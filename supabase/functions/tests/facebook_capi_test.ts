import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";

import {
  configureFacebookCapi,
  facebookCapiConfigured,
  reportRenewalPurchase,
} from "../_shared/facebook_capi.ts";

/** One captured outbound call. */
interface Captured {
  url: string;
  body: unknown;
}

/** Swaps `fetch` for a recorder, so the module can be exercised without the network. */
function captureFetch(): { calls: Captured[]; restore: () => void } {
  const calls: Captured[] = [];
  const original = globalThis.fetch;

  globalThis.fetch = ((url: string | URL | Request, init?: RequestInit) => {
    calls.push({
      url: String(url),
      body: JSON.parse(String(init?.body ?? "null")),
    });
    return Promise.resolve(new Response("{}", { status: 200 }));
  }) as typeof fetch;

  return { calls, restore: () => { globalThis.fetch = original; } };
}

/** A fully switched-on configuration, overridable per test. */
function configWith(overrides: Record<string, string> = {}): Map<string, string> {
  return new Map(Object.entries({
    facebook_dataset_id: "ds_1",
    facebook_capi_access_token: "tok_1",
    facebook_capi_enabled: "true",
    facebook_graph_api_version: "v26.0",
    facebook_capi_test_event_code: "",
    ...overrides,
  }));
}

const USER_ID = "11111111-2222-3333-4444-555555555555";

/** SHA-256 of `11111111-2222-3333-4444-555555555555`. */
const USER_ID_HASH = "666ff6ccaa5b3c07feaa3a95d3a4bd2c46ac9e9abdb09ca9133528d3dc1e8952";

/** SHA-256 of `919876543210` — the ten-digit column value with India's country code restored. */
const PHONE_HASH = "92b5072176e723878b5e06ff3ca61898e4eb74e8c46642a0f2db800b17364ab0";

function renewal(overrides: Record<string, unknown> = {}) {
  return {
    userId: USER_ID,
    mobileNo: "9876543210",
    cfPaymentId: "cf_99",
    amount: 499,
    currency: "INR",
    // Recent, so the seven-day guard is not what is under test here.
    paidAt: new Date(Date.now() - 60_000).toISOString(),
    platform: "android",
    ...overrides,
  };
}

/** The single event out of a captured /events call. */
// deno-lint-ignore no-explicit-any
function soleEvent(calls: Captured[]): Record<string, any> {
  assertEquals(calls.length, 1);
  const body = calls[0].body as { data: Array<Record<string, unknown>> };
  assertEquals(body.data.length, 1);
  return body.data[0];
}

Deno.test("reporting stays off until the dataset, the token and the switch are all present", async () => {
  const { calls, restore } = captureFetch();
  try {
    const off: Record<string, string>[] = [
      { facebook_dataset_id: "" },
      { facebook_capi_access_token: "" },
      { facebook_capi_enabled: "false" },
    ];

    for (const overrides of off) {
      configureFacebookCapi(configWith(overrides), "test");
      assertFalse(facebookCapiConfigured());
      await reportRenewalPurchase(renewal());
    }

    // Half-configured is the normal state while someone is pasting credentials into the
    // dashboard, and the kill switch is how this is turned off without a deploy. None of the
    // three may produce a call.
    assertEquals(calls.length, 0);
  } finally {
    restore();
  }
});

Deno.test("a renewal is reported as a Purchase keyed on the charge", async () => {
  const { calls, restore } = captureFetch();
  try {
    configureFacebookCapi(configWith(), "cashfree-webhook");
    assert(facebookCapiConfigured());

    await reportRenewalPurchase(renewal());

    assert(calls[0].url.startsWith("https://graph.facebook.com/v26.0/ds_1/events?access_token="));

    const event = soleEvent(calls);
    assertEquals(event.event_name, "Purchase");
    assertEquals(event.action_source, "app");
    assertEquals(event.custom_data, { currency: "INR", value: 499 });

    // Keyed on the charge, never the delivery attempt: Cashfree redelivers freely and the
    // reconcile sweep replays history, and a renewal counted twice teaches the optimiser to pay
    // twice what a customer is worth.
    assertEquals(event.event_id, "pay:cf_99");
  } finally {
    restore();
  }
});

