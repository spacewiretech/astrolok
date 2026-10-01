import { cashfreeSettings, CashfreeSettings, disputeFrom, paymentFrom, refundFrom } from "../_shared/cashfree.ts";
import { AppConfig, configFlag, loadConfig } from "../_shared/config.ts";
import { corsHeaders, json } from "../_shared/cors.ts";
import { eachBounded, inBackground } from "../_shared/background.ts";
import { isCronRequest } from "../_shared/cron_auth.ts";
import { serviceClient } from "../_shared/db.ts";
import { configureFacebookCapi } from "../_shared/facebook_capi.ts";
import { configureMixpanel } from "../_shared/mixpanel.ts";
import { configureNotifications } from "../_shared/notify.ts";
import {
  chargesToRecord,
  chunked,
  groupPendingEvents,
  paymentIdsOf,
  PendingEvent,
} from "../_shared/payment_sync.ts";
import {
  asSubscriptionRow,
  recordDispute,
  recordPayment,
  recordRefund,
  SUBSCRIPTION_COLUMNS,
  SubscriptionRow,
  syncSubscription,
} from "../_shared/subscription_sync.ts";

/**
 * Processes the Cashfree webhooks `cashfree-webhook` queued, every minute (pg_cron job
 * `payment-sync-1min`, `20260929000001_payment_sync.sql`).
 *
 * The same money path the webhook used to run inline, per subscription rather than per delivery:
 * each charge the ledger does not already hold at that status goes through `recordPayment`, then the
 * subscription is synced from Cashfree once. The webhook only queues while `cashfree_webhook_batch`
 * is on. While it is off this picks up only a verified delivery left unprocessed for five minutes,
 * one whose inline run died.
 *
 * A group that fails stays queued, with its error, and is claimed again next run, up to
 * [MAX_ATTEMPTS]. That replaces Cashfree's own retries, which the webhook no longer asks for.
 */

type Db = ReturnType<typeof serviceClient>;

/** Deliveries claimed per pass. About 45 arrive per minute at the daytime peak. */
const CLAIM_LIMIT = 500;

/** A claim older than this belongs to a run that died, and is taken again. */
const STALE_MINUTES = 10;

/** Claims before a delivery is given up on: an hour of runs. The hourly reconcile still sweeps. */
const MAX_ATTEMPTS = 12;

/** Subscriptions synced at once. Cashfree answered 429 to a third of calls at 5 (2026-09-28). */
const CONCURRENCY = 3;

/**
 * Past this no new subscription is started, so a run is done before the next minute's begins.
 * Two runs at once would be safe (their claims never overlap) but would double the calls on
 * Cashfree.
 */
const RUN_BUDGET_MS = 50_000;

/** While the switch is off: how long a delivery must sit unprocessed before this takes it over. */
const INLINE_GRACE_SECONDS = 300;

/** `in (...)` filters per request, so the URL stays short: our subscription ids are 47 characters. */
const READ_CHUNK = 100;

interface Tally {
  claimed: number;
  subscriptions: number;
  charges: number;
  repeats: number;
  done: number;
  unknown: number;
  failed: number;
  released: number;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const db = serviceClient();
  const config = await loadConfig(db);
  if (!isCronRequest(req, config)) return new Response("forbidden", { status: 403, headers: corsHeaders });

  configureMixpanel(config, "payment-sync");
  configureNotifications(config, "payment-sync");
  configureFacebookCapi(config, "payment-sync");

  let settings: CashfreeSettings;
  try {
    settings = cashfreeSettings(config);
  } catch (error) {
    console.error("payment-sync cannot run: settings unavailable", error);
    return new Response("payments not configured", { status: 503, headers: corsHeaders });
  }

  // pg_cron waits ten seconds for an answer; the batch takes longer, so it runs after the response.
  await inBackground("payment-sync run", run(db, config, settings));
  return json({ accepted: true }, 202);
});

