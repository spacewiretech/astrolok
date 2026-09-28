import {
  CashfreeError,
  cashfreeSettings,
  CashfreeSettings,
  constantTimeEquals,
  fetchSubscription,
  fetchSubscriptionPayments,
  retrySubscriptionPayment,
  settingsForPlan,
  snapshotOf,
} from "../_shared/cashfree.ts";
import { configFlag, configSetting, loadConfig } from "../_shared/config.ts";
import { corsHeaders, json } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/db.ts";
import { configureMixpanel, trackServer } from "../_shared/mixpanel.ts";
import {
  isInsufficientFunds,
  istDate,
  planRetry,
  RetryPlan,
  retryPolicy,
  RetryPolicy,
} from "../_shared/payment_retry.ts";

/**
 * Retries debits that failed for insufficient funds. The schedule is in `_shared/payment_retry.ts`
 * and the cron job in `20260928000003_payment_retries.sql`.
 *
 * Each run does three things, in order:
 *
 *   1. resolve  — closes requested attempts whose result has arrived, reports each one, and plans
 *                 the next attempt for a charge that failed for insufficient funds again;
 *   2. enqueue  — starts a chain for every newly failed charge (and, when configured, the backlog
 *                 that failed before retries existed);
 *   3. send     — asks Cashfree to retry the pending attempts, after checking with Cashfree that
 *                 the mandate is still ACTIVE.
 *
 * It never touches the webhook path. A retried charge that succeeds arrives as an ordinary charge
 * webhook, and is credited and reported like any other debit.
 *
 * Body (all optional):
 *   {"probe": "<subscription_id>"}  read-only: what Cashfree says about that mandate's charges
 *   {"dry_run": true}               plan without writing or sending
 *   {"only": ["<subscription_id>"]} act on these mandates only, even while switched off
 *   {"backlog_base": "YYYY-MM-DD"}  with `only`: schedule their old failures from this day
 *   {"limit": n}                    most retries to send this run
 */

/** Stops claiming new work past this, so a run always answers inside the cron's 55 s timeout. */
const TIME_BUDGET_MS = 40_000;
/** Three at a time: at five, Cashfree answered 429 to about a third of the backlog's calls. */
const CONCURRENCY = 3;
/** Transient Cashfree failures an attempt may have before it is given up as rejected. */
const MAX_SENDS = 5;
const ENQUEUE_LIMIT = 3000;
/** Far enough ahead that no failure counts as new when `cashfree_retry_since` is blank. */
const NEVER = "9999-01-01T00:00:00Z";

type Row = Record<string, unknown>;

