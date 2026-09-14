import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";

import {
  normaliseReferralCode,
  parseReferrerString,
  referralSettings,
  resolveAcquisition,
  shareLinkFor,
} from "../_shared/referral.ts";
import { AppConfig } from "../_shared/config.ts";

// ---------------------------------------------------------------- codes

Deno.test("a well-formed code survives normalisation unchanged", () => {
  assertEquals(normaliseReferralCode("ABCD2345"), "ABCD2345");
});

Deno.test("case and punctuation carry no meaning", () => {
  assertEquals(normaliseReferralCode("  abcd-2345 "), "ABCD2345");
});

Deno.test("the four ambiguous letters fold onto what was almost certainly meant", () => {
  // I and L read as 1, O as 0, U as V — the misreads someone makes off a screenshot. Rejecting
  // them would be technically correct and useless to the person holding the phone.
  assertEquals(normaliseReferralCode("ILOU2345"), "110V2345");
  assertEquals(normaliseReferralCode("iloU2345"), normaliseReferralCode("ILOU2345"));
});

Deno.test("anything that is not eight characters is not a code", () => {
  assertEquals(normaliseReferralCode("ABCD234"), null);
  assertEquals(normaliseReferralCode("ABCD23456"), null);
  assertEquals(normaliseReferralCode(""), null);
  assertEquals(normaliseReferralCode(null), null);
  assertEquals(normaliseReferralCode(12345678), null);
});

// ---------------------------------------------------------------- the share link

const STORE = "https://play.google.com/store/apps/details?id=com.spacewire.astrolok";

function settingsWithStore(url: string) {
  return referralSettings(new Map([["referral_store_url", url]]) as AppConfig);
}

Deno.test("the share link is the store listing with the code in referrer", () => {
  const link = shareLinkFor(settingsWithStore(STORE), "ABCD2345")!;

  // The listing already carries `?id=`, so a second `?` would make Play drop everything after it.
  assertEquals(link.startsWith(STORE + "&referrer="), true, link);
  assertEquals(link.split("?").length, 2, "exactly one question mark");
});

Deno.test("the referrer survives exactly one decode, which is what Google performs", () => {
  const link = shareLinkFor(settingsWithStore(STORE), "ABCD2345")!;
  const raw = new URL(link).searchParams.get("referrer")!;

  // `searchParams.get` is the single decode. Anything double-encoded upstream would surface here
  // as literal `%3D`, which is the classic reason a code arrives at the app unusable.
  const parsed = parseReferrerString(raw);
  assertEquals(parsed.ref_code, "ABCD2345");
  assertEquals(parsed.utm_source, "referral");
  assertEquals(parsed.utm_medium, "invite");
});

Deno.test("a referred install resolves back to a referral, end to end", () => {
  const link = shareLinkFor(settingsWithStore(STORE), "ABCD2345")!;
  const raw = new URL(link).searchParams.get("referrer")!;

  const acquisition = resolveAcquisition(parseReferrerString(raw), "install_referrer", "ABCD2345");
  assertEquals(acquisition.source, "referral");
  assertEquals(acquisition.referralCode, "ABCD2345");
});

Deno.test("no store URL means no link, rather than a broken one", () => {
  // A pre-launch deployment has no listing yet. The invite screen says so instead of sharing a
  // URL that 404s.
  assertEquals(shareLinkFor(settingsWithStore(""), "ABCD2345"), null);
  assertEquals(shareLinkFor(settingsWithStore("   "), "ABCD2345"), null);
});

// ---------------------------------------------------------------- acquisition

Deno.test("a referral code outranks every campaign parameter on the same link", () => {
  // An explicit statement that a named user sent this person beats a utm that merely rode along.
  const result = resolveAcquisition(
    { utm_source: "facebook", fbclid: "abc", gclid: "xyz" },
    "deep_link",
    "ABCD2345",
  );
  assertEquals(result.source, "referral");
  assertEquals(result.referralCode, "ABCD2345");
});

Deno.test("gclid is Google Ads, on its own", () => {
  assertEquals(resolveAcquisition({ gclid: "abc" }, "install_referrer", null).source, "google_ads");
});

