import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  CAMPAIGN_KEYS,
  CAMPAIGNS,
  capDeferral,
  insertIdFor,
  istDate,
  istHour,
  istMidnight,
  PUSH_ROUTES,
  quietHoursDeferral,
  SCHEDULED_CAMPAIGNS,
} from "../_shared/notification_campaigns.ts";
import { billingIssueDecision, midCancelDecision, onHoldDecision } from "../_shared/notification_triggers.ts";

/** An instant given as IST wall-clock time. */
const ist = (iso: string) => new Date(`${iso}+05:30`);

// ---------------------------------------------------------------- the registry

Deno.test("every campaign opens an allowed route, and only the cancellation reason may wake anyone", () => {
  for (const key of CAMPAIGN_KEYS) {
    assert((PUSH_ROUTES as readonly string[]).includes(CAMPAIGNS[key].route), key);
    assertEquals(CAMPAIGNS[key].bypassQuietHours, key === "mid_cancel", key);
  }
  assertEquals(SCHEDULED_CAMPAIGNS.includes("mid_cancel"), false);
  assertEquals(SCHEDULED_CAMPAIGNS.includes("billing_issue"), false);
  assertEquals(SCHEDULED_CAMPAIGNS.includes("kundali_ready_lapsed"), false);
  assert(SCHEDULED_CAMPAIGNS.includes("kundali_ready"));
});

Deno.test("the route allowlist matches the app's", async () => {
  // The app drops a tap on a route it does not know. Keep `kPushRoutes` in step with this list.
  const dart = await Deno.readTextFile(new URL("../../../lib/data/firebase/push_payload.dart", import.meta.url))
    .catch(() => null);
  if (dart === null) return; // The app side may not exist yet in a backend-only checkout.
  for (const route of PUSH_ROUTES) assert(dart.includes(`'${route}'`), `app is missing ${route}`);
});

// ---------------------------------------------------------------- IST

Deno.test("IST days and hours are counted from IST midnight, not UTC's", () => {
  const lateNight = ist("2026-09-17T23:30:00");
  assertEquals(istDate(lateNight), "2026-09-17");
  assertEquals(istMidnight(lateNight).toISOString(), "2026-09-16T18:30:00.000Z");
  assertEquals(istHour(lateNight), 23.5);
  assertEquals(istDate(ist("2026-09-18T00:10:00")), "2026-09-18");
});

Deno.test("quiet hours defer to 08:00 IST across midnight, with jitter, and not outside them", () => {
  assertEquals(quietHoursDeferral(ist("2026-09-17T21:59:00"), 22, 8), null);
  assertEquals(quietHoursDeferral(ist("2026-09-17T08:00:00"), 22, 8), null);
  assertEquals(quietHoursDeferral(ist("2026-09-17T22:00:00"), 22, 8)?.toISOString(), ist("2026-09-18T08:00:00").toISOString());
  assertEquals(quietHoursDeferral(ist("2026-09-18T02:15:00"), 22, 8)?.toISOString(), ist("2026-09-18T08:00:00").toISOString());
  assertEquals(quietHoursDeferral(ist("2026-09-18T07:59:00"), 22, 8, 17)?.toISOString(), ist("2026-09-18T08:17:00").toISOString());
  // A daytime window, and none at all.
  assertEquals(quietHoursDeferral(ist("2026-09-17T13:00:00"), 12, 14)?.toISOString(), ist("2026-09-17T14:00:00").toISOString());
  assertEquals(quietHoursDeferral(ist("2026-09-17T23:00:00"), 0, 0), null);
});

Deno.test("the daily cap waits for the next IST day; the gap waits for itself", () => {
  const now = ist("2026-09-17T15:00:00");
  assertEquals(capDeferral({ now, sentToday: 1, cap: 2, lastSentAt: null, minGapMinutes: 180 }), null);
  assertEquals(
    capDeferral({ now, sentToday: 2, cap: 2, lastSentAt: ist("2026-09-17T09:00:00"), minGapMinutes: 180 })?.toISOString(),
    ist("2026-09-18T00:00:00").toISOString(),
  );
  assertEquals(
    capDeferral({ now, sentToday: 1, cap: 2, lastSentAt: ist("2026-09-17T14:00:00"), minGapMinutes: 180 })?.toISOString(),
    ist("2026-09-17T17:00:00").toISOString(),
  );
  assertEquals(capDeferral({ now, sentToday: 1, cap: 2, lastSentAt: ist("2026-09-17T11:00:00"), minGapMinutes: 180 }), null);
  assertEquals(capDeferral({ now, sentToday: 9, cap: 0, lastSentAt: null, minGapMinutes: 0 }), null);
});

Deno.test("insert ids stay inside Mixpanel's 36 characters without hashing", () => {
  const id = insertIdFor("ns", "8a1f5c2e-1234-4abc-9def-001122334455");
  assertEquals(id, "ns:8a1f5c2e12344abc9def001122334455");
  assert(id.length <= 36);
});

// ---------------------------------------------------------------- triggers

const base = {
  fromStatus: "ACTIVE",
  toStatus: "CUSTOMER_CANCELLED",
  functionName: "cashfree-webhook",
  previousCheckedAt: null,
  now: new Date("2026-09-17T10:00:00Z"),
  maxAgeMinutes: 180,
};

Deno.test("a cancellation from the UPI app, or our own cancel screen, asks why", () => {
  assert(midCancelDecision(base));
  assert(midCancelDecision({ ...base, toStatus: "CANCELLED", functionName: "subscription-cancel" }));
  assert(midCancelDecision({ ...base, functionName: "subscription-status" }));
});

Deno.test("housekeeping cancels, repeats and non-cancellations never ask", () => {
  // Plain CANCELLED from anywhere but our cancel endpoint is a merchant-side cancel.
  assertEquals(midCancelDecision({ ...base, toStatus: "CANCELLED", functionName: "subscription-start" }), false);
  assertEquals(midCancelDecision({ ...base, toStatus: "CANCELLED" }), false);
  assertEquals(midCancelDecision({ ...base, fromStatus: "CANCELLED" }), false);
  assertEquals(midCancelDecision({ ...base, toStatus: "ON_HOLD" }), false);
});

Deno.test("the reconcile sweep asks only about a mandate it saw live recently", () => {
  const sweep = { ...base, functionName: "subscription-reconcile" };
  assert(midCancelDecision({ ...sweep, previousCheckedAt: "2026-09-17T08:00:00Z" }));
  assertEquals(midCancelDecision({ ...sweep, previousCheckedAt: "2026-09-17T06:59:00Z" }), false);
  assertEquals(midCancelDecision({ ...sweep, previousCheckedAt: null }), false);
});

Deno.test("billing pushes fire on a new failure or a new hold, not on redeliveries", () => {
  assert(billingIssueDecision({ kind: "RECURRING", status: "FAILED", failed: true, priorStatus: null }));
  assert(billingIssueDecision({ kind: "RECURRING", status: "FAILED", failed: true, priorStatus: "PENDING" }));
  assertEquals(billingIssueDecision({ kind: "RECURRING", status: "FAILED", failed: true, priorStatus: "FAILED" }), false);
  assertEquals(billingIssueDecision({ kind: "AUTH", status: "FAILED", failed: true, priorStatus: null }), false);
  assertEquals(billingIssueDecision({ kind: "RECURRING", status: "PENDING", failed: false, priorStatus: null }), false);

  assert(onHoldDecision("ACTIVE", "ON_HOLD"));
  assertEquals(onHoldDecision("ON_HOLD", "ON_HOLD"), false);
  assertEquals(onHoldDecision("ON_HOLD", "ACTIVE"), false);
});
