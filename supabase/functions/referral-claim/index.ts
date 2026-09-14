import { loadConfig } from "../_shared/config.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer } from "../_shared/db.ts";
import { configureMixpanel, trackServer } from "../_shared/mixpanel.ts";
import {
  claimReferral,
  normaliseReferralCode,
  referralSettings,
} from "../_shared/referral.ts";

/**
 * How an attribution reached us, in descending order of how much we trust it.
 *
 * `install_referrer` is Google handing back the code we put in the store link — deterministic.
 * `manual_code` is the user typing it. `deep_link` is reserved for the `astrolok://` scheme.
 *
 * `ip_match` is deliberately absent. It existed to recover a referral on iOS, where nothing
 * survives the App Store, by matching a recent click against a salted fingerprint of the device's
 * address. That whole path — the clicks table, the click endpoint, the salt — was removed when the
 * launch scope became Android-only, because on Android the Play Store carries the code and a
 * probabilistic guess would only ever be worse than the deterministic answer already in hand.
 */
const ATTRIBUTION_TYPES = new Set([
  "install_referrer",
  "manual_code",
  "deep_link",
]);

/**
 * The one place a referral relationship is created.
 *
 * Every path the app can take — the Play install referrer read on first launch, or a code typed
 * by hand — arrives here. Keeping it to one function is what makes "a user can be referred at
 * most once" a property of the system rather than a rule each call site has to remember.
 *
 * ## Idempotent by construction
 *
 * Safe to call any number of times with anything. `claimReferral` inserts and, on conflict, reads
 * back whoever actually holds the claim, so a retry after a dropped response, an app killed
 * mid-call, and two requests racing all produce the same successful answer. The client never has
 * to reason about whether its previous attempt landed — which is the point, because it cannot
 * know.
 *
 * ## What the client is not trusted with
 *
 * Only the code. Whether the caller is a new account is re-derived here from the database, never
 * accepted as a flag: a client-supplied "I am new" would be the whole exploit, letting any
 * existing user re-claim a referral by editing one boolean.
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
  const settings = referralSettings(config);
  configureMixpanel(config, "referral-claim");

  if (!settings.enabled) return json({ status: "disabled" });

  const attributionType = typeof body.attribution_type === "string" &&
      ATTRIBUTION_TYPES.has(body.attribution_type)
    ? body.attribution_type
    : "manual_code";

  const code = normaliseReferralCode(body.code);

  // No code, nothing to attribute. There is no server-side recovery path: on Android a referred
  // install always carries its code in the Play referrer, so an absent one means this genuinely
  // was not a referral.
  if (!code) return json({ status: "no_attribution" });

  const outcome = await claimReferral(db, {
    referredUserId: userId,
    code,
    attributionType,
    windowDays: settings.claimWindowDays,
  });

  switch (outcome.status) {
    case "created":
      // Keyed on the relationship, which by the primary key above can only ever exist once. A
      // redelivery or a retry that somehow reached this branch twice still produces one event.
      await trackServer({
        event: "Referral Attributed",
        distinctId: userId,
        insertId: `ref:${userId}`,
        properties: {
          referral_code: code,
          referred_by: outcome.referrerUserId,
          attribution_type: attributionType,
          acquisition_source: "referral",
          acquisition_channel: attributionType,
        },
      });
      return json({
        status: "created",
        code,
        referred_by: outcome.referrerUserId,
        attribution_type: attributionType,
      });

    // Already claimed — by an earlier attempt of this same call, or by a different link. Reported
    // as a success so the client clears its pending state instead of retrying forever, but
    // deliberately not re-fired as an event: the referral did not happen twice.
    case "already_referred":
      return json({
        status: "already_referred",
        referred_by: outcome.referrerUserId,
      });

    case "self_referral":
      return json({ status: "self_referral" });

    // The account is not a fresh signup — a reinstall, or an existing user who opened a friend's
    // link. Not an error, and the client must stop asking.
    case "not_eligible":
      return json({ status: "not_eligible" });

    case "invalid_code":
      return json({ status: "invalid_code" });
  }
});
