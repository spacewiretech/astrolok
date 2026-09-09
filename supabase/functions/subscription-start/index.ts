import {
  addDays,
  addMonths,
  cancelSubscription,
  CashfreeError,
  cashfreeSettings,
  createSubscription,
  snapshotOf,
} from "../_shared/cashfree.ts";
import { loadConfig } from "../_shared/config.ts";
import { configureMixpanel } from "../_shared/mixpanel.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer } from "../_shared/db.ts";
import {
  asUserRow,
  entitlementPayload,
  graceHoursFrom,
  isEntitled,
  trialAvailable,
  USER_COLUMNS,
} from "../_shared/entitlement.ts";
import {
  isResumable,
  latestSubscription,
  syncSubscription,
  trackCancellation,
} from "../_shared/subscription_sync.ts";

/**
 * Opens a Cashfree UPI Autopay mandate, on one of two offers.
 *
 *  * An account that has never authorised a mandate — `payment_type = 'none'` — gets the trial:
 *    ₹3 now, then ₹499/month starting after the trial days.
 *  * Anyone else has already spent their trial, so they pay ₹499 now and ₹499/month from a month
 *    out. The full price is taken as the *authorisation* amount because Cashfree will not
 *    schedule a first debit less than 24 hours ahead — charging it up front is the only way to
 *    take money at mandate time at all.
 *
 * Which of the two applies is decided here from the user's own row, never from the request. This
 * used to be a display-only distinction the paywall made on its own, which meant a returning
 * subscriber was shown ₹499 and sold the ₹3 trial — repeatably, by cancelling and coming back.
 *
 * The request body is empty by design. The plan, both amounts and the trial length all come
 * from `app_config`, so there is no parameter a modified client could send to pay less. The
 * only thing the caller supplies is its session token, and the user id is derived from that.
 */

/** Cashfree allows alphanumerics, underscore, dot, hyphen and space, up to 250 characters. */
function newSubscriptionId(userId: string): string {
  return `alk_${userId.replace(/-/g, "")}_${Math.floor(Date.now() / 1000)}`;
}

/** Cashfree requires an email. Nobody reads this one — the notices go out over SMS. */
function syntheticEmail(mobile: string): string {
  return `${mobile}@astrolok.app`;
}

/** How long the checkout token stays usable before a retry has to mint a fresh mandate. */
const SESSION_MINUTES = 15;

