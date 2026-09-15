/**
 * Server-side Meta Conversions API, for the one conversion the app can never report.
 *
 * The client's `FacebookAnalytics` reports exactly one `Purchase` per device — the ₹3 that
 * authorises the mandate — and then latches a flag on disk so it can never report another. The
 * ₹499 that arrives a month later is a UPI Autopay debit taken on Cashfree's schedule, at 3am,
 * with no app running. Nothing on the device observes it, so until now Meta's optimiser has been
 * bidding against a trial fee while the revenue it should be buying was invisible.
 *
 * This is the other half: every recurring debit the server actually credits is reported here as a
 * `Purchase` carrying the amount Cashfree confirms, so the optimiser can learn to buy payers
 * rather than trial-starters.
 *
 * ## What this is not
 *
 * Not a second analytics sink. `trackServer` in `mixpanel.ts` takes the whole subscription
 * lifecycle — renewals, holds, failures, refunds, disputes. This takes one event. Meta's catalogue
 * is an ad-targeting surface, and the rule the client established in `facebook_analytics.dart`
 * holds on the server too: Facebook learns what it needs to buy the right users, and nothing else.
 *
 * ## Why the App Secret is not here
 *
 * `20260908000003_facebook.sql` says the Facebook app secret must never enter `app_config`, and
 * that stays true — this does not use one. The modern app-event path authenticates with a **token
 * generated against a Dataset** in Events Manager, and addresses a **Dataset ID** that has been
 * linked to the app. The secret belongs to an older `/{app_id}/activities` endpoint we do not call.
 *
 * ## Match quality, honestly
 *
 * Meta matches an app event best on a device advertising id (`madid`) or the SDK's own
 * `anon_id`. The server holds neither, and no table stores a device model, OS version or locale
 * either. So this sends the two identifiers it does have — the phone and the account id — and
 * fills Meta's device array with the placeholders its documentation permits. That is enough for
 * the conversion to be credited to the ad; it is not the match rate a client-side send would get.
 * See the follow-ups in `FACEBOOK_ADS_TRACKING_GUIDE.md`.
 */

import { AppConfig, configFlag, configSetting } from "./config.ts";

/** Long enough for a normal call, short enough that Cashfree never waits on ad reporting. */
const TIMEOUT_MS = 4_000;

/**
 * Meta rejects an event whose `event_time` is more than seven days old.
 *
 * This is not hypothetical here: the reconcile sweep replays history, and a payment that was
 * never delivered as a webhook can surface for the first time long after it was taken. Such an
 * event is dropped rather than back-dated — see [reportRenewalPurchase].
 */
const MAX_EVENT_AGE_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * Set once per request by the entry point, exactly as `configureMixpanel` does.
 *
 * Module-level for the same reason and with the same safety argument: `recordPayment` sits five
 * frames below the handler, and there is one dataset for the whole deployment, so a warm instance
 * reusing these is reusing the values it would have been handed anyway.
 */
let datasetId = "";
let accessToken = "";
let apiVersion = "v26.0";
let enabled = false;
let testEventCode = "";
let source = "unknown";

export function configureFacebookCapi(config: AppConfig, functionName: string): void {
  datasetId = configSetting(config, "facebook_dataset_id");
  accessToken = configSetting(config, "facebook_capi_access_token");
  enabled = configFlag(config, "facebook_capi_enabled");
  testEventCode = configSetting(config, "facebook_capi_test_event_code");
  source = functionName;

  // Pinned deliberately rather than tracking "latest": a Graph API version is stable for about two
  // years, and a silent bump is how a working integration starts failing on a schedule nobody set.
  const version = configSetting(config, "facebook_graph_api_version");
  if (version) apiVersion = version;
}

/**
 * True only when reporting is switched on *and* both credentials are present.
 *
 * Three separate ways to be off, all of them legitimate: a checkout that was never pointed at a
 * dataset, a deployment mid-setup with the token still blank, and the kill switch. Mirrors how
 * `mixpanelConfigured` treats a blank project token.
 */
export function facebookCapiConfigured(): boolean {
  return enabled && datasetId.length > 0 && accessToken.length > 0;
}

export interface RenewalPurchase {
  /** `users.user_id`. Hashed into `external_id`, matching what the app SDK was given. */
  userId: string;
  /** `users.mobile_no` — a bare 10-digit Indian mobile, per the CHECK constraint on the column. */
  mobileNo: string | null;
  /** Cashfree's payment id. Becomes `event_id`, so a redelivery collapses onto the same event. */
  cfPaymentId: string;
  /** What Cashfree says it took. Authoritative — never the price label from `app_config`. */
  amount: number;
  currency: string;
  /** When the money actually moved. */
  paidAt: string | null;
  /** From `push_tokens`, when this user has one. Decides Meta's `a2`/`i2` marker. */
  platform: string | null;
}

/**
 * Reports one recurring debit as a Meta `Purchase`.
 *
 * Never throws and never delays the caller materially. This hangs off `recordPayment`, which is
 * the only path by which an account becomes paid: an unreachable Meta must cost the campaign its
 * conversion, never the user their subscription.
 *
 * Deduplication is deliberately layered, because one renewal reported twice teaches the optimiser
 * to pay twice what a customer is worth:
 *
 *  1. **The caller's `alreadyCredited` guard** returns before reaching here for any charge already
 *     recorded as SUCCESS, which is what actually stops Cashfree's redeliveries and the hourly
 *     reconcile sweep. This is the real guard.
 *  2. **`event_id` keyed on the charge**, not on the delivery attempt — the same rule `$insert_id`
 *     follows in `mixpanel.ts`. Meta collapses repeats within its own window if one ever escapes.
 */