/** Set once Cashfree answers 429 in this run; the workers stop sending. Reset per request. */
let throttled = false;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const db = serviceClient();
  const config = await loadConfig(db);
  configureMixpanel(config, "payment-retry");

  // Same caller as the reconcile, same secret. Fail closed: without it anyone could make us ask
  // Cashfree to debit people.
  const expected = configSetting(config, "reconcile_secret");
  const provided = req.headers.get("x-reconcile-secret") ?? "";
  if (!expected || !constantTimeEquals(expected, provided)) {
    return new Response("forbidden", { status: 403, headers: corsHeaders });
  }

  let settings: CashfreeSettings;
  try {
    settings = cashfreeSettings(config);
  } catch (error) {
    console.error("payment-retry cannot run: settings unavailable", error);
    return new Response("payments not configured", { status: 503, headers: corsHeaders });
  }

  const body = await req.json().catch(() => ({})) as Row;

  if (typeof body.probe === "string" && body.probe) {
    return json(await probe(db, settings, body.probe, body.account));
  }

  const only = Array.isArray(body.only)
    ? body.only.filter((id): id is string => typeof id === "string" && id.length > 0)
    : null;
  const dryRun = body.dry_run === true;

  // A targeted run is allowed while switched off: it is how the retry is tried on one mandate
  // before it is let loose on all of them.
  if (!configFlag(config, "cashfree_retry_enabled") && !only) {
    return json({ enabled: false });
  }

  const started = Date.now();
  throttled = false;
  const now = new Date();
  const today = istDate(now);
  const policy = retryPolicy(config);
  const apiVersion = configSetting(config, "cashfree_retry_api_version");
  const batch = Math.min(
    Number(body.limit) > 0 ? Number(body.limit) : Number(configSetting(config, "cashfree_retry_batch")) || 100,
    500,
  );

  const sinceSetting = configSetting(config, "cashfree_retry_since");
  const since = sinceSetting && !Number.isNaN(Date.parse(sinceSetting))
    ? new Date(sinceSetting).toISOString()
    : NEVER;
  const backlogBase = dateOrNull(only && typeof body.backlog_base === "string"
    ? body.backlog_base
    : configSetting(config, "cashfree_retry_backlog_base"));

  const summary = {
    today,
    dry_run: dryRun,
    resolved: { succeeded: 0, failed: 0, ended: 0 },
    enqueued: 0,
    skipped: 0,
    sent: { requested: 0, rejected: 0, ended: 0, skipped: 0, deferred: 0 },
    errors: [] as string[],
    plans: [] as Row[],
  };

  // ------------------------------------------------------------ 1. resolve

  if (!dryRun) {
    const { data: resolved, error } = await db.rpc("payment_retry_resolve");
    if (error) {
      console.error("payment_retry_resolve failed", error);
      summary.errors.push(`resolve: ${error.message}`);
    }
    const next: Row[] = [];
    for (const row of (resolved ?? []) as Row[]) {
      const status = String(row.status);
      if (status === "succeeded") summary.resolved.succeeded++;
      else if (status === "failed") summary.resolved.failed++;
      else summary.resolved.ended++;

      const again = status === "failed" && isInsufficientFunds(row.result_reason as string);
      const plan = again
        ? planRetry(Number(row.attempt) + 1, String(row.base_date), today, dateOrNull(row.regular_next_date), policy)
        : null;
      const final = !plan || "skip" in plan;

      await trackServer({
        event: status === "succeeded"
          ? "Payment Retry Succeeded"
          : status === "failed"
          ? "Payment Retry Failed"
          : "Payment Retry Ended",
        distinctId: String(row.user_id),
        insertId: `retry:${row.cf_payment_id}:${row.attempt}:${status}`,
        time: String(row.resolved_at),
        properties: {
          ...chainProps(row),
          result_reason: row.result_reason ?? null,
          final: status === "succeeded" || final,
          hours_since_request: row.requested_at
            ? Math.round((now.getTime() - Date.parse(String(row.requested_at))) / 3_600_000)
            : null,
        },
      });

      if (plan) next.push(attemptRow(row, plan, String(row.next_payment_id ?? row.payment_id ?? "")));
    }
    if (next.length > 0) {
      const inserted = await insertAttempts(db, next, summary);
      await reportSkips(inserted);
    }
  }

  // ------------------------------------------------------------ 2. enqueue

  if (since !== NEVER || backlogBase) {
    const { data: candidates, error } = await db.rpc("payment_retry_candidates", {
      p_since: since,
      p_backlog_base: backlogBase,
      p_limit: ENQUEUE_LIMIT,
      p_only: only,
    });
    if (error) {
      console.error("payment_retry_candidates failed", error);
      summary.errors.push(`candidates: ${error.message}`);
    }

    const rows = ((candidates ?? []) as Row[]).map((c) => {
      const regularNext = c.next_schedule_date ? istDate(new Date(String(c.next_schedule_date))) : null;
      const plan = planRetry(1, String(c.base_date), today, regularNext, policy);
      return attemptRow({ ...c, regular_next_date: regularNext }, plan, String(c.payment_id));
    });

    if (dryRun) {
      summary.enqueued = rows.length;
      summary.plans = rows.slice(0, 20).map((r) => ({
        subscription_id: r.subscription_id,
        base_date: r.base_date,
        scheduled_for: r.scheduled_for,
        status: r.status,
        backlog: r.backlog,
      }));
      return json({ ...summary, by_date: countBy(rows, (r) => String(r.scheduled_for ?? r.result_reason)) });
    }

    if (rows.length > 0) {
      const inserted = await insertAttempts(db, rows, summary);
      summary.enqueued = inserted.filter((r) => r.status === "pending").length;
      await reportSkips(inserted);
    }
  }

  if (dryRun) return json(summary);

  // ------------------------------------------------------------ 3. send

  const { data: claimed, error: claimError } = await db.rpc("payment_retry_claim", {
    p_limit: batch,
    p_only: only,
  });
  if (claimError) {
    console.error("payment_retry_claim failed", claimError);
    summary.errors.push(`claim: ${claimError.message}`);
  }

  const queue = [...((claimed ?? []) as Row[])];
  const unsent: string[] = [];

  const worker = async () => {
    while (queue.length > 0) {
      const row = queue.shift()!;
      // Out of time, or Cashfree has started answering 429: stop, and leave the rest for the next
      // run rather than pressing on into the limit.
      if (Date.now() - started > TIME_BUDGET_MS || throttled) {
        unsent.push(String(row.id));
        continue;
      }
      try {
        const outcome = await send(db, settings, apiVersion, policy, today, row);
        summary.sent[outcome]++;
      } catch (error) {
        // Only a database write can land here. Leave the row in `sending`: it is handed out again
        // in ten minutes, and the idempotency key makes a resend safe.
        summary.errors.push(`${row.subscription_id}: ${error}`);
      }
    }
  };
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));

  // Out of time: give the rest straight back instead of making them wait out the claim.
  if (unsent.length > 0) {
    await db.from("payment_retries")
      .update({ status: "pending", claimed_at: null })
      .in("id", unsent);
    summary.sent.deferred += unsent.length;
  }

  if (summary.errors.length > 0) console.error("payment-retry errors", summary.errors.slice(0, 20));
  return json({ ...summary, plans: undefined, throttled, errors: summary.errors.slice(0, 20) });
});

