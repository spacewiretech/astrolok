import { parseCancellationFeedback } from "../_shared/cancellation_feedback.ts";
import { resolveLanguage } from "../_shared/chat_language.ts";
import { loadConfig } from "../_shared/config.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer } from "../_shared/db.ts";
import { asUserRow, USER_COLUMNS } from "../_shared/entitlement.ts";
import { configureMixpanel, setProfile } from "../_shared/mixpanel.ts";

/**
 * Records why a user cancelled.
 *
 *   POST {reason, comment?, source?: "push" | "in_app", notification_id?} → {ok: true, recorded}
 *
 * Bearer token only — deliberately no entitlement check. A trial user who cancels loses access the
 * same minute, and this is exactly the person whose answer is wanted.
 *
 * The subscription is the account's most recently cancelled one, decided here rather than taken from
 * the body. One answer per mandate: a second submission answers `recorded: false` and changes nothing.
 */

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  const db = serviceClient();
  const userId = await userIdForBearer(db, req.headers.get("Authorization"));
  if (!userId) return fail("unauthorized", "Please sign in again.", 401);

  let body: unknown = null;
  try {
    body = await req.json();
  } catch {
    // Rejected below along with any other malformed body.
  }

  const feedback = parseCancellationFeedback(body);
  if (!feedback) return fail("invalid_request", "Please choose a reason.", 400);

  const config = await loadConfig(db);
  configureMixpanel(config, "cancellation-feedback");

  const [{ data: subscription, error: subError }, { data: userRow, error: userError }] = await Promise.all([
    db.from("subscriptions")
      .select("subscription_id, cancelled_at")
      .eq("user_id", userId)
      .in("status", ["CANCELLED", "CUSTOMER_CANCELLED"])
      .order("cancelled_at", { ascending: false, nullsFirst: false })
      .limit(1)
      .maybeSingle(),
    db.from("users").select(USER_COLUMNS).eq("user_id", userId).single(),
  ]);

  if (subError || userError || !userRow) {
    console.error("cancellation-feedback: lookup failed", subError ?? userError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }
  if (!subscription) return fail("not_found", "There is no cancelled plan to tell us about.", 404);

  const user = asUserRow(userRow);

  // Only an id that is really this account's push; anything else is stored as unattributed.
  let notificationId = feedback.notificationId;
  if (notificationId) {
    const { data } = await db.from("notifications").select("id").eq("id", notificationId).eq("user_id", userId)
      .maybeSingle();
    if (!data) notificationId = null;
  }

  const { data: inserted, error } = await db.from("cancellation_feedback").upsert({
    user_id: userId,
    subscription_id: subscription.subscription_id,
    reason: feedback.reason,
    comment: feedback.comment,
    // A trial is the only state with no paid period behind it.
    was_in_trial: !user.current_period_end,
    payment_type: user.payment_type,
    language: resolveLanguage(user.language, config),
    source: feedback.source,
    notification_id: notificationId,
  }, { onConflict: "user_id,subscription_id", ignoreDuplicates: true }).select("id");

  if (error) {
    console.error("cancellation-feedback: insert failed", error);
    return fail("server_error", "Could not save your answer. Please try again.", 500);
  }

  const recorded = (inserted?.length ?? 0) > 0;
  if (recorded && feedback.reason !== "dismissed") {
    await setProfile(userId, { last_cancel_reason: feedback.reason });
  }

  return json({ ok: true, recorded });
});