async function run(db: Db, config: AppConfig, settings: CashfreeSettings): Promise<void> {
  const startedAt = Date.now();
  const deadline = startedAt + RUN_BUDGET_MS;
  const minAge = configFlag(config, "cashfree_webhook_batch") ? 0 : INLINE_GRACE_SECONDS;
  const tally: Tally = {
    claimed: 0,
    subscriptions: 0,
    charges: 0,
    repeats: 0,
    done: 0,
    unknown: 0,
    failed: 0,
    released: 0,
  };

  while (Date.now() < deadline) {
    const { data, error } = await db.rpc("claim_payment_events", {
      p_limit: CLAIM_LIMIT,
      p_stale_minutes: STALE_MINUTES,
      p_max_attempts: MAX_ATTEMPTS,
      p_min_age_seconds: minAge,
    });
    if (error) {
      console.error("payment-sync: claim failed", error);
      break;
    }

    const events = (data ?? []) as PendingEvent[];
    if (events.length === 0) break;
    tally.claimed += events.length;

    await processBatch(db, settings, events, deadline, tally);
    if (events.length < CLAIM_LIMIT) break;
  }

  console.log(`payment-sync: ${JSON.stringify(tally)} in ${Date.now() - startedAt}ms`);
}

async function processBatch(
  db: Db,
  settings: CashfreeSettings,
  events: PendingEvent[],
  deadline: number,
  tally: Tally,
): Promise<void> {
  const done: number[] = [];

  // Refunds and disputes name a payment, not a subscription. The webhook still handles them inline;
  // one only lands here if that run died.
  const subscriptionScoped: PendingEvent[] = [];
  for (const event of events) {
    const refund = event.payload ? refundFrom(event.payload) : null;
    const dispute = !refund && event.payload ? disputeFrom(event.payload) : null;
    if (!refund && !dispute) {
      subscriptionScoped.push(event);
      continue;
    }
    try {
      if (refund) await recordRefund(db, settings, refund);
      else if (dispute) await recordDispute(db, settings, dispute);
      done.push(event.id);
    } catch (error) {
      await markFailed(db, [event], error, tally);
    }
  }

  let lookups;
  try {
    lookups = await readAhead(db, subscriptionScoped);
  } catch (error) {
    // Nothing is known about these yet, so nothing is marked. Released to the next run instead.
    console.error("payment-sync: read-ahead failed", error);
    await release(db, subscriptionScoped, tally);
    await markDone(db, done, tally);
    return;
  }

  const { bySubscription, unresolved } = groupPendingEvents(subscriptionScoped, lookups.localByCfId);
  // Names nothing we own and nothing a refund or dispute could reach: settlement notices, one-time
  // order events, pre-debit reminders. Acknowledged, as the webhook always has.
  done.push(...unresolved.map((event) => event.id));

  const groups = [...bySubscription.entries()];
  const started = new Set<string>();
  const unknown: number[] = [];

  await eachBounded(groups, { concurrency: CONCURRENCY, deadline }, async ([subscriptionId, group]) => {
    started.add(subscriptionId);
    const row = lookups.rows.get(subscriptionId);
    if (!row) {
      // A mandate Cashfree knows about and we do not: almost always another environment's webhook.
      console.error(`payment-sync: webhook for unknown subscription ${subscriptionId}`);
      unknown.push(...group.map((event) => event.id));
      return;
    }

    try {
      const charges = chargesToRecord(group, lookups.ledger);
      tally.repeats += group.filter((event) => event.payload && paymentFrom(event.payload)).length - charges.length;
      for (const { event, payment } of charges) {
        await recordPayment(db, settings, row, payment, event.event_type);
        tally.charges += 1;
      }

      // The authoritative step, once for however many deliveries named this subscription.
      await syncSubscription(db, settings, subscriptionId);
      tally.subscriptions += 1;
      done.push(...group.map((event) => event.id));
    } catch (error) {
      await markFailed(db, group, error, tally);
    }
  });

  // Past the deadline: handed straight to the next run rather than left locked for STALE_MINUTES.
  const unstarted = groups.filter(([id]) => !started.has(id)).flatMap(([, group]) => group);
  await release(db, unstarted, tally);

  await markDone(db, done, tally);
  if (unknown.length > 0) {
    for (const ids of chunked(unknown, READ_CHUNK)) {
      await db.from("payment_events")
        .update({ processed_at: new Date().toISOString(), process_error: "unknown subscription", locked_at: null })
        .in("id", ids);
    }
    tally.unknown += unknown.length;
  }
}

