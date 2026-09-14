/**
 * Referral codes, share links and acquisition resolution.
 *
 * Shared by the referral Edge Functions and by the conversion hook in `subscription_sync.ts`, so
 * that "what counts as a Meta install" and "what makes a claim idempotent" are each written
 * exactly once. Two functions disagreeing about either is how an attribution system starts
 * producing numbers nobody trusts.
 *
 * ## Android, through the Play Store
 *
 * An invite is a Play Store link carrying `referrer=ref_code=<CODE>`, which Google returns
 * verbatim on first launch. There is no web page and no click record: an earlier draft had both,
 * to recover a referral on iOS where nothing survives the App Store, and all of it was removed
 * when the launch scope became Android-only. The fallback for a device that never completed the
 * store round trip is the manual code field in onboarding.
 */

import { SupabaseClient } from "jsr:@supabase/supabase-js@2";

import { AppConfig, configFlag, configSetting } from "./config.ts";

// ---------------------------------------------------------------- codes

/**
 * Crockford base32 without I, L, O and U. Must match the CHECK constraint on
 * `referral_codes.code` and the client's `referral_links.dart` — all three describe the same
 * alphabet, and a mismatch shows up as a valid code the app refuses to open.
 */
export const REFERRAL_CODE_PATTERN = /^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{8}$/;

/**
 * Cleans up a code the way a human would have meant it.
 *
 * Codes arrive off screenshots, out of WhatsApp messages and typed by hand, so case and stray
 * whitespace mean nothing. The four ambiguous letters are folded onto the characters they are
 * almost certainly a misreading of rather than rejected: someone who types `LOIU` meant `1010`,
 * and refusing them would be technically correct and useless.
 */
export function normaliseReferralCode(raw: unknown): string | null {
  if (typeof raw !== "string") return null;

  const cleaned = raw
    .trim()
    .toUpperCase()
    .replace(/[^0-9A-Z]/g, "")
    .replace(/[IL]/g, "1")
    .replace(/O/g, "0")
    .replace(/U/g, "V");

  return REFERRAL_CODE_PATTERN.test(cleaned) ? cleaned : null;
}

// ---------------------------------------------------------------- acquisition

/** Ceiling on any single campaign value. See the note in [resolveAcquisition]. */
const MAX_PROPERTY_LENGTH = 256;

export interface Acquisition {
  /** referral | meta | google_ads | paid_other | organic */
  source: string;
  /** install_referrer | manual_code | deep_link */
  channel: string;
  campaign: string | null;
  campaignId: string | null;
  adset: string | null;
  ad: string | null;
  referralCode: string | null;
}

/**
 * Decides where an install came from, from whatever parameters survived the trip.
 *
 * The precedence is deliberate and is the whole of the policy:
 *
 *   **referral > paid > organic**
 *
 * A referral code is an explicit, first-party statement that a named user sent this person, so it
 * outranks a campaign parameter that merely rode along on the same URL. Paid beats organic for the
 * opposite reason — `utm_medium=organic` is what the Play Store stamps on *every* store visit
 * including one that began with an ad click, so treating it as authoritative would quietly
 * reclassify paid installs as free ones and make every campaign look unprofitable.
 */
export function resolveAcquisition(
  params: Record<string, string | null | undefined>,
  channel: string,
  referralCode: string | null,
): Acquisition {
  // Truncated, not merely trimmed. These values are client-supplied and every one of them is
  // written to `user_attribution` and sent to Mixpanel as a property, so an unbounded string here
  // is an unauthenticated way to write large rows and to blow past Mixpanel's own property
  // limits. 256 is far more than any real campaign name and far less than a problem.
  const get = (key: string): string | null => {
    const value = params[key];
    if (typeof value !== "string") return null;
    const trimmed = value.trim();
    return trimmed === "" ? null : trimmed.slice(0, MAX_PROPERTY_LENGTH);
  };

  const utmSource = (get("utm_source") ?? "").toLowerCase();
  const utmMedium = (get("utm_medium") ?? "").toLowerCase();

  const source = referralCode !== null
    ? "referral"
    // `gclid` is Google's click id and is present on precisely one thing: a click on a Google ad.
    // It is the only unambiguous signal in this whole function, so it is tested first.
    : get("gclid") !== null || utmSource === "adwords" || utmSource === "google-ads"
    ? "google_ads"
    // `fbclid` is the Meta equivalent. `apps.facebook.com` is what Meta stamps on the Play Store
    // referrer when a click routes through the store rather than through a deep link.
    : get("fbclid") !== null ||
      /facebook|instagram|^meta$|^ig$|apps\.facebook\.com/.test(utmSource)
    ? "meta"
    // A campaign with a paid medium and an unrecognised source is still paid — some other network
    // or a manually tagged link. Better an honest "paid, source unknown" than a false organic.
    : /^(cpc|ppc|paid|cpm|cpi)/.test(utmMedium)
    ? "paid_other"
    : "organic";

  return {
    source,
    channel,
    campaign: get("utm_campaign") ?? get("campaign"),
    campaignId: get("campaign_id") ?? get("utm_id"),
    adset: get("adset") ?? get("utm_adset") ?? get("utm_term"),
    ad: get("ad") ?? get("utm_ad") ?? get("utm_content"),
    referralCode,
  };
}