// ------------------------------------------------------------------------------------------------

type SendOutcome = "requested" | "rejected" | "ended" | "skipped" | "deferred";

/**
 * One attempt: check the mandate with Cashfree, re-plan against today and the real regular charge
 * date, then ask for the retry.
 */
async function send(
  db: ReturnType<typeof serviceClient>,
  settings: CashfreeSettings,
  apiVersion: string,
  policy: RetryPolicy,
  today: string,
  row: Row,
): Promise<SendOutcome> {
  const account = settingsForPlan(settings, row.plan_id as string | null);
  const subscriptionId = String(row.subscription_id);

  // Asked of Cashfree, not of our row: the reconcile can run days behind, and retrying a mandate
  // the user revoked yesterday would only fail and send them a pre-debit notice for nothing.
  let snapshot;
  try {
    snapshot = snapshotOf(await fetchSubscription(account, subscriptionId));
  } catch (error) {
    return await failSend(db, row, error, "fetch");
  }

  if (snapshot.status !== "ACTIVE") {
    await update(db, row, {
      status: "ended",
      result_reason: `mandate ${snapshot.status}`,
      resolved_at: new Date().toISOString(),
      error: null,
    });
    await trackServer({
      event: "Payment Retry Ended",
      distinctId: String(row.user_id),
      insertId: `retry:${row.cf_payment_id}:${row.attempt}:ended`,
      properties: { ...chainProps(row), result_reason: `mandate ${snapshot.status}`, final: true },
    });
    return "ended";
  }

  // The regular next debit. Attempt 1 reads it fresh from Cashfree, before any retry of ours could
  // move it, and the later attempts inherit what attempt 1 saw.
  const fresh = snapshot.nextScheduleDate ? istDate(new Date(snapshot.nextScheduleDate)) : null;
  const regularNext = Number(row.attempt) === 1
    ? fresh ?? dateOrNull(row.regular_next_date)
    : dateOrNull(row.regular_next_date) ?? fresh;

  const plan = planRetry(Number(row.attempt), String(row.base_date), today, regularNext, policy);
  if ("skip" in plan) {
    await update(db, row, {
      status: "skipped",
      scheduled_for: null,
      regular_next_date: regularNext,
      result_reason: plan.skip,
      resolved_at: new Date().toISOString(),
    });
    await reportSkips([{ ...row, status: "skipped", result_reason: plan.skip, regular_next_date: regularNext }]);
    return "skipped";
  }

  const retrySettings = apiVersion ? { ...account, apiVersion } : account;
  let response: Record<string, unknown>;
  try {
    response = await retrySubscriptionPayment(
      retrySettings,
      subscriptionId,
      String(row.payment_id),
      plan.date,
      `retry_${row.cf_payment_id}_${row.attempt}`,
    );
  } catch (error) {
    return await failSend(db, row, error, "retry");
  }

  const requestedAt = new Date().toISOString();
  const retryPaymentId = response.cf_payment_id != null
    ? String(response.cf_payment_id)
    : String(row.cf_payment_id);

  await update(db, row, {
    status: "requested",
    scheduled_for: plan.date,
    regular_next_date: regularNext,
    requested_at: requestedAt,
    retry_cf_payment_id: retryPaymentId,
    response: pick(response, [
      "payment_id",
      "cf_payment_id",
      "payment_status",
      "payment_type",
      "payment_amount",
      "retry_attempts",
      "payment_schedule_date",
      "payment_initiated_date",
      "failure_details",
    ]),
    error: null,
  });

  await trackServer({
    event: "Payment Retry Scheduled",
    distinctId: String(row.user_id),
    insertId: `retry:${row.cf_payment_id}:${row.attempt}:requested`,
    time: requestedAt,
    properties: {
      ...chainProps({ ...row, scheduled_for: plan.date, regular_next_date: regularNext }),
      same_payment: retryPaymentId === String(row.cf_payment_id),
      cf_retry_attempts: response.retry_attempts ?? null,
    },
  });
  return "requested";
}

