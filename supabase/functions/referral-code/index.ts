import { loadConfig } from "../_shared/config.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer } from "../_shared/db.ts";
import { referralSettings, shareLinkFor } from "../_shared/referral.ts";

/**
 * Hands the caller their own invite code, minting one the first time they ask.
 *
 * Idempotent twice over: `issue_referral_code` returns an existing code unchanged, and the
 * `referral_codes.user_id` unique constraint means even a concurrent double-tap on the invite
 * screen cannot produce two codes for one account. That matters because a user who saw two
 * different codes would have already shared the one we later stopped honouring.
 *
 * The share URL is built here rather than in the app, so the Play Store listing can be corrected
 * or replaced from the dashboard without shipping a release. It is a Play Store link carrying
 * `referrer=ref_code=<CODE>`, which Google returns verbatim on first launch — see `shareLinkFor`
 * for the two encoding traps that otherwise produce a link that looks right and attributes
 * nothing.
 */
Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  const db = serviceClient();
  const userId = await userIdForBearer(db, req.headers.get("Authorization"));
  if (!userId) return fail("unauthorized", "Please sign in again.", 401);

  const config = await loadConfig(db);
  const settings = referralSettings(config);

  // The off switch. Answered as a normal response rather than an error so the app can simply
  // hide the invite screen, which is what "referrals are off" should look like to a user.
  if (!settings.enabled) {
    return json({ enabled: false });
  }

  const { data, error } = await db.rpc("issue_referral_code", { p_user_id: userId });

  if (error || typeof data !== "string") {
    console.error("issue_referral_code failed", error);
    return fail("server_error", "Could not create your invite link. Please try again.", 500);
  }

  // No Play Store listing configured yet, so there is no link to share. Reported as disabled
  // rather than as an error: it is the honest state of a pre-launch deployment, and sharing a
  // store URL that 404s would be worse than the invite screen saying it is unavailable.
  const link = shareLinkFor(settings, data);
  if (!link) {
    console.error("referral_store_url is unset; cannot build a share link");
    return json({ enabled: false });
  }

  // How many people this user has brought in, and how many of those actually paid. Two numbers
  // rather than one because the gap between them is the entire story of whether an invite
  // campaign is working — plenty of signups and no conversions is a very different problem from
  // no signups at all.
  const { count: invited } = await db
    .from("referrals")
    .select("referred_user_id", { count: "exact", head: true })
    .eq("referrer_user_id", userId);

  const { count: converted } = await db
    .from("referrals")
    .select("referred_user_id", { count: "exact", head: true })
    .eq("referrer_user_id", userId)
    .not("qualified_at", "is", null);

  return json({
    enabled: true,
    code: data,
    link,
    invited: invited ?? 0,
    converted: converted ?? 0,
  });
});