export async function reportRenewalPurchase(purchase: RenewalPurchase): Promise<void> {
  if (!facebookCapiConfigured()) return;

  try {
    const occurredAt = purchase.paidAt ? Date.parse(purchase.paidAt) : Date.now();
    const eventTime = Number.isFinite(occurredAt) ? occurredAt : Date.now();

    // Back-dating would be worse than dropping: Meta would reject the call anyway, and a event
    // stamped "now" for money that moved last month corrupts the very attribution window this
    // exists to inform.
    if (Date.now() - eventTime > MAX_EVENT_AGE_MS) {
      console.error(
        `facebook capi: skipping ${purchase.cfPaymentId}, ` +
          `payment time ${purchase.paidAt} is older than Meta's seven-day window`,
      );
      return;
    }

    const userData: Record<string, unknown> = {
      // Hashed, because the SDK hashes whatever `setUserData(externalId:)` is given on the device.
      // Send it any other way and the two sources describe two different people.
      external_id: [await sha256Hex(purchase.userId)],
    };

    const phone = normalisePhone(purchase.mobileNo);
    if (phone) userData.ph = [await sha256Hex(phone)];

    const event: Record<string, unknown> = {
      event_name: "Purchase",
      event_time: Math.floor(eventTime / 1000),
      event_id: `pay:${purchase.cfPaymentId}`,
      action_source: "app",
      user_data: userData,
      custom_data: {
        currency: (purchase.currency || "INR").toUpperCase(),
        value: purchase.amount,
      },
      app_data: appData(purchase.platform),
    };

    const body: Record<string, unknown> = { data: [event] };

    // Only ever set while validating against Events Manager's Test Events view. Left set in
    // production it keeps real conversions in test mode, where they optimise nothing.
    if (testEventCode) body.test_event_code = testEventCode;

    send(
      `https://graph.facebook.com/${apiVersion}/${datasetId}/events` +
        `?access_token=${encodeURIComponent(accessToken)}`,
      body,
    );
  } catch (error) {
    // Hashing or JSON, not the network — the send below has its own catch. Logged, never rethrown.
    console.error("facebook capi: could not build the purchase event", String(error));
  }
}

/**
 * Meta's device block, which `action_source: "app"` obliges us to send.
 *
 * Every field in it describes a handset, and this runs on an edge node hours after that handset
 * was last seen — no table stores a device model, OS version, screen size, carrier or locale. So
 * this sends the one marker Meta needs to parse the array and the empty-string placeholders its
 * documentation prescribes for missing values.
 *
 * `advertiser_tracking_enabled: 1` is an approximation and worth naming as one. On Android there
 * is no tracking gate, which is the bulk of this audience; on iOS the honest answer is whatever
 * the ATT prompt returned, and that answer is never persisted anywhere the server can read.
 */
function appData(platform: string | null): Record<string, unknown> {
  const extinfo = new Array(16).fill("");
  extinfo[0] = platform?.toLowerCase() === "ios" ? "i2" : "a2";

  return {
    advertiser_tracking_enabled: 1,
    application_tracking_enabled: 1,
    extinfo,
  };
}

/**
 * A phone number in the only form Meta will match on: country code, digits, nothing else.
 *
 * `users.mobile_no` is a bare 10-digit Indian mobile — the CHECK constraint on the column
 * guarantees it — so the country code has to be added back here. Anything that does not look like
 * that after stripping is dropped rather than guessed at: an unmatchable hash costs one match,
 * while a *wrongly* matched hash attributes a payment to a stranger.
 */
function normalisePhone(mobileNo: string | null): string | null {
  if (!mobileNo) return null;

  const digits = mobileNo.replace(/\D/g, "");
  if (digits.length === 10) return `91${digits}`;
  if (digits.length === 12 && digits.startsWith("91")) return digits;
  return null;
}

/** Lowercase hex SHA-256, which is the only encoding Meta accepts for a hashed parameter. */
async function sha256Hex(value: string): Promise<string> {
  const normalised = value.trim().toLowerCase();
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(normalised));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Hands the send to the runtime and returns immediately.
 *
 * Identical reasoning to `mixpanel.ts`: awaited, a slow Meta would add its round trip to every
 * webhook response, and a hanging one would push the handler past Cashfree's timeout into a retry
 * — turning an ad-reporting outage into a payment incident. `EdgeRuntime.waitUntil` keeps the
 * isolate alive without holding the response; where it does not exist (a local run, a test) the
 * promise is awaited so nothing is silently dropped.
 */
function send(url: string, body: unknown): Promise<void> {
  const pending = post(url, body);

  const runtime = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } })
    .EdgeRuntime;

  if (typeof runtime?.waitUntil === "function") {
    runtime.waitUntil(pending);
    return Promise.resolve();
  }

  return pending;
}

async function post(url: string, body: unknown): Promise<void> {
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
        signal: controller.signal,
      });

      if (!response.ok) {
        // Read the body: Meta explains *why* it rejected an event, and without that a bad hash or
        // a dataset that was never linked to the app is indistinguishable from a network blip.
        // The url is deliberately not logged — it carries the access token.
        const detail = await response.text().catch(() => "");
        console.error(`facebook capi responded ${response.status}: ${detail.slice(0, 500)}`);
      }
    } finally {
      clearTimeout(timer);
    }
  } catch (error) {
    // Includes the abort. Logged, never rethrown.
    console.error(`facebook capi send failed (${source})`, String(error));
  }
}
