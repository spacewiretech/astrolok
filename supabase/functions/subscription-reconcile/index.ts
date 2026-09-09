import { cashfreeSettings } from "../_shared/cashfree.ts";
import { configSetting, loadConfig } from "../_shared/config.ts";
import { configureMixpanel } from "../_shared/mixpanel.ts";
import { corsHeaders, json } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/db.ts";
import { constantTimeEquals } from "../_shared/cashfree.ts";
import {
  refreshPaymentTotals,
  staleSweepCutoff,
  syncSubscription,
} from "../_shared/subscription_sync.ts";

/**
 * The safety net under the webhook. The schedule lives in `0003_reconcile.sql`, which points the
 * job at this project's own URL — the one detail that does not survive being copied between
 * projects, and the one worth reading twice when two deployments share a Cashfree account.
 *
 * Webhooks get lost — endpoints are briefly down, deliveries are dropped, a deploy lands at the
 * wrong moment, the merchant account's webhook URL names a different project entirely. Without
 * this, a user whose ₹499 was debited during that window would sit in `trial` until it expired
 * and then be told to pay again, and a user who cancelled would keep their access to the end of
 * the cycle with nothing recording that they had gone. Here we go and ask.
 */

/** Bounded so one run cannot exceed the function timeout on a large backlog. */
const BATCH = 100;

/**
 * The staleness sweep's own, much smaller, budget.
 *
 * The two sweeps below it are driven by events that are rare — an overdue schedule, an unconverted
 * trial. This one is driven by the clock, so on a healthy account base every live mandate is
 * eventually a candidate. Left at BATCH it would fetch 100 subscriptions from Cashfree every hour
 * whether or not anything was wrong; at 25 it round-robins through the base a slice at a time and
 * the sweep stays cheap enough to leave on forever.
 */
const STALE_BATCH = 25;

/** Hours a live mandate may go unchecked before the sweep asks Cashfree about it anyway. */
const DEFAULT_STALE_HOURS = 6;

