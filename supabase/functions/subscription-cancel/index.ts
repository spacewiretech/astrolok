import { cancelSubscription, CashfreeError, cashfreeSettings } from "../_shared/cashfree.ts";
import { loadConfig } from "../_shared/config.ts";
import { configureMixpanel } from "../_shared/mixpanel.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer } from "../_shared/db.ts";
import {
  asUserRow,
  entitlementPayload,
  graceHoursFrom,
  USER_COLUMNS,
} from "../_shared/entitlement.ts";
import {
  latestSubscription,
  syncSubscription,
  trackCancellation,
} from "../_shared/subscription_sync.ts";

/**
 * Cancels the caller's UPI mandate so no further ₹499 is debited.
 *
 * Access is deliberately not revoked here: `current_period_end` is left alone, so the user
 * keeps the month they already paid for and `payment_type` becomes `cancelled`, which the
 * entitlement rule honours until that date passes.
 *
 * The subscription is found from the session token, never named in the body — otherwise
 * knowing a subscription id would be enough to cancel a stranger's plan.
 */
Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  const db = serviceClient();
  const userId = await userIdForBearer(db, req.headers.get("Authorization"));
  if (!userId) return fail("unauthorized", "Please sign in again.", 401);

  const config = await loadConfig(db);
  configureMixpanel(config, "subscription-cancel");
  const graceHours = graceHoursFrom(config);

  let settings;
  try {
    settings = cashfreeSettings(config);
  } catch (error) {
    console.error("cashfree settings unavailable", error);
    return fail("payment_failed", "Payments are temporarily unavailable.", 503);
  }

  const subscription = await latestSubscription(db, userId);
  if (!subscription || !["ACTIVE", "ON_HOLD", "PAUSED"].includes(subscription.status)) {
    return fail("invalid_request", "There is no active subscription to cancel.", 400);
  }

  try {
    await cancelSubscription(settings, subscription.subscription_id);
  } catch (error) {
    const detail = error instanceof CashfreeError ? error.detail : String(error);
    console.error("cashfree cancel failed", detail);
    return fail(
      "payment_failed",
      "Could not cancel the subscription. Please try again.",
      502,
    );
  }

  // Fired here, before the read-back below, because this is the only place that knows *why* the
  // mandate ended. Cashfree reports our own cancel back as a plain `CANCELLED`, indistinguishable
  // from a merchant cancel made for any other reason — so if this were left to the sync, a user
  // deliberately churning through our own screen would be filed under `merchant`.
  //
  // The `cancel:<subscription id>` insert id is what makes the double-report safe: the sync below
  // will raise the same event a second later, and Mixpanel collapses the two onto this one.
  {
    const { data: priorUser } = await db
      .from("users")
      .select(USER_COLUMNS)
      .eq("user_id", userId)
      .maybeSingle();
    const prior = priorUser ? asUserRow(priorUser) : null;

    await trackCancellation({
      userId,
      subscriptionId: subscription.subscription_id,
      cancelledBy: "user_in_app",
      cfStatus: subscription.status,
      fromStatus: subscription.status,
      wasInTrial: prior?.payment_type === "trial",
      entitledUntil: prior?.current_period_end ?? null,
      startedAt: prior?.subscription_started_at ?? subscription.authorized_at,
    });
  }

  // Read the result back rather than assuming the cancel took effect, so the status we report
  // is the one Cashfree will actually bill against.
  try {
    await syncSubscription(db, settings, subscription.subscription_id);
  } catch (error) {
    console.error(`cancel reconcile failed for ${subscription.subscription_id}`, error);
  }

  const { data: userRow, error } = await db
    .from("users")
    .select(USER_COLUMNS)
    .eq("user_id", userId)
    .single();

  if (error || !userRow) {
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  return json({ user: entitlementPayload(asUserRow(userRow), graceHours) });
});