/**
 * A Cashfree call that did not go through. Transient failures go back to `pending` for the next
 * run, up to [MAX_SENDS]; anything else is Cashfree refusing, and asking again changes nothing.
 */
async function failSend(
  db: ReturnType<typeof serviceClient>,
  row: Row,
  error: unknown,
  step: string,
): Promise<SendOutcome> {
  const detail = `${step}: ${error instanceof Error ? error.message : String(error)}`.slice(0, 500);
  const transient = error instanceof CashfreeError && error.isTransient;

  // A rate limit is Cashfree asking us to slow down, not refusing this retry. It never counts
  // toward MAX_SENDS: on the first backlog run it rejected four attempts that were never refused.
  const rateLimited = error instanceof CashfreeError && error.status === 429;
  if (rateLimited) throttled = true;

  if (rateLimited || (transient && Number(row.send_attempts) < MAX_SENDS)) {
    await update(db, row, { status: "pending", claimed_at: null, error: detail });
    return "deferred";
  }

  await update(db, row, { status: "rejected", error: detail, resolved_at: new Date().toISOString() });
  await trackServer({
    event: "Payment Retry Rejected",
    distinctId: String(row.user_id),
    insertId: `retry:${row.cf_payment_id}:${row.attempt}:rejected`,
    properties: { ...chainProps(row), error: detail.slice(0, 200), final: true },
  });
  return "rejected";
}

async function update(db: ReturnType<typeof serviceClient>, row: Row, patch: Row): Promise<void> {
  const { error } = await db.from("payment_retries").update(patch).eq("id", row.id);
  if (error) throw new Error(`payment_retries update failed: ${error.message}`);
}

// ------------------------------------------------------------------------------------------------

/** The row for one attempt of a chain, from a candidate or from the attempt before it. */
function attemptRow(source: Row, plan: RetryPlan, paymentId: string): Row {
  const skip = "skip" in plan;
  return {
    subscription_pk: source.subscription_pk,
    user_id: source.user_id,
    subscription_id: source.subscription_id,
    plan_id: source.plan_id ?? null,
    cf_payment_id: source.cf_payment_id,
    payment_id: paymentId,
    amount: source.amount ?? null,
    attempt: plan.attempt,
    base_date: source.base_date,
    backlog: source.backlog === true,
    scheduled_for: skip ? null : plan.date,
    regular_next_date: dateOrNull(source.regular_next_date),
    status: skip ? "skipped" : "pending",
    result_reason: skip ? plan.skip : null,
    resolved_at: skip ? new Date().toISOString() : null,
  };
}