/** A sane ceiling on mandate attempts per hour, so a retry loop cannot hammer Cashfree. */
const MAX_ATTEMPTS_PER_HOUR = 10;

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  const db = serviceClient();
  const userId = await userIdForBearer(db, req.headers.get("Authorization"));
  if (!userId) return fail("unauthorized", "Please sign in again.", 401);

  const config = await loadConfig(db);
  configureMixpanel(config, "subscription-start");
  const graceHours = graceHoursFrom(config);

  let settings;
  try {
    settings = cashfreeSettings(config);
  } catch (error) {
    // Missing credentials are a deployment problem, not something the user can act on.
    console.error("cashfree settings unavailable", error);
    return fail("payment_failed", "Payments are temporarily unavailable.", 503);
  }

  const { data: userRow, error: userError } = await db
    .from("users")
    .select(USER_COLUMNS)
    .eq("user_id", userId)
    .single();

  if (userError || !userRow) {
    console.error("subscription-start user lookup failed", userError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  // Reassigned by the reconcile below, which can credit a payment we were never told about.
  let user = asUserRow(userRow);

  // Charging someone who is already inside their trial or their paid month is the one mistake
  // that is genuinely hard to undo, so it is checked before anything else touches Cashfree.
  if (isEntitled(user, graceHours)) {
    return json({
      status: "entitled",
      user: entitlementPayload(user, graceHours),
    });
  }

  if (!user.name || !user.name.trim()) {
    return fail("invalid_request", "Please add your name before subscribing.", 400);
  }

  // Held rather than re-read off `user`, which the reconcile below may reassign — and a name
  // checked on one row is not a name checked on another.
  const customerName = user.name.trim();

  // Resume rather than duplicate: a double tap, or a checkout the user backgrounded and came
  // back to, must reuse the mandate it already opened.
  const existing = await latestSubscription(db, userId);
  if (existing && isResumable(existing)) {
    return json({
      status: "pending",
      subscription_id: existing.subscription_id,
      subscription_session_id: existing.session_id,
      cf_subscription_id: existing.cf_subscription_id,
      environment: settings.env,
    });
  }

  // Before anything is replaced, and before the offer is decided: a live mandate whose owner is
  // not entitled is *usually* one whose debits are failing, but it is also exactly what a
  // captured authorisation whose webhook never arrived looks like, and from here the two are
  // indistinguishable. So ask Cashfree — `withPayments` pulls the charge list, which is the only
  // thing that can report a payment we were never told about.
  //
  // This matters far more than it used to. The branch below cancels the mandate and opens a
  // replacement, which for a returning subscriber means authorising the full plan price a second
  // time — charging ₹499 twice for one month, minutes apart, to someone who did nothing wrong.
  if (existing && ["ACTIVE", "ON_HOLD", "PAUSED"].includes(existing.status)) {
    try {
      const synced = await syncSubscription(db, settings, existing.subscription_id, 0, true);
      if (isEntitled(synced.user, graceHours)) {
        return json({
          status: "entitled",
          user: entitlementPayload(synced.user, graceHours),
        });
      }
      // Not entitled, but the row may still have moved: this is where a `none` account that
      // authorised long ago finally gets its `trial_ends_at`, which is precisely the fact the
      // offer below turns on. Deciding the price from the pre-sync row would sell a second ₹3
      // trial to someone the sync had just recorded as having spent theirs.
      user = synced.user;
    } catch (error) {
      // Cashfree unreachable, or a mandate it has no record of. Falling through opens a fresh
      // one, which is exactly what this function did before the check existed.
      console.error(
        `could not reconcile ${existing.subscription_id} before replacing it`,
        error,
      );
    }
  }

  // The one decision that says what this user is about to be charged, taken from the freshest
  // view of their row that exists.
  const offerTrial = trialAvailable(user);
  const authorizationAmount = offerTrial ? settings.trialAmount : settings.recurringAmount;

  // Fails closed rather than authorising ₹0. A blank or unreadable `cashfree_recurring_amount`
  // used to cost nothing here — it only named a future debit, and Cashfree's own plan was the
  // authority on that. It now decides an amount charged immediately, so a misconfigured row
  // would hand a returning subscriber a free month.
  if (!offerTrial && !(authorizationAmount > 0)) {
    console.error(
      "cashfree_recurring_amount is not a positive number; refusing to authorise a " +
        "returning subscriber for nothing",
    );
    return fail("payment_failed", "Payments are temporarily unavailable.", 503);
  }

  const hourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { count } = await db
    .from("subscriptions")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", hourAgo);

  if ((count ?? 0) >= MAX_ATTEMPTS_PER_HOUR) {
    return fail("throttled", "Too many attempts. Please try again in a little while.", 429);
  }

  // Anything still open is dead now: a new mandate is about to replace it.
  if (existing && ["INITIALIZED", "PENDING_AUTHORIZATION"].includes(existing.status)) {
    await db
      .from("subscriptions")
      .update({ status: "ABANDONED" })
      .eq("id", existing.id);
  }

  // Still live at Cashfree, still not entitled, and the reconcile above already proved no
  // payment is unaccounted for — so this really is a mandate whose debits are failing.
  //
  // It has to be cancelled *before* the replacement is created, not cleaned up afterwards:
  // leaving it would either trip the one-live-mandate index — losing the new mandate the user
  // just paid for, in favour of the broken one — or, worse, leave two UPI mandates both
  // authorised to take ₹499 a month.
  if (existing && ["ACTIVE", "ON_HOLD", "PAUSED"].includes(existing.status)) {
    try {
      await cancelSubscription(settings, existing.subscription_id);
    } catch (error) {
      // Already cancelled at Cashfree, or unreachable. Recording it locally still keeps the
      // index clear; the reconcile sweep will correct the status if this was wrong.
      console.error(`could not cancel stale mandate ${existing.subscription_id}`, error);
    }

    await db
      .from("subscriptions")
      .update({
        status: "CANCELLED",
        cancelled_at: new Date().toISOString(),
        failure_reason: "replaced by a new mandate",
      })
      .eq("id", existing.id);

    // Housekeeping, but a real mandate really ended — and the user never asked for it. Counted
    // separately from a churn cancel by `cancelled_by`, so a run of these reads as what it is: a
    // user who had to start checkout again because the first mandate stopped working.
    await trackCancellation({
      userId,
      subscriptionId: existing.subscription_id,
      cancelledBy: "system",
      cfStatus: "CANCELLED",
      fromStatus: existing.status,
      reason: "replaced_by_new_mandate",
    });
  }

  const now = new Date();
  const subscriptionId = newSubscriptionId(userId);

  // Cashfree requires subscription_first_charge_time to sit at least 24 hours out for a UPI
  // Autopay mandate, which is exactly where trialDays = 1 lands the trial. A returning subscriber
  // has just paid for their first month in the authorisation above, so their debit schedule
  // starts a month out — anything sooner would bill them twice for the same month.
  const firstChargeTime = offerTrial
    ? addDays(now, settings.trialDays)
    : addMonths(now, 1);

  const sessionExpiry = new Date(now.getTime() + SESSION_MINUTES * 60 * 1000);

  // The local row is written first. If Cashfree then succeeds but our follow-up write fails,
  // there is still a row naming the mandate — an orphaned mandate with no local owner is the
  // one failure mode that cannot be reconciled later.
  const { data: created, error: insertError } = await db
    .from("subscriptions")
    .insert({
      user_id: userId,
      subscription_id: subscriptionId,
      plan_id: settings.planId,
      status: "INITIALIZED",
      authorization_amount: authorizationAmount,
      recurring_amount: settings.recurringAmount,
      first_charge_time: firstChargeTime.toISOString(),
      session_expiry: sessionExpiry.toISOString(),
    })
    .select("id")
    .single();

  if (insertError || !created) {
    console.error("subscription insert failed", insertError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  let response: Record<string, unknown>;
  try {
    response = await createSubscription(settings, {
      subscriptionId,
      customerName,
      customerPhone: user.mobile_no,
      customerEmail: syntheticEmail(user.mobile_no),
      authorizationAmount,
      firstChargeTime,
      sessionExpiry,
      // The SDK returns control through its own callback; this only matters for the web
      // fallback. The matching intent filter is registered so the redirect resolves rather
      // than dead-ending on "no app can handle this link".
      returnUrl: `astrolok://payment?sub=${subscriptionId}`,
    });
  } catch (error) {
    const detail = error instanceof CashfreeError ? error.detail : String(error);
    console.error("cashfree create subscription failed", detail);

    await db
      .from("subscriptions")
      .update({ status: "FAILED_TO_CREATE", failure_reason: detail.slice(0, 500) })
      .eq("id", created.id);

    return fail(
      "payment_failed",
      error instanceof CashfreeError ? error.userMessage : "Could not start the payment.",
      502,
    );
  }

  const snapshot = snapshotOf(response);

  if (!snapshot.sessionId) {
    console.error("cashfree returned no subscription_session_id", response);
    await db
      .from("subscriptions")
      .update({ status: "FAILED_TO_CREATE", failure_reason: "no session id", raw: response })
      .eq("id", created.id);
    return fail("payment_failed", "Could not start the payment. Please try again.", 502);
  }

  await db
    .from("subscriptions")
    .update({
      cf_subscription_id: snapshot.cfSubscriptionId,
      status: snapshot.status,
      session_id: snapshot.sessionId,
      raw: snapshot.raw,
    })
    .eq("id", created.id);

  return json({
    status: "pending",
    subscription_id: subscriptionId,
    subscription_session_id: snapshot.sessionId,
    cf_subscription_id: snapshot.cfSubscriptionId,
    environment: settings.env,
    // Which of the two offers was opened, and what was actually authorised for it. Returned so
    // the client's `Subscribe Tapped` and `Payment Completed` events — and the conversion value
    // they hand to Facebook — describe the charge that happened rather than the one the paywall
    // guessed at.
    offer_type: offerTrial ? "trial" : "plan",
    authorization_amount: authorizationAmount,
    // Display only. The recurring amount that is actually charged lives in the Cashfree plan.
    trial_amount: settings.trialAmount,
    recurring_amount: settings.recurringAmount,
    trial_days: settings.trialDays,
  });
});
