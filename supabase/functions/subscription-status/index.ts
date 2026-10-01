import { cashfreeSettings } from "../_shared/cashfree.ts";
import { loadConfig } from "../_shared/config.ts";
import { configureFacebookCapi } from "../_shared/facebook_capi.ts";
import { configureMixpanel } from "../_shared/mixpanel.ts";
import { configureNotifications } from "../_shared/notify.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { callerForBearer, serviceClient } from "../_shared/db.ts";
import {
  callerUserRow,
  entitlementPayload,
  graceHoursFrom,
  isEntitled,
  readUserRow,
} from "../_shared/entitlement.ts";
import { planFor } from "../_shared/pricing.ts";
import { latestSubscription, syncSubscription } from "../_shared/subscription_sync.ts";

/**
 * Re-reads the caller's subscription from Cashfree and returns their current entitlement.
 *
 * Two jobs. It is what the app polls after checkout, because the SDK's success callback proves
 * only that the sheet closed — not that the money moved. And it is the self-heal for a webhook
 * that never arrived, which is why it reconciles rather than just reading the local row.
 *
 * A Cashfree outage degrades to the stored state instead of erroring: a user who is already
 * paid up must not be locked out because the gateway is briefly unreachable.
 */

const TERMINAL = ["CANCELLED", "COMPLETED", "EXPIRED", "ABANDONED", "FAILED_TO_CREATE"];

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  const db = serviceClient();
  const caller = await callerForBearer(db, req.headers.get("Authorization"));
  if (!caller) return fail("unauthorized", "Please sign in again.", 401);
  const { userId } = caller;

  const config = await loadConfig(db);
  configureMixpanel(config, "subscription-status");
  configureNotifications(config, "subscription-status");
  configureFacebookCapi(config, "subscription-status");
  const graceHours = graceHoursFrom(config);

  const subscription = await latestSubscription(db, userId);
  // Whether anything in this request may have written `users` or `subscriptions`. Until a sync
  // runs, the rows read at the top are still the answer and are not read a second time.
  let synced = false;

  if (subscription && !TERMINAL.includes(subscription.status)) {
    // Pull the payments list only when a debit could be unaccounted for, so the extra Cashfree
    // call stays off the ordinary foreground poll that runs on every app resume.
    //
    // Two triggers. `blocked` is the user already being turned away — the end state a missed
    // webhook produces. `chargeDue` catches it earlier: Cashfree's schedule has passed, so a
    // debit has probably happened, and waiting for the user to be locked out first would mean
    // recovering their access only after they had already been shown the paywall.
    const stored = await callerUserRow(db, caller, "subscription-status");

    const blocked = !stored || !isEntitled(stored, graceHours);
    const chargeDue = subscription.next_schedule_date !== null &&
      new Date(subscription.next_schedule_date).getTime() <= Date.now();

    synced = true;
    try {
      const settings = cashfreeSettings(config);
      await syncSubscription(
        db,
        settings,
        subscription.subscription_id,
        0,
        blocked || chargeDue,
      );
    } catch (error) {
      // Logged, not surfaced. The stored state below is still a correct answer, just possibly
      // a few minutes stale, and the webhook or the nightly sweep will catch up.
      console.error(`status reconcile failed for ${subscription.subscription_id}`, error);
    }
  }

  const row = synced
    ? await readUserRow(db, userId, "subscription-status")
    : await callerUserRow(db, caller, "subscription-status");
  if (!row) return fail("server_error", "Something went wrong. Please try again.", 500);

  const fresh = synced ? await latestSubscription(db, userId) : subscription;

  return json({
    user: entitlementPayload(row, graceHours, planFor(config, row.plan_variant)),
    subscription: fresh
      ? {
        subscription_id: fresh.subscription_id,
        status: fresh.status,
        next_schedule_date: fresh.next_schedule_date,
        authorized_at: fresh.authorized_at,
      }
      : null,
  });
});