Deno.test("the account id and the phone are hashed the way Meta matches on", async () => {
  const { calls, restore } = captureFetch();
  try {
    configureFacebookCapi(configWith(), "test");
    await reportRenewalPurchase(renewal());

    // `external_id` is hashed because the client SDK hashes whatever `setUserData` is given. Send
    // it any other way and the two sources describe two different people.
    assertEquals(soleEvent(calls).user_data, {
      external_id: [USER_ID_HASH],
      ph: [PHONE_HASH],
    });
  } finally {
    restore();
  }
});

Deno.test("a number already carrying the country code hashes to the same person", async () => {
  const { calls, restore } = captureFetch();
  try {
    configureFacebookCapi(configWith(), "test");
    await reportRenewalPurchase(renewal({ mobileNo: "+91 98765-43210" }));

    assertEquals(soleEvent(calls).user_data.ph, [PHONE_HASH]);
  } finally {
    restore();
  }
});

Deno.test("an unusable phone number is dropped rather than guessed at", async () => {
  const { calls, restore } = captureFetch();
  try {
    configureFacebookCapi(configWith(), "test");
    await reportRenewalPurchase(renewal({ mobileNo: "12345" }));

    // One lost match costs a conversion; a wrongly matched hash attributes a payment to a
    // stranger. The event still goes, on the account id alone.
    const userData = soleEvent(calls).user_data;
    assertEquals(userData.external_id, [USER_ID_HASH]);
    assertFalse("ph" in userData);
  } finally {
    restore();
  }
});

Deno.test("a payment older than Meta's seven-day window is dropped, not back-dated", async () => {
  const { calls, restore } = captureFetch();
  try {
    configureFacebookCapi(configWith(), "subscription-reconcile");
    await reportRenewalPurchase(renewal({
      paidAt: new Date(Date.now() - 8 * 24 * 60 * 60 * 1000).toISOString(),
    }));

    // The reconcile sweep can surface a payment for the first time long after it was taken. Meta
    // would reject it, and stamping it "now" would corrupt the attribution window this exists to
    // inform.
    assertEquals(calls.length, 0);
  } finally {
    restore();
  }
});

Deno.test("the device marker follows the platform, defaulting to Android", async () => {
  const { calls, restore } = captureFetch();
  try {
    configureFacebookCapi(configWith(), "test");

    await reportRenewalPurchase(renewal({ platform: "ios" }));
    assertEquals(soleEvent(calls).app_data.extinfo[0], "i2");

    calls.length = 0;
    await reportRenewalPurchase(renewal({ platform: null }));
    const extinfo = soleEvent(calls).app_data.extinfo;
    assertEquals(extinfo[0], "a2");

    // Sixteen fields, of which the server can honestly fill exactly one. Meta's documentation
    // prescribes empty strings for the rest.
    assertEquals(extinfo.length, 16);
    assertEquals(extinfo.slice(1), new Array(15).fill(""));
  } finally {
    restore();
  }
});

Deno.test("the test event code is attached only while it is configured", async () => {
  const { calls, restore } = captureFetch();
  try {
    configureFacebookCapi(configWith({ facebook_capi_test_event_code: "TEST123" }), "test");
    await reportRenewalPurchase(renewal());
    assertEquals((calls[0].body as Record<string, unknown>).test_event_code, "TEST123");

    // Cleared, because left set in production it keeps real conversions in test mode, where they
    // optimise nothing.
    calls.length = 0;
    configureFacebookCapi(configWith(), "test");
    await reportRenewalPurchase(renewal());
    assertFalse("test_event_code" in (calls[0].body as Record<string, unknown>));
  } finally {
    restore();
  }
});

Deno.test("an unreachable Meta never reaches the caller", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.reject(new Error("network down"))) as typeof fetch;

  try {
    configureFacebookCapi(configWith(), "cashfree-webhook");

    // This hangs off the only path that makes an account paid. An ad-reporting outage must cost
    // the campaign its conversion, never the user their subscription.
    await reportRenewalPurchase(renewal());
  } finally {
    globalThis.fetch = original;
  }
});