/** Inserts attempts, ignoring any that already exist; returns only the rows actually written. */
async function insertAttempts(
  db: ReturnType<typeof serviceClient>,
  rows: Row[],
  summary: { errors: string[]; skipped: number },
): Promise<Row[]> {
  const written: Row[] = [];
  // Chunked: the backlog is thousands of rows, and one oversized request failing loses them all.
  for (let i = 0; i < rows.length; i += 500) {
    const { data, error } = await db
      .from("payment_retries")
      .upsert(rows.slice(i, i + 500), { onConflict: "cf_payment_id,attempt", ignoreDuplicates: true })
      .select();
    if (error) {
      console.error("payment_retries insert failed", error);
      summary.errors.push(`insert: ${error.message}`);
      continue;
    }
    written.push(...((data ?? []) as Row[]));
  }
  summary.skipped += written.filter((r) => r.status === "skipped").length;
  return written;
}

async function reportSkips(rows: Row[]): Promise<void> {
  const skipped = rows.filter((r) => r.status === "skipped");
  if (skipped.length === 0) return;
  await trackServer(skipped.map((row) => ({
    event: "Payment Retry Skipped",
    distinctId: String(row.user_id),
    insertId: `retry:${row.cf_payment_id}:${row.attempt}:skipped`,
    properties: { ...chainProps(row), result_reason: row.result_reason ?? null, final: true },
  })));
}

/** What every retry event carries, so a chain can be followed attempt by attempt. */
function chainProps(row: Row): Row {
  return {
    subscription_id: row.subscription_id,
    cf_payment_id: row.cf_payment_id,
    attempt: Number(row.attempt),
    base_date: row.base_date ?? null,
    scheduled_for: row.scheduled_for ?? null,
    regular_next_date: row.regular_next_date ?? null,
    backlog: row.backlog === true,
    amount: row.amount != null ? Number(row.amount) : null,
    plan_id: row.plan_id ?? null,
  };
}

/**
 * Read-only: what Cashfree holds for one mandate's charges, without the payer's UPI details.
 * Used to check the ids and statuses a retry works with before sending one.
 *
 * [accountOverride] "current" or "legacy" asks with that account's credentials instead of the
 * plan's routing, to find out which account a mandate actually lives in.
 */
async function probe(
  db: ReturnType<typeof serviceClient>,
  settings: CashfreeSettings,
  subscriptionId: string,
  accountOverride?: unknown,
): Promise<Row> {
  const { data: row } = await db.from("subscriptions").select("plan_id")
    .eq("subscription_id", subscriptionId).maybeSingle();
  const account = accountOverride === "current"
    ? settings
    : accountOverride === "legacy" && settings.legacy
    ? { ...settings, appId: settings.legacy.appId, secret: settings.legacy.secret }
    : settingsForPlan(settings, row?.plan_id as string | null);
  try {
    const snapshot = snapshotOf(await fetchSubscription(account, subscriptionId));
    const payments = await fetchSubscriptionPayments(account, subscriptionId);
    return {
      status: snapshot.status,
      next_schedule_date: snapshot.nextScheduleDate,
      payments: payments.map((p) =>
        pick(p.raw, [
          "payment_id",
          "cf_payment_id",
          "payment_type",
          "payment_status",
          "payment_amount",
          "retry_attempts",
          "payment_schedule_date",
          "payment_initiated_date",
          "failure_details",
        ])
      ),
    };
  } catch (error) {
    return { error: String(error) };
  }
}

function pick(source: Record<string, unknown>, keys: string[]): Row {
  const out: Row = {};
  for (const key of keys) if (source[key] !== undefined) out[key] = source[key];
  return out;
}

function dateOrNull(value: unknown): string | null {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}/.test(value) ? value.slice(0, 10) : null;
}

function countBy(rows: Row[], key: (row: Row) => string): Record<string, number> {
  const out: Record<string, number> = {};
  for (const row of rows) out[key(row)] = (out[key(row)] ?? 0) + 1;
  return out;
}
