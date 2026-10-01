import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";

import {
  chargesToRecord,
  chunked,
  groupPendingEvents,
  isForeignSubscription,
  paymentIdsOf,
  PendingEvent,
} from "../_shared/payment_sync.ts";

/**
 * `payment-sync`, the every-minute worker behind queued Cashfree webhooks: which deliveries are
 * another product's, how deliveries collapse onto one sync per subscription, and which charges
 * are worth recording again.
 */

let nextId = 1;
function delivery(overrides: Partial<PendingEvent> & { at: string }): PendingEvent {
  const { at, ...rest } = overrides;
  return {
    id: nextId++,
    event_type: "SUBSCRIPTION_STATUS_CHANGED",
    subscription_id: null,
    cf_subscription_id: null,
    payload: {},
    received_at: at,
    attempts: 1,
    ...rest,
  };
}

function charge(cfPaymentId: string, status: string) {
  return { data: { cf_payment_id: cfPaymentId, payment_status: status, payment_amount: 499 } };
}

Deno.test("only a named subscription that is not ours is foreign", () => {
  assert(isForeignSubscription("c360_91f0_1790000000"));
  assert(isForeignSubscription("ca_123"));
  assert(isForeignSubscription("mt_9"));

  assertFalse(isForeignSubscription("alk_4f3c2b1a0e9d8c7b6a5f4e3d2c1b0a99_1790000000"));
  // A refund or dispute names only a payment, and may well be ours.
  assertFalse(isForeignSubscription(null));
  assertFalse(isForeignSubscription(undefined));
  assertFalse(isForeignSubscription(""));
});

Deno.test("deliveries collapse onto their subscription, oldest first", () => {
  const late = delivery({ subscription_id: "alk_a", at: "2026-09-29T06:31:00Z" });
  const early = delivery({ subscription_id: "alk_a", at: "2026-09-29T06:30:00Z" });
  const other = delivery({ subscription_id: "alk_b", at: "2026-09-29T06:30:30Z" });

  const { bySubscription, unresolved } = groupPendingEvents([late, other, early], new Map());

  assertEquals([...bySubscription.keys()].sort(), ["alk_a", "alk_b"]);
  assertEquals(bySubscription.get("alk_a")!.map((e) => e.id), [early.id, late.id]);
  assertEquals(unresolved, []);
});

Deno.test("a delivery with only Cashfree's id joins its subscription, and one naming nothing is unresolved", () => {
  const ours = delivery({ subscription_id: "alk_a", at: "2026-09-29T06:30:00Z" });
  const byCfId = delivery({ cf_subscription_id: "1234", at: "2026-09-29T06:30:05Z" });
  const unknownCfId = delivery({ cf_subscription_id: "9999", at: "2026-09-29T06:30:06Z" });
  const nothing = delivery({ event_type: "SETTLEMENT", at: "2026-09-29T06:30:07Z" });

  const { bySubscription, unresolved } = groupPendingEvents(
    [ours, byCfId, unknownCfId, nothing],
    new Map([["1234", "alk_a"]]),
  );

  assertEquals(bySubscription.get("alk_a")!.map((e) => e.id), [ours.id, byCfId.id]);
  assertEquals(unresolved.map((e) => e.id), [unknownCfId.id, nothing.id]);
});

Deno.test("a charge already in the ledger at that status is not recorded again", () => {
  const events = [
    // AUTH_STATUS and PAYMENT_SUCCESS both announce the one charge.
    delivery({ event_type: "SUBSCRIPTION_AUTH_STATUS", payload: charge("p1", "SUCCESS"), at: "2026-09-29T06:30:00Z" }),
    delivery({ event_type: "SUBSCRIPTION_PAYMENT_SUCCESS", payload: charge("p1", "SUCCESS"), at: "2026-09-29T06:30:01Z" }),
    // Already recorded as FAILED before this run.
    delivery({ event_type: "SUBSCRIPTION_PAYMENT_FAILED", payload: charge("p2", "FAILED"), at: "2026-09-29T06:30:02Z" }),
    // No charge at all.
    delivery({ payload: { data: { subscription_status: "ACTIVE" } }, at: "2026-09-29T06:30:03Z" }),
  ];
  const ledger = new Map([["p2", "FAILED"]]);

  const charges = chargesToRecord(events, ledger);

  assertEquals(charges.map((c) => [c.payment.cfPaymentId, c.payment.status]), [["p1", "SUCCESS"]]);
  assertEquals(charges[0].event.id, events[0].id);
  // Taken charges are remembered, so a later group in the same run cannot record it twice.
  assertEquals(ledger.get("p1"), "SUCCESS");
});

Deno.test("a change of status is always recorded, in the order it arrived", () => {
  const events = [
    delivery({ payload: charge("p1", "PENDING"), at: "2026-09-29T06:30:00Z" }),
    delivery({ payload: charge("p1", "SUCCESS"), at: "2026-09-29T06:30:01Z" }),
  ];

  const charges = chargesToRecord(events, new Map([["p1", "INITIALIZED"]]));

  assertEquals(charges.map((c) => c.payment.status), ["PENDING", "SUCCESS"]);
});

Deno.test("a truncated or empty payload carries no charge", () => {
  const events = [
    delivery({ payload: { truncated: 70_000 }, at: "2026-09-29T06:30:00Z" }),
    delivery({ payload: null, at: "2026-09-29T06:30:01Z" }),
  ];
  assertEquals(chargesToRecord(events, new Map()), []);
  assertEquals(paymentIdsOf(events), []);
});

Deno.test("payment ids are read once each, and long lists are sliced", () => {
  const events = [
    delivery({ payload: charge("p1", "PENDING"), at: "2026-09-29T06:30:00Z" }),
    delivery({ payload: charge("p1", "SUCCESS"), at: "2026-09-29T06:30:01Z" }),
    delivery({ payload: charge("p2", "FAILED"), at: "2026-09-29T06:30:02Z" }),
  ];
  assertEquals(paymentIdsOf(events).sort(), ["p1", "p2"]);

  assertEquals(chunked([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  assertEquals(chunked([], 100), []);
});