/**
 * Parses a Play Install Referrer string, which is a URL query without the URL.
 *
 * Google hands back exactly what was in the store link's `referrer` parameter, already
 * percent-decoded once. Our own referral links put `ref_code` in there, which is what makes
 * Android deferred attribution deterministic rather than a guess.
 */
export function parseReferrerString(raw: string | null): Record<string, string> {
  if (!raw) return {};
  const out: Record<string, string> = {};
  for (const [key, value] of new URLSearchParams(raw)) {
    out[key] = value;
  }
  return out;
}

// ---------------------------------------------------------------- settings

export interface ReferralSettings {
  enabled: boolean;
  /** The Play Store listing an invite links to. Blank means invites cannot be shared at all. */
  storeUrl: string;
  claimWindowDays: number;
}

export function referralSettings(config: AppConfig): ReferralSettings {
  const claimDays = Number.parseInt(
    configSetting(config, "referral_claim_window_days"),
    10,
  );
  return {
    enabled: configFlag(config, "referral_enabled"),
    storeUrl: configSetting(config, "referral_store_url"),
    claimWindowDays: Number.isFinite(claimDays) && claimDays > 0
      ? claimDays
      : DEFAULT_CLAIM_WINDOW_DAYS,
  };
}

/**
 * The link a user actually shares: the Play Store listing, carrying the code in `referrer`.
 *
 * Google hands that parameter back verbatim through the Install Referrer API on first launch,
 * which is what lets a code survive an install that had no app to open — no web page, no domain
 * verification, no association files.
 *
 * ## Two encoding traps, both of which produce a link that looks right and attributes nothing
 *
 * The value of `referrer` is itself a query string, so it must be percent-encoded **once** as a
 * whole. Encoding the inner `=` and `&` separately as well is the usual reason a code arrives at
 * the app as the literal text `ref_code%3DABCD2345`. `encodeURIComponent` over the assembled
 * string is exactly one round, which is what Google's decode expects.
 *
 * And the listing URL already carries `?id=`, so the parameter is appended with `&`. A second `?`
 * makes Play drop everything after it, silently and with a page that still loads.
 *
 * Returns null when no store URL is configured, so the caller can say "invites are unavailable"
 * rather than share a link that 404s.
 */
export function shareLinkFor(settings: ReferralSettings, code: string): string | null {
  const base = settings.storeUrl.trim();
  if (!base) return null;

  const referrer = encodeURIComponent(`utm_source=referral&utm_medium=invite&ref_code=${code}`);
  return `${base}${base.includes("?") ? "&" : "?"}referrer=${referrer}`;
}

// ---------------------------------------------------------------- claiming

export type ClaimOutcome =
  | { status: "created"; referrerUserId: string }
  | { status: "already_referred"; referrerUserId: string }
  | { status: "invalid_code" }
  | { status: "self_referral" }
  | { status: "not_eligible" };

/** How long after signing up an account can still be attributed to a referrer. */
const DEFAULT_CLAIM_WINDOW_DAYS = 7;

/**
 * Whether this account may still be credited to a referrer.
 *
 * Two conditions, and each rules out a different way of gaming or mis-crediting this:
 *
 *  1. **Never had entitlement.** No trial, no paid period, ever. Someone who has already been a
 *     customer cannot be "acquired" by a referral, so a paying user who reinstalls and opens a
 *     friend's link earns that friend nothing.
 *  2. **Signed up recently.** Within [DEFAULT_CLAIM_WINDOW_DAYS], from `creation_time`. This is
 *     what stops a months-old account that simply never paid from being retro-attributed — which
 *     the entitlement test alone would allow, and which is indistinguishable from farming.
 *
 * An earlier version of this used "has no name yet" as the proxy for a fresh signup. It was
 * tighter and worse: it meant a code had to be typed *before* the name step or not at all, which
 * gave the iOS fallback a window of about thirty seconds and made the rule depend on an unrelated
 * bit of onboarding order. Account age says the thing actually meant.
 *
 * Asked of the database rather than trusted from the client, which is the entire security of this
 * feature — a client-supplied "I am a new user" flag would be the exploit.
 */