/** One read each, per batch, for what every delivery in it would otherwise read on its own. */
async function readAhead(db: Db, events: PendingEvent[]): Promise<{
  localByCfId: Map<string, string>;
  rows: Map<string, SubscriptionRow>;
  ledger: Map<string, string>;
}> {
  const localByCfId = new Map<string, string>();
  const cfOnly = [
    ...new Set(
      events.filter((event) => !event.subscription_id && event.cf_subscription_id)
        .map((event) => event.cf_subscription_id as string),
    ),
  ];
  for (const ids of chunked(cfOnly, READ_CHUNK)) {
    const { data, error } = await db.from("subscriptions")
      .select("subscription_id, cf_subscription_id")
      .in("cf_subscription_id", ids);
    if (error) throw new Error(`subscriptions by cf id: ${error.message}`);
    for (const row of data ?? []) localByCfId.set(String(row.cf_subscription_id), String(row.subscription_id));
  }

  const subscriptionIds = [
    ...new Set(
      events.map((event) =>
        event.subscription_id ?? (event.cf_subscription_id ? localByCfId.get(event.cf_subscription_id) : undefined)
      ).filter((id): id is string => !!id),
    ),
  ];
  const rows = new Map<string, SubscriptionRow>();
  for (const ids of chunked(subscriptionIds, READ_CHUNK)) {
    const { data, error } = await db.from("subscriptions").select(SUBSCRIPTION_COLUMNS).in("subscription_id", ids);
    if (error) throw new Error(`subscriptions: ${error.message}`);
    for (const raw of data ?? []) {
      const row = asSubscriptionRow(raw);
      rows.set(row.subscription_id, row);
    }
  }

  const ledger = new Map<string, string>();
  for (const ids of chunked(paymentIdsOf(events), READ_CHUNK)) {
    const { data, error } = await db.from("subscription_payments").select("cf_payment_id, status").in(
      "cf_payment_id",
      ids,
    );
    if (error) throw new Error(`subscription_payments: ${error.message}`);
    for (const row of data ?? []) ledger.set(String(row.cf_payment_id), String(row.status));
  }

  return { localByCfId, rows, ledger };
}

async function markDone(db: Db, ids: number[], tally: Tally): Promise<void> {
  for (const chunk of chunked(ids, READ_CHUNK)) {
    const { error } = await db.from("payment_events")
      .update({ processed_at: new Date().toISOString(), process_error: null, locked_at: null })
      .in("id", chunk);
    // Left claimed, so taken again after STALE_MINUTES. Everything above is idempotent, so the cost
    // of that is a second sync, not a second charge.
    if (error) console.error("payment-sync: could not mark processed", error);
  }
  tally.done += ids.length;
}

async function release(db: Db, events: PendingEvent[], tally: Tally): Promise<void> {
  for (const chunk of chunked(events.map((event) => event.id), READ_CHUNK)) {
    await db.from("payment_events").update({ locked_at: null }).in("id", chunk);
  }
  tally.released += events.length;
}

/** Keeps the error on the rows, and gives up on the ones that have used their attempts. */
async function markFailed(db: Db, events: PendingEvent[], error: unknown, tally: Tally): Promise<void> {
  const detail = String(error).slice(0, 500);
  console.error(`payment-sync: ${events[0]?.subscription_id ?? events[0]?.id} failed: ${detail}`);
  const spent = events.filter((event) => event.attempts >= MAX_ATTEMPTS).map((event) => event.id);
  const retry = events.filter((event) => event.attempts < MAX_ATTEMPTS).map((event) => event.id);
  if (retry.length > 0) {
    await db.from("payment_events").update({ process_error: detail, locked_at: null }).in("id", retry);
  }
  if (spent.length > 0) {
    await db.from("payment_events")
      .update({
        processed_at: new Date().toISOString(),
        process_error: `gave up after ${MAX_ATTEMPTS} attempts: ${detail}`,
        locked_at: null,
      })
      .in("id", spent);
  }
  tally.failed += events.length;
}