/** Cashfree states in which a schedule can still fire, so drift is worth checking for. */
const LIVE = ["ACTIVE", "ON_HOLD", "PAUSED", "PENDING_AUTHORIZATION", "INITIALIZED"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const db = serviceClient();
  const config = await loadConfig(db);
  configureMixpanel(config, "subscription-reconcile");

  // Fail closed: with no secret configured this endpoint would be an open invitation to make
  // us hammer Cashfree on demand.
  const expected = configSetting(config, "reconcile_secret");
  const provided = req.headers.get("x-reconcile-secret") ?? "";
  if (!expected || !constantTimeEquals(expected, provided)) {
    return new Response("forbidden", { status: 403, headers: corsHeaders });
  }

  let settings;
  try {
    settings = cashfreeSettings(config);
  } catch (error) {
    console.error("reconcile cannot run: settings unavailable", error);
    return new Response("payments not configured", { status: 503, headers: corsHeaders });
  }

  const now = new Date();
  const nowIso = now.toISOString();

  // Cheap first pass, no network: close out checkouts whose session token has expired without
  // the user ever reaching the UPI sheet. These can never become active on their own.
  const { count: abandoned } = await db
    .from("subscriptions")
    .update({ status: "ABANDONED" }, { count: "exact" })
    .in("status", ["INITIALIZED", "PENDING_AUTHORIZATION"])
    .lt("session_expiry", nowIso);

  // A schedule that should have fired an hour ago and produced no webhook is drift worth
  // chasing. The hour of slack keeps the sweep off charges that are simply still settling.
  const overdue = new Date(now.getTime() - 60 * 60 * 1000).toISOString();

  const { data: drifted, error } = await db
    .from("subscriptions")
    .select("subscription_id")
    .in("status", LIVE)
    .not("next_schedule_date", "is", null)
    .lt("next_schedule_date", overdue)
    .order("next_schedule_date", { ascending: true })
    .limit(BATCH);

  if (error) {
    console.error("reconcile candidate query failed", error);
    return new Response("query failed", { status: 500, headers: corsHeaders });
  }

  // Trials that should have converted by now: the first ₹499 was due, the grace has run out,
  // and the account is still sitting in `trial`. Either the debit failed — in which case the
  // paywall is correct — or its webhook went missing, which this repairs.
  const graceAgo = new Date(
    now.getTime() - Number(configSetting(config, "entitlement_grace_hours") || 12) * 3600_000,
  ).toISOString();

  const { data: staleTrials } = await db
    .from("users")
    .select("active_subscription_id")
    .eq("payment_type", "trial")
    .not("trial_ends_at", "is", null)
    .not("active_subscription_id", "is", null)
    .lt("trial_ends_at", graceAgo)
    .limit(BATCH);

  const ids = new Set<string>();
  for (const row of drifted ?? []) ids.add(row.subscription_id as string);
  for (const row of staleTrials ?? []) ids.add(row.active_subscription_id as string);

  // Live mandates nobody has asked Cashfree about lately.
  //
  // The two queries above both start from a debit that should have happened. Neither can see a
  // mandate that quietly stopped being live: a user cancelling UPI Autopay in their PSP app lands
  // it in `CUSTOMER_CANCELLED` at Cashfree, and the only thing that ever told us was the webhook.
  // When that delivery is dropped — or registered against a different project — the row sits here
  // as ACTIVE with a `next_schedule_date` weeks out, matching nothing, while the account keeps
  // full access and the churn event never fires.
  //
  // `updated_at` is the free "last checked" marker: the trigger on `subscriptions` bumps it and
  // `syncSubscription` always writes its patch, so oldest-first is a round-robin over the base
  // with no extra column and no cursor to keep.
  const staleBefore = staleSweepCutoff(
    configSetting(config, "reconcile_stale_hours"),
    now,
    DEFAULT_STALE_HOURS,
  );
  const staleIds = new Set<string>();

  if (staleBefore) {
    const { data: unchecked } = await db
      .from("subscriptions")
      .select("subscription_id")
      .in("status", LIVE)
      .lt("updated_at", staleBefore)
      .order("updated_at", { ascending: true })
      .limit(STALE_BATCH);

    // Anything the queries above already claimed is dropped here rather than synced twice: they
    // ask for the payments list as well, which is the more thorough of the two passes.
    for (const row of unchecked ?? []) {
      const id = row.subscription_id as string;
      if (!ids.has(id)) staleIds.add(id);
    }
  }

  let synced = 0;
  const failures: string[] = [];

  // withPayments: the first pass exists for the case where a webhook never arrived, and the
  // subscription snapshot alone cannot tell us a ₹499 was taken. Only the payments list can, and
  // without it a debited user still lapses. The staleness pass wants only the status word — a
  // cancellation is visible in the snapshot — so it skips the second Cashfree call.
  const passes: Array<[Set<string>, boolean]> = [[ids, true], [staleIds, false]];

  for (const [batch, withPayments] of passes) {
    for (const id of batch) {
      try {
        const result = await syncSubscription(db, settings, id, 0, withPayments);
        // Denormalised counters are recomputed from the ledger, so anything that drifted — a
        // partial write, a charge recorded before these columns existed — is repaired here
        // rather than staying wrong forever. Pointless when no payments were fetched: the
        // ledger cannot have changed under us.
        if (withPayments) await refreshPaymentTotals(db, result.subscription.user_id);
        synced++;
      } catch (err) {
        // One bad subscription must not abort the batch — the rest still need reconciling.
        failures.push(`${id}: ${err}`);
      }
    }
  }

  if (failures.length > 0) console.error("reconcile failures", failures);

  return json({
    checked: ids.size + staleIds.size,
    synced,
    // Reported separately so a run can be read at a glance: `stale` climbing while `checked`
    // stays flat is the signal that webhook deliveries are going missing.
    stale: staleIds.size,
    abandoned: abandoned ?? 0,
    failed: failures.length,
  });
});