Deno.test("fbclid and the Meta sources are Meta", () => {
  for (const params of [
    { fbclid: "abc" },
    { utm_source: "facebook" },
    { utm_source: "Instagram" },
    { utm_source: "apps.facebook.com" },
    { utm_source: "ig" },
  ]) {
    assertEquals(resolveAcquisition(params, "install_referrer", null).source, "meta", JSON.stringify(params));
  }
});

Deno.test("a paid medium with an unknown source is paid, not organic", () => {
  // Being wrong towards organic would quietly reclassify paid installs as free and make every
  // campaign look more profitable than it is.
  assertEquals(
    resolveAcquisition({ utm_source: "somenetwork", utm_medium: "cpc" }, "web", null).source,
    "paid_other",
  );
});

Deno.test("the Play Store's own organic stamp resolves to organic", () => {
  assertEquals(
    resolveAcquisition(
      { utm_source: "google-play", utm_medium: "organic" },
      "install_referrer",
      null,
    ).source,
    "organic",
  );
});

Deno.test("nothing at all is organic rather than an error", () => {
  assertEquals(resolveAcquisition({}, "web", null).source, "organic");
});

Deno.test("campaign fields are read from either spelling", () => {
  const result = resolveAcquisition({
    utm_campaign: "diwali",
    utm_id: "1234",
    utm_term: "lookalike_2pc",
    utm_content: "video_a",
  }, "install_referrer", null);

  assertEquals(result.campaign, "diwali");
  assertEquals(result.campaignId, "1234");
  assertEquals(result.adset, "lookalike_2pc");
  assertEquals(result.ad, "video_a");
});

Deno.test("blank parameters are treated as absent, not as empty campaigns", () => {
  const result = resolveAcquisition({ utm_campaign: "   ", utm_source: "" }, "web", null);
  assertEquals(result.campaign, null);
  assertEquals(result.source, "organic");
});

// ---------------------------------------------------------------- install referrer

Deno.test("a Play referrer string is parsed as the query it is", () => {
  const params = parseReferrerString(
    "utm_source=referral&utm_medium=invite&ref_code=ABCD2345",
  );
  assertEquals(params.ref_code, "ABCD2345");
  assertEquals(params.utm_source, "referral");
});

Deno.test("an empty or absent referrer is an answer, not a crash", () => {
  assertEquals(parseReferrerString(null), {});
  assertEquals(parseReferrerString(""), {});
});

// ---------------------------------------------------------------- settings

Deno.test("an untouched deployment has referrals off and a usable claim window", () => {
  const settings = referralSettings(new Map() as AppConfig);
  assertEquals(settings.enabled, false);
  assertEquals(settings.storeUrl, "");
  assertEquals(settings.claimWindowDays, 7);
});

Deno.test("a garbage claim window does not become a zero-day one", () => {
  // A zero-day window would refuse every referral while looking configured.
  const settings = referralSettings(
    new Map([["referral_claim_window_days", "not-a-number"]]) as AppConfig,
  );
  assertEquals(settings.claimWindowDays, 7);

  const zero = referralSettings(
    new Map([["referral_claim_window_days", "0"]]) as AppConfig,
  );
  assertEquals(zero.claimWindowDays, 7);
});

Deno.test("the enabled flag is read independently of the store URL", () => {
  const on = referralSettings(
    new Map([["referral_enabled", "true"], ["referral_store_url", STORE]]) as AppConfig,
  );
  assert(on.enabled);
  assertEquals(on.storeUrl, STORE);
});

// ---------------------------------------------------------------- hardening

Deno.test("a campaign value cannot be arbitrarily long", () => {
  // These are client-supplied and land both in `user_attribution` and in a Mixpanel property, so
  // an unbounded string is an unauthenticated way to write large rows.
  const result = resolveAcquisition(
    { utm_campaign: "x".repeat(5000), utm_content: "y".repeat(5000) },
    "web",
    null,
  );
  assertEquals(result.campaign!.length, 256);
  assertEquals(result.ad!.length, 256);
});

Deno.test("a non-string parameter is ignored rather than coerced", () => {
  const result = resolveAcquisition(
    { utm_campaign: undefined, utm_source: null },
    "web",
    null,
  );
  assertEquals(result.campaign, null);
  assertEquals(result.source, "organic");
});