export async function isEligibleForReferral(
  db: SupabaseClient,
  userId: string,
  windowDays = DEFAULT_CLAIM_WINDOW_DAYS,
): Promise<boolean> {
  const { data, error } = await db
    .from("users")
    .select("payment_type, trial_ends_at, current_period_end, creation_time")
    .eq("user_id", userId)
    .maybeSingle();

  if (error || !data) return false;

  const row = data as {
    payment_type: string | null;
    trial_ends_at: string | null;
    current_period_end: string | null;
    creation_time: string | null;
  };

  // Has ever had entitlement, so was already a customer and cannot be acquired again.
  if (row.trial_ends_at !== null || row.current_period_end !== null) return false;
  if (row.payment_type !== null && !["trial", "none"].includes(row.payment_type)) {
    return false;
  }

  // A row with no creation_time should not exist — the column is `not null default now()` — so
  // treating it as ineligible rather than guessing is the safe direction to be wrong in.
  if (!row.creation_time) return false;

  const age = Date.now() - Date.parse(row.creation_time);
  return Number.isFinite(age) && age <= windowDays * 24 * 60 * 60 * 1000;
}

/**
 * Records the relationship, idempotently.
 *
 * The insert is `on conflict do nothing` followed by an unconditional read-back, which is the
 * shape that makes every duplicate path safe at once. A retry, a second link, two concurrent
 * requests and an app that was killed after writing its pending state all end up here, and all of
 * them get the *same* answer: the row that exists. Nothing has to detect the race, because
 * nothing depends on having won it.
 */
export async function claimReferral(
  db: SupabaseClient,
  {
    referredUserId,
    code,
    attributionType,
    windowDays,
  }: {
    referredUserId: string;
    code: string;
    attributionType: string;
    windowDays?: number;
  },
): Promise<ClaimOutcome> {
  const { data: codeRow } = await db
    .from("referral_codes")
    .select("user_id")
    .eq("code", code)
    .maybeSingle();

  if (!codeRow) return { status: "invalid_code" };

  const referrerUserId = (codeRow as { user_id: string }).user_id;
  if (referrerUserId === referredUserId) return { status: "self_referral" };

  // Checked before the insert so the caller gets a meaningful reason, and enforced again by the
  // database's own constraints regardless of what any caller does.
  if (!await isEligibleForReferral(db, referredUserId, windowDays)) {
    return { status: "not_eligible" };
  }

  // A plain insert, not an upsert. A conflict here is not an error condition to be smoothed
  // over — it is the answer to the question being asked, and it must be distinguishable from
  // having created the row, because only one of those two is a new referral worth an event.
  const { data: inserted, error: insertError } = await db
    .from("referrals")
    .insert({
      referred_user_id: referredUserId,
      referrer_user_id: referrerUserId,
      code,
      attribution_type: attributionType,
    })
    .select("referrer_user_id")
    .maybeSingle();

  if (!insertError && inserted) {
    return { status: "created", referrerUserId };
  }

  // The insert did not land. Overwhelmingly that is the primary key rejecting a second referral
  // for this user — a retry, a second link, or the loser of a race — so read back who actually
  // holds the claim and report *them*. The caller gets a successful, stable answer either way,
  // which is what makes this safe to call any number of times.
  const { data: existing } = await db
    .from("referrals")
    .select("referrer_user_id")
    .eq("referred_user_id", referredUserId)
    .maybeSingle();

  if (existing) {
    return {
      status: "already_referred",
      referrerUserId: (existing as { referrer_user_id: string }).referrer_user_id,
    };
  }

  // No row and no insert: a genuine write failure, not a conflict. Reported as ineligible rather
  // than retried, because the client's retry loop must not spin on a broken database.
  console.error("referral insert failed", insertError);
  return { status: "not_eligible" };
}

/**
 * Marks a referral as having paid, and says whether this call is the one that did it.
 *
 * The `is null` predicate is what makes the payment webhook safe to redeliver: a second delivery
 * updates zero rows and returns false, so the conversion event fires exactly once even before
 * Mixpanel's own `$insert_id` dedupe is considered. Two independent guards for one event, because
 * revenue attribution counted twice is worse than not counted at all.
 */
export async function qualifyReferral(
  db: SupabaseClient,
  referredUserId: string,
  at: string,
): Promise<{ qualified: boolean; referrerUserId: string | null; code: string | null }> {
  const { data, error } = await db
    .from("referrals")
    .update({ qualified_at: at })
    .eq("referred_user_id", referredUserId)
    .is("qualified_at", null)
    .select("referrer_user_id, code")
    .maybeSingle();

  if (error || !data) return { qualified: false, referrerUserId: null, code: null };

  const row = data as { referrer_user_id: string; code: string };
  return { qualified: true, referrerUserId: row.referrer_user_id, code: row.code };
}
