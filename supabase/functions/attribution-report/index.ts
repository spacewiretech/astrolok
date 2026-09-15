import { loadConfig } from "../_shared/config.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer } from "../_shared/db.ts";
import { configureFacebookCapi } from "../_shared/facebook_capi.ts";
import { configureMixpanel, setProfile, trackServer } from "../_shared/mixpanel.ts";
import { normaliseReferralCode, resolveAcquisition } from "../_shared/referral.ts";

/**
 * Records where a user came from, and mirrors it onto their Mixpanel profile.
 *
 * ## Why this is server-side at all
 *
 * The app could write these properties itself, and for the *current* session it does. But the app
 * has no `alias` call anywhere — identity is bound purely by `identify(user_id)` — so events
 * fired before signup sit on an anonymous distinct id and only stitch to the account if the
 * Mixpanel project is on Simplified ID Merge. Writing the durable record here, keyed on
 * `users.user_id`, makes the attribution correct regardless of which merge mode the project uses
 * and regardless of whether the install that clicked the ad is the install that signed up.
 *
 * The client-side super properties become a convenience for segmenting live events; this table is
 * the thing that is actually true.
 *
 * ## First touch cannot be overwritten
 *
 * The `first_*` columns are written by an insert that does nothing on conflict, so the first write
 * wins at the database. Later calls only ever move the `last_*` columns. This is the failure mode
 * worth being paranoid about: a first touch quietly replaced by a later retargeting click
 * re-attributes the acquisition to the campaign that had the least to do with it, and it is
 * invisible once it has happened — there is no record of what the value used to be.
 */
Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail("invalid_request", "Malformed request.", 400);
  }

  const db = serviceClient();
  const userId = await userIdForBearer(db, req.headers.get("Authorization"));
  if (!userId) return fail("unauthorized", "Please sign in again.", 401);

  const config = await loadConfig(db);
  configureMixpanel(config, "attribution-report");
  configureFacebookCapi(config, "attribution-report");

  const params = body.params && typeof body.params === "object"
    ? body.params as Record<string, string>
    : {};
  const channel = typeof body.channel === "string" ? body.channel : "web";
  const code = normaliseReferralCode(body.referral_code);

  const acquisition = resolveAcquisition(params, channel, code);
  const now = new Date().toISOString();

  // Insert-or-nothing. This is the whole first-touch guarantee: if a row already exists, not one
  // of these values is written, and no amount of later reporting can move them.
  const { error: insertError } = await db
    .from("user_attribution")
    .upsert({
      user_id: userId,
      first_source: acquisition.source,
      first_channel: acquisition.channel,
      first_campaign: acquisition.campaign,
      first_campaign_id: acquisition.campaignId,
      first_adset: acquisition.adset,
      first_ad: acquisition.ad,
      first_attribution_type: acquisition.channel,
      first_referral_code: acquisition.referralCode,
      first_touch_at: now,
      last_source: acquisition.source,
      last_channel: acquisition.channel,
      last_campaign: acquisition.campaign,
      last_campaign_id: acquisition.campaignId,
      last_adset: acquisition.adset,
      last_ad: acquisition.ad,
      last_attribution_type: acquisition.channel,
      last_referral_code: acquisition.referralCode,
      last_touch_at: now,
    }, { onConflict: "user_id", ignoreDuplicates: true });

  if (insertError) {
    console.error("user_attribution insert failed", insertError);
    return fail("server_error", "Could not record attribution.", 500);
  }

  // And the half that is supposed to move. A no-op on the row we just created, which is cheaper
  // than asking whether it was created.
  const { error: updateError } = await db
    .from("user_attribution")
    .update({
      last_source: acquisition.source,
      last_channel: acquisition.channel,
      last_campaign: acquisition.campaign,
      last_campaign_id: acquisition.campaignId,
      last_adset: acquisition.adset,
      last_ad: acquisition.ad,
      last_attribution_type: acquisition.channel,
      last_referral_code: acquisition.referralCode,
      last_touch_at: now,
      updated_at: now,
    })
    .eq("user_id", userId);

  if (updateError) console.error("user_attribution update failed", updateError);

  // Read back what first touch actually settled on, rather than reporting what this call
  // proposed. On every call after the first those differ, and the profile must carry the value
  // that won.
  const { data: stored } = await db
    .from("user_attribution")
    .select("first_source, first_channel, first_campaign, first_campaign_id, " +
      "first_adset, first_ad, first_referral_code, first_touch_at")
    .eq("user_id", userId)
    .maybeSingle();

  const first = (stored ?? {}) as Record<string, string | null>;

  // `setOnce` on the initial_* properties as well as the do-nothing insert above. Belt and
  // braces on purpose: the two guards fail independently, and this is the value that cannot be
  // reconstructed if it is lost.
  await setProfile(userId, {
    initial_acquisition_source: first.first_source,
    initial_acquisition_channel: first.first_channel,
    initial_campaign: first.first_campaign,
    initial_campaign_id: first.first_campaign_id,
    initial_adset: first.first_adset,
    initial_ad: first.first_ad,
    initial_referral_code: first.first_referral_code,
    acquisition_source: acquisition.source,
    acquisition_channel: acquisition.channel,
    campaign: acquisition.campaign,
    campaign_id: acquisition.campaignId,
    adset: acquisition.adset,
    ad: acquisition.ad,
    referral_code: acquisition.referralCode,
    is_referred: acquisition.source === "referral",
  });

  // `Attribution Recorded`, not `Attribution Resolved` — those are two different moments and
  // must not share a name.
  //
  // The app raises `Attribution Resolved` when it works out where an install came from, which
  // happens before there is an account and therefore also for the many installs that never sign
  // up. This one says the backend stored it against a user. Giving both the same name would
  // double-count: a client SDK event carries no `$insert_id`, so Mixpanel cannot collapse it
  // against a server one however carefully the server keys its own.
  //
  // Keyed on the user and the resolved source, so the same install reporting the same thing on
  // every launch — which it will, since the install referrer never changes — produces one event.
  await trackServer({
    event: "Attribution Recorded",
    distinctId: userId,
    insertId: `attr:${userId}:${acquisition.source}:${acquisition.channel}`,
    properties: {
      acquisition_source: acquisition.source,
      acquisition_channel: acquisition.channel,
      campaign: acquisition.campaign,
      campaign_id: acquisition.campaignId,
      adset: acquisition.adset,
      ad: acquisition.ad,
      referral_code: acquisition.referralCode,
      attribution_type: acquisition.channel,
      is_first_touch: first.first_touch_at === now,
    },
  });

  return json({
    ok: true,
    acquisition_source: acquisition.source,
    first_source: first.first_source ?? acquisition.source,
  });
});
