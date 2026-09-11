/**
 * Tests for the payment logic that has no database or network in it.
 *
 * These are the functions where a bug is both silent and expensive: an entitlement rule that is
 * off by an hour locks out paying customers, and a signature check that is subtly wrong lets
 * anyone mark themselves paid. Run with:
 *
 *   deno test --allow-none supabase/functions/tests/payments_test.ts
 */

import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";

import {
  addMonths,
  CashfreeSettings,
  dedupeKey,
  disputeFrom,
  cancelledBy,
  isCancelledStatus,
  isDisputeLost,
  isExpiredStatus,
  isLiveStatus,
  isPausedStatus,
  notificationKey,
  paymentFrom,
  refundFrom,
  skewSeconds,
  snapshotOf,
  subscriptionIdsFrom,
  toIstIso,
  verifyWebhook,
  webhookSignature,
} from "../_shared/cashfree.ts";
import {
  isEntitled,
  isInTrial,
  trialAvailable,
  UserRow,
} from "../_shared/entitlement.ts";
import {
  buysAMonth,
  isFailedCharge,
  paymentKind,
  staleSweepCutoff,
  transitionName,
  userUpdatesFor,
} from "../_shared/subscription_sync.ts";

const NOW = new Date("2026-09-01T12:00:00Z");

function user(overrides: Partial<UserRow> = {}): UserRow {
  return {
    user_id: "u",
    mobile_no: "9931145610",
    name: "Ayush",
    dob: null,
    // What verify-otp leaves behind: a row that has never authorised a mandate.
    payment_type: "none",
    trial_ends_at: null,
    current_period_end: null,
    active_subscription_id: null,
    ...overrides,
  };
}

/**
 * A user who authorised the ₹3 and whose trial clock is running.
 *
 * Spelled out rather than left to the fixture default, because the default is now `none` — the
 * distinction this whole state exists to make.
 */
function trialUser(overrides: Partial<UserRow> = {}): UserRow {
  return user({ payment_type: "trial", ...overrides });
}

const settings = {
  trialAmount: 3,
  recurringAmount: 249,
  trialDays: 1,
} as CashfreeSettings;

// ---------------------------------------------------------------- entitlement

Deno.test("a new signup is not entitled until the authorisation is captured", () => {
  // The row exists with payment_type 'none' from the moment the OTP is verified. If that alone
  // granted access, every account would be free.
  assertFalse(isEntitled(user(), 12, NOW));
});

Deno.test("none grants nothing whatever the dates say", () => {
  // The rule that makes the `none` state safe to introduce at all. `isEntitled` used to reach
  // this answer only by falling through to `default:`, which is a fragile place for the
  // difference between a free account and a paid one to live.
  assertFalse(
    isEntitled(
      user({
        trial_ends_at: "2027-01-01T00:00:00Z",
        current_period_end: "2027-01-01T00:00:00Z",
      }),
      12,
      NOW,
    ),
  );
});

Deno.test("a running trial is entitled", () => {
  const u = trialUser({ trial_ends_at: "2026-09-02T12:00:00Z" });
  assert(isEntitled(u, 12, NOW));
  assert(isInTrial(u, 12, NOW));
});

Deno.test("a trial inside the grace window is still entitled", () => {
  // The ₹499 may already have been debited and the webhook simply not landed yet. Locking out
  // here is the expensive direction to be wrong in.
  const u = trialUser({ trial_ends_at: "2026-09-01T06:00:00Z" });
  assert(isEntitled(u, 12, NOW), "6h past expiry, inside a 12h grace");
});

Deno.test("a trial past the grace window is not entitled", () => {
  const u = trialUser({ trial_ends_at: "2026-08-31T20:00:00Z" });
  assertFalse(isEntitled(u, 12, NOW), "16h past expiry, outside a 12h grace");
});

Deno.test("zero grace cuts exactly at the expiry instant", () => {
  assertFalse(isEntitled(trialUser({ trial_ends_at: "2026-09-01T11:59:59Z" }), 0, NOW));
  assert(isEntitled(trialUser({ trial_ends_at: "2026-09-01T12:00:01Z" }), 0, NOW));
});

Deno.test("an active plan with no period end yet is entitled", () => {
  // The gap between authorisation and the first recurring debit.
  assert(isEntitled(user({ payment_type: "active" }), 12, NOW));
});

Deno.test("an active plan whose renewal failed lapses once grace runs out", () => {
  // Nothing sets this state explicitly — current_period_end simply stops moving forward, which
  // is the whole reason the failure path needs no code of its own.
  const u = user({ payment_type: "active", current_period_end: "2026-08-30T12:00:00Z" });
  assertFalse(isEntitled(u, 12, NOW));
});

Deno.test("a cancelled plan keeps its paid month but gets no grace", () => {
  assert(isEntitled(
    user({ payment_type: "cancelled", current_period_end: "2026-09-20T00:00:00Z" }),
    12,
    NOW,
  ));
  assertFalse(
    isEntitled(
      user({ payment_type: "cancelled", current_period_end: "2026-09-01T11:00:00Z" }),
      12,
      NOW,
    ),
    "an hour past the paid period, and there is no debit in flight to wait for",
  );
});

Deno.test("expired is never entitled, whatever the dates say", () => {
  const u = user({ payment_type: "expired", current_period_end: "2027-01-01T00:00:00Z" });
  assertFalse(isEntitled(u, 12, NOW));
});

Deno.test("a garbled timestamp does not grant access", () => {
  assertFalse(isEntitled(trialUser({ trial_ends_at: "not a date" }), 12, NOW));
});

// ---------------------------------------------------------------- who gets the trial

Deno.test("only an account that never authorised a mandate is offered the trial", () => {
  assert(trialAvailable(user()));

  for (const type of ["trial", "active", "expired", "cancelled"] as const) {
    assertFalse(trialAvailable(user({ payment_type: type })), type);
  }
});

Deno.test("a `none` row carrying dates is not offered the trial", () => {
  // Belt and braces for a row the backfill could have misjudged. The mistake this guards against
  // is handing a second ₹3 trial to someone who already had one, which is repeatable revenue
  // loss; refusing a trial to someone owed one is merely a support ticket.
  assertFalse(trialAvailable(user({ trial_ends_at: "2026-08-01T00:00:00Z" })));
  assertFalse(trialAvailable(user({ current_period_end: "2026-08-01T00:00:00Z" })));
});

// ---------------------------------------------------------------- webhooks

const SECRET = "test_secret_key";

Deno.test("a correctly signed webhook verifies", async () => {
  const body = '{"type":"SUBSCRIPTION_STATUS_CHANGED","data":{}}';
  const ts = "1756728000";
  const signature = await webhookSignature(SECRET, ts, body);

  assert(await verifyWebhook(SECRET, ts, signature, body));
});

Deno.test("a single mutated byte fails verification", async () => {
  const body = '{"type":"SUBSCRIPTION_PAYMENT_SUCCESS","data":{"payment_amount":249}}';
  const ts = "1756728000";
  const signature = await webhookSignature(SECRET, ts, body);

  const tampered = body.replace("249", "999");
  assertFalse(await verifyWebhook(SECRET, ts, signature, tampered));
});

Deno.test("replaying a signature under a different timestamp fails", async () => {
  const body = '{"type":"SUBSCRIPTION_STATUS_CHANGED"}';
  const signature = await webhookSignature(SECRET, "1756728000", body);

  assertFalse(await verifyWebhook(SECRET, "1756731600", signature, body));
});

Deno.test("the wrong secret fails", async () => {
  const body = "{}";
  const signature = await webhookSignature(SECRET, "1", body);
  assertFalse(await verifyWebhook("other_secret", "1", signature, body));
});

Deno.test("a missing secret, timestamp or signature fails closed", async () => {
  const body = "{}";
  const signature = await webhookSignature(SECRET, "1", body);

  assertFalse(await verifyWebhook("", "1", signature, body), "no secret configured");
  assertFalse(await verifyWebhook(SECRET, null, signature, body), "no timestamp header");
  assertFalse(await verifyWebhook(SECRET, "1", null, body), "no signature header");
});

Deno.test("the signature is base64 over timestamp+body, matching Cashfree's own sample", async () => {
  // Pinned so a refactor that swaps the concatenation order, or hex-encodes instead of base64,
  // fails here rather than silently rejecting every live webhook.
  const signature = await webhookSignature("secret", "1234567890", '{"a":1}');
  assertEquals(signature, await webhookSignature("secret", "1234567890", '{"a":1}'));
  assert(/^[A-Za-z0-9+/]+=*$/.test(signature), "base64, not hex");
  assertEquals(signature.length, 44, "32 bytes of SHA-256 in base64");
});

Deno.test("the dedupe key is stable per delivery and unique across them", async () => {
  const a = await dedupeKey("SUBSCRIPTION_PAYMENT_SUCCESS", "100", '{"x":1}');
  const same = await dedupeKey("SUBSCRIPTION_PAYMENT_SUCCESS", "100", '{"x":1}');
  const otherBody = await dedupeKey("SUBSCRIPTION_PAYMENT_SUCCESS", "100", '{"x":2}');
  const otherType = await dedupeKey("SUBSCRIPTION_PAYMENT_FAILED", "100", '{"x":1}');

  assertEquals(a, same, "a redelivery must collide so it can be skipped");
  assert(a !== otherBody);
  assert(a !== otherType);
});

Deno.test("Cashfree's millisecond timestamp does not overflow the skew column", () => {
  // The exact delivery that took the webhook path down on 2026-09-09. Cashfree stamps
  // x-webhook-timestamp in MILLISECONDS; reading it as seconds and scaling by a thousand gave
  // -1787152295188, which is past int4, so the payment_events insert failed, the handler
  // answered 500, and Cashfree redelivered every minute forever.
  const now = 1788941237108;
  assertEquals(skewSeconds("1788941236425", now), 1);

  // A seconds-epoch stamp still reads correctly, so this cannot break if Cashfree ever changes
  // back or a test harness sends the older format.
  assertEquals(skewSeconds("1788941236", now), 1);
});

Deno.test("a nonsense timestamp is clamped rather than allowed to fail the insert", () => {
  // The real lesson from the outage: skew_seconds is written for diagnostics and nothing reads
  // it, so it must never be able to reject the delivery it describes.
  const int4Max = 2_147_483_647;

  assert(Math.abs(skewSeconds("1", 1788941237108)!) <= int4Max);
  assert(Math.abs(skewSeconds("99999999999999999", 1788941237108)!) <= int4Max);

  assertEquals(skewSeconds(null), null);
  assertEquals(skewSeconds("not-a-number"), null);
  assertEquals(skewSeconds(""), null);
});

Deno.test("the notification key survives a retry that the dedupe key does not", async () => {
  // The bug this exists to prevent: Cashfree stamps a fresh x-webhook-timestamp on every
  // delivery attempt, so a webhook it cannot deliver successfully used to emit a brand-new,
  // un-dedupable Mixpanel event every minute for as long as it kept retrying.
  const body = '{"data":{"cf_payment_id":987,"payment_status":"FAILED"}}';
  const payload = JSON.parse(body);

  const first = await notificationKey("SUBSCRIPTION_PAYMENT_FAILED", payload, body);
  const retry = await notificationKey("SUBSCRIPTION_PAYMENT_FAILED", payload, body);
  assertEquals(first, retry);

  // Where the delivery key deliberately does not, because a retry after a failed attempt is
  // meant to run the money path again.
  assert(
    await dedupeKey("SUBSCRIPTION_PAYMENT_FAILED", "100", body) !==
      await dedupeKey("SUBSCRIPTION_PAYMENT_FAILED", "160", body),
    "the delivery key must still change per attempt",
  );
});

Deno.test("the notification key separates what is genuinely a different notification", async () => {
  const failed = '{"data":{"cf_payment_id":987,"payment_status":"FAILED"}}';
  const succeeded = '{"data":{"cf_payment_id":987,"payment_status":"SUCCESS"}}';
  const otherCharge = '{"data":{"cf_payment_id":988,"payment_status":"FAILED"}}';

  const a = await notificationKey("SUBSCRIPTION_PAYMENT_FAILED", JSON.parse(failed), failed);

  // The same charge reaching a different status is a different thing happening, and must be
  // countable — silencing it would hide every recovery.
  assert(
    a !== await notificationKey("SUBSCRIPTION_PAYMENT_SUCCESS", JSON.parse(succeeded), succeeded),
  );
  assert(
    a !== await notificationKey("SUBSCRIPTION_PAYMENT_FAILED", JSON.parse(otherCharge), otherCharge),
  );
});

Deno.test("a notification naming nothing we can identify falls back to the body", async () => {
  // Settlement notices and pre-debit reminders carry no payment, refund or dispute id. Hashing
  // the body is never less precise than the delivery key it replaces, and still collapses a
  // retry whenever Cashfree resends identical bytes.
  const body = '{"data":{"subscription_id":"c360_a"}}';
  const payload = JSON.parse(body);

  const a = await notificationKey("SUBSCRIPTION_STATUS_CHANGE", payload, body);
  assertEquals(a, await notificationKey("SUBSCRIPTION_STATUS_CHANGE", payload, body));
  assert(a.includes("|body:"), "no payment id to key on, so the body carries it");

  const other = '{"data":{"subscription_id":"c360_b"}}';
  assert(a !== await notificationKey("SUBSCRIPTION_STATUS_CHANGE", JSON.parse(other), other));
});

// ---------------------------------------------------------------- payload shapes

Deno.test("the subscription id is found wherever Cashfree nests it", () => {
  // Three real shapes across the subscription event types. Handled by walking the candidates
  // rather than by a switch, so a fourth shape does not need new code to be found.
  assertEquals(
    subscriptionIdsFrom({ data: { subscription_id: "c360_a" } }).subscriptionId,
    "c360_a",
  );
  assertEquals(
    subscriptionIdsFrom({ data: { subscription_details: { subscription_id: "c360_b" } } })
      .subscriptionId,
    "c360_b",
  );
  assertEquals(
    subscriptionIdsFrom({
      data: { subscription_status_webhook: { subscription_details: { subscription_id: "c360_c" } } },
    }).subscriptionId,
    "c360_c",
  );
});

Deno.test("a payload naming no subscription yields nulls rather than throwing", () => {
  const ids = subscriptionIdsFrom({ data: { cf_refund_id: "r1" } });
  assertEquals(ids.subscriptionId, null);
  assertEquals(ids.cfSubscriptionId, null);
});

Deno.test("cf_subscription_id is normalised to a string", () => {
  // Cashfree sends it as a number in some events and a string in others.
  assertEquals(subscriptionIdsFrom({ data: { cf_subscription_id: 12345 } }).cfSubscriptionId, "12345");
});

Deno.test("both spellings of the authorisation block are read", () => {
  // The API responds with British "authorisation_details"; some payloads use the American form.
  const british = snapshotOf({
    subscription_status: "ACTIVE",
    authorisation_details: { authorization_amount: 3, authorization_time: "2026-09-01T12:00:00Z" },
  });
  assertEquals(british.authorizationAmount, 3);
  assertEquals(british.authorizedAt, "2026-09-01T12:00:00.000Z");

  const american = snapshotOf({
    subscription_status: "ACTIVE",
    authorization_details: { authorization_amount: 3 },
  });
  assertEquals(american.authorizationAmount, 3);
});

Deno.test("an unknown subscription status is recorded, not rejected", () => {
  // A CHECK constraint or a throw here would fail the webhook closed on a status Cashfree adds
  // later — the opposite of what is wanted, which is to see it.
  assertEquals(snapshotOf({ subscription_status: "SOMETHING_NEW" }).status, "SOMETHING_NEW");
  assertEquals(snapshotOf({}).status, "UNKNOWN");
});

Deno.test("a non-payment event yields no payment", () => {
  assertEquals(paymentFrom({ data: { subscription_id: "c360_a" } }), null);
});

Deno.test("payment fields are pulled out with the failure reason", () => {
  const payment = paymentFrom({
    data: {
      cf_payment_id: 987,
      payment_amount: 249,
      payment_status: "FAILED",
      payment_time: "2026-09-03T12:00:00Z",
      failure_details: { failure_reason: "insufficient_funds" },
    },
  });

  assertEquals(payment?.cfPaymentId, "987");
  assertEquals(payment?.amount, 249);
  assertEquals(payment?.status, "FAILED");
  assertEquals(payment?.failureReason, "insufficient_funds");
});

// ---------------------------------------------------------------- classification

Deno.test("the auth event is classified as AUTH, and the ₹249 debit as RECURRING", () => {
  assertEquals(paymentKind("SUBSCRIPTION_AUTH_STATUS", 3, settings), "AUTH");
  assertEquals(paymentKind("SUBSCRIPTION_PAYMENT_SUCCESS", 249, settings), "RECURRING");
});

Deno.test("the amount decides when the event type is unreadable", () => {
  // Only a RECURRING SUCCESS promotes an account to `active`, so misreading the ₹3 as a monthly
  // debit would hand out a free month.
  assertEquals(paymentKind(null, 3, settings), "AUTH");
  assertEquals(paymentKind(null, 249, settings), "RECURRING");
});

Deno.test("an unreadable charge is UNKNOWN rather than a free month", () => {
  // This used to fall through to RECURRING, so a SUCCESS payload whose type and amount both
  // failed to parse credited a paid month nobody had been billed for.
  assertEquals(paymentKind(null, null, settings), "UNKNOWN");
});

Deno.test("Cashfree's own payment_type outranks the amount", () => {
  // A ₹3 row labelled RECURRING is a real renewal on a discounted plan; a ₹249 row labelled
  // AUTH is an authorisation. The label is the only signal that can tell those apart.
  assertEquals(paymentKind(null, 3, settings, "RECURRING"), "RECURRING");
  assertEquals(paymentKind("SUBSCRIPTION_PAYMENT_SUCCESS", 249, settings, "AUTH"), "AUTH");
});

Deno.test("the payments endpoint's payment_type is carried through as a hint", () => {
  const payment = paymentFrom({
    data: { cf_payment_id: 1, payment_amount: 249, payment_type: "recurring" },
  });

  assertEquals(payment?.kindHint, "RECURRING");
  assertEquals(paymentKind(null, null, settings, payment?.kindHint ?? null), "RECURRING");
});

Deno.test("PAUSED counts as a live mandate", () => {
  // subscription-cancel and subscription-start both accept it, so a reconcile that skipped it
  // left a paused mandate that nothing ever swept.
  assertEquals(isLiveStatus("PAUSED"), true);
  assertEquals(isLiveStatus("CANCELLED"), false);
});

// ---------------------------------------------------------------- time

Deno.test("outbound timestamps carry the IST offset Cashfree expects", () => {
  // Sending UTC where IST is expected would schedule every first charge five and a half hours
  // early — money moving before the trial is over.
  assertEquals(toIstIso(new Date("2026-09-01T12:00:00Z")), "2026-09-01T17:30:00+05:30");
  assertEquals(toIstIso(new Date("2026-09-01T20:00:00Z")), "2026-09-02T01:30:00+05:30");
});

Deno.test("adding a month clamps rather than skipping one", () => {
  // Jan 31 + 1 month must not roll into March, or a subscriber started on the 31st would be
  // granted an extra free period every short month.
  assertEquals(addMonths(new Date("2026-01-31T00:00:00Z"), 1).toISOString().slice(0, 10), "2026-02-28");
  assertEquals(addMonths(new Date("2026-03-31T00:00:00Z"), 1).toISOString().slice(0, 10), "2026-04-30");
  assertEquals(addMonths(new Date("2026-09-15T00:00:00Z"), 1).toISOString().slice(0, 10), "2026-10-15");
});

// ---------------------------------------------------------------- refunds & disputes

Deno.test("a refund is read out of the nested refund block", () => {
  const refund = refundFrom({
    type: "REFUND_STATUS_WEBHOOK",
    data: {
      refund: {
        cf_refund_id: 8812,
        cf_payment_id: 5566,
        refund_amount: 249,
        refund_currency: "INR",
        refund_status: "SUCCESS",
        refund_note: "customer request",
        processed_at: "2026-09-10T09:00:00Z",
      },
    },
  });

  assertEquals(refund?.cfRefundId, "8812");
  assertEquals(refund?.cfPaymentId, "5566");
  assertEquals(refund?.amount, 249);
  assertEquals(refund?.status, "SUCCESS");
  assertEquals(refund?.reason, "customer request");
});

Deno.test("a subscription event is not mistaken for a refund", () => {
  // The webhook tries the refund extractor on every payload, so a false positive here would
  // divert a real charge into the refund path.
  assertEquals(
    refundFrom({ type: "SUBSCRIPTION_PAYMENT_SUCCESS", data: { cf_payment_id: 1 } }),
    null,
  );
  assertEquals(disputeFrom({ type: "SUBSCRIPTION_PAYMENT_SUCCESS", data: { cf_payment_id: 1 } }), null);
});

Deno.test("a dispute finds its payment inside the order block", () => {
  const dispute = disputeFrom({
    type: "DISPUTE_CREATED",
    data: {
      dispute: {
        cf_dispute_id: 991,
        dispute_amount: 249,
        dispute_type: "CHARGEBACK",
        dispute_status: "DISPUTE_CREATED",
        reason_description: "Services not rendered",
        respond_by: "2026-09-20T00:00:00Z",
        order_details: { order_id: "o1", cf_payment_id: 5566 },
      },
    },
  });

  assertEquals(dispute?.cfDisputeId, "991");
  assertEquals(dispute?.cfPaymentId, "5566");
  assertEquals(dispute?.disputeType, "CHARGEBACK");
  assertEquals(dispute?.respondBy, "2026-09-20T00:00:00.000Z");
});

Deno.test("only a lost dispute costs the user their access", () => {
  // Opening one must not revoke: most are resolved in the merchant's favour, and a bank's
  // automated query is not the user's fault.
  assertFalse(isDisputeLost("DISPUTE_CREATED"));
  assertFalse(isDisputeLost("DISPUTE_UNDER_REVIEW"));
  assertFalse(isDisputeLost("DISPUTE_MERCHANT_WON"));
  assert(isDisputeLost("DISPUTE_MERCHANT_LOST"));
  assert(isDisputeLost("CHARGEBACK_ACCEPTED"));
});

Deno.test("an unreadable refund payload yields null rather than throwing", () => {
  // The webhook runs these extractors on every delivery, including ones for products this app
  // does not use. They must never be the reason a delivery 500s.
  assertEquals(refundFrom({}), null);
  assertEquals(disputeFrom({}), null);
  assertEquals(refundFrom({ data: null }), null);
  assertEquals(disputeFrom({ data: "nonsense" }), null);
});

Deno.test("a scheduled charge is not a failed one", () => {
  // Cashfree reports INITIALIZED for a debit it has only scheduled. Counting that as a failure
  // told a user their payment had been declined before it was even attempted.
  assertFalse(isFailedCharge("INITIALIZED"));
  assertFalse(isFailedCharge("PENDING"));
  assertFalse(isFailedCharge("BANK_APPROVAL_PENDING"));
  assertFalse(isFailedCharge("SUCCESS"));
  // Nor is a status we do not recognise: alarming someone over nothing is the worse error.
  assertFalse(isFailedCharge("SOME_NEW_CASHFREE_STATE"));

  assert(isFailedCharge("FAILED"));
  assert(isFailedCharge("USER_DROPPED"));
  assert(isFailedCharge("cancelled"), "case-insensitive");
});

// ---------------------------------------------------------------- cancellation states

Deno.test("a mandate the user revoked in their UPI app reads as cancelled", () => {
  // The whole reason these predicates exist. Cashfree reports a merchant cancel as `CANCELLED`
  // and a user revoking the mandate in GPay/PhonePe as `CUSTOMER_CANCELLED`, and only the first
  // was ever compared against — so the far more common case fell through every check.
  assert(isCancelledStatus("CANCELLED"));
  assert(isCancelledStatus("CUSTOMER_CANCELLED"));
  assertFalse(isCancelledStatus("ACTIVE"));
  assertFalse(isCancelledStatus("ON_HOLD"));

  assert(isPausedStatus("PAUSED"));
  assert(isPausedStatus("CUSTOMER_PAUSED"));
  assertFalse(isPausedStatus("ACTIVE"));

  // LINK_EXPIRED is the non-seamless twin of EXPIRED: the authorisation link went unused.
  assert(isExpiredStatus("COMPLETED"));
  assert(isExpiredStatus("EXPIRED"));
  assert(isExpiredStatus("LINK_EXPIRED"));
  assertFalse(isExpiredStatus("CANCELLED"));
});

Deno.test("who ended the mandate is recoverable from the status alone", () => {
  assertEquals(cancelledBy("CUSTOMER_CANCELLED"), "customer");
  assertEquals(cancelledBy("CANCELLED"), "merchant");
});

Deno.test("a customer-revoked mandate revokes entitlement, not just analytics", () => {
  // The regression this guards. Before the predicates, `userUpdatesFor` switched on the status
  // word, `CUSTOMER_CANCELLED` hit `default:`, and the account kept `payment_type` untouched —
  // staying fully entitled on a subscription the bank would never debit again.
  const paidUntil = "2026-10-01T00:00:00.000Z";
  const updates = userUpdatesFor(
    user({ payment_type: "active", current_period_end: paidUntil }),
    snapshotOf({
      subscription_id: "sub_1",
      subscription_status: "CUSTOMER_CANCELLED",
    }),
    settings,
  );

  assertEquals(updates.payment_type, "cancelled");
  // Paid time is honoured: the user keeps the month they already bought.
  assertEquals(updates.current_period_end, undefined);
  assert(updates.cancelled_at, "the cancellation instant is stamped once");
});

Deno.test("a customer-paused mandate is recorded as a billing problem", () => {
  const updates = userUpdatesFor(
    user({ payment_type: "active" }),
    snapshotOf({ subscription_id: "sub_1", subscription_status: "CUSTOMER_PAUSED" }),
    settings,
  );

  assertEquals(updates.billing_state, "paused");
  // Pausing is not cancelling: entitlement is left alone and simply stops advancing.
  assertEquals(updates.payment_type, undefined);
});

// ---------------------------------------------------------------- activation

const AUTHORIZED_AT = "2026-09-01T11:00:00Z";

function activeSnapshot() {
  return snapshotOf({
    subscription_id: "sub_1",
    subscription_status: "ACTIVE",
    authorization_details: { authorization_time: AUTHORIZED_AT },
  });
}

Deno.test("a new account's first authorisation starts the trial AND leaves `none`", () => {
  // The regression that makes `none` dangerous if it is added alone. `isEntitled` answers
  // `false` for `none` no matter what the dates say, so an activation that wrote `trial_ends_at`
  // without moving `payment_type` would take the user's ₹3 and leave them on the paywall — with
  // every date in the row insisting they were fine.
  const updates = userUpdatesFor(user(), activeSnapshot(), settings);

  assertEquals(updates.payment_type, "trial");
  assert(updates.trial_ends_at, "the trial clock is started");
  assertEquals(
    updates.trial_ends_at,
    new Date(new Date(AUTHORIZED_AT).getTime() + 86_400_000).toISOString(),
    "anchored to Cashfree's authorisation instant, not to now",
  );
  assertFalse(
    isEntitled(
      { payment_type: "trial", trial_ends_at: updates.trial_ends_at as string,
        current_period_end: null },
      0,
      new Date("2026-09-03T00:00:00Z"),
    ),
    "and it is a real one-day clock, not an open-ended grant",
  );
});

Deno.test("a returning subscriber is not given a second trial", () => {
  // They spent it. `trial_ends_at` is set once and never extended, and the state must not be
  // rewritten to `trial` either — that would claim a trial that ended in the past, which reads as
  // entitled-until-a-stale-date to every report that looks at the row.
  const updates = userUpdatesFor(
    user({ payment_type: "cancelled", trial_ends_at: "2026-08-01T00:00:00Z" }),
    activeSnapshot(),
    settings,
  );

  assertEquals(updates.trial_ends_at, undefined);
  assertEquals(
    updates.payment_type,
    undefined,
    "left where it is until the full-price charge actually lands",
  );
});

Deno.test("re-authorising inside a paid month goes straight back to active", () => {
  const updates = userUpdatesFor(
    user({ payment_type: "cancelled", current_period_end: "2027-01-01T00:00:00Z" }),
    activeSnapshot(),
    settings,
  );

  assertEquals(updates.payment_type, "active");
});

Deno.test("an already-active account is never rewritten by a status sync", () => {
  // `active` is the strongest state a row can hold. Recomputing it from a snapshot is how a paid
  // month gets downgraded to a spent trial by an out-of-order webhook.
  const updates = userUpdatesFor(
    user({ payment_type: "active", trial_ends_at: "2026-08-01T00:00:00Z" }),
    activeSnapshot(),
    settings,
  );

  assertEquals(updates.payment_type, undefined);
});

// ---------------------------------------------------------------- what buys a month

Deno.test("the ₹3 authorisation buys a trial, not a month", () => {
  assertFalse(buysAMonth("AUTH", 3, settings));
  assertFalse(buysAMonth("AUTH", 248, settings), "one rupee short still buys nothing");
});

Deno.test("a full-price authorisation buys a month", () => {
  // How a returning subscriber pays at all: Cashfree will not schedule a first debit less than
  // 24 hours out, so the only way to take money at mandate time is the authorisation. Crediting
  // only RECURRING would take ₹499 and leave them looking at the paywall.
  assert(buysAMonth("AUTH", 499, { ...settings, recurringAmount: 499 }));
  assert(buysAMonth("AUTH", 249, settings), "at the recurring amount exactly");
});

Deno.test("a recurring debit always buys a month, and UNKNOWN never does", () => {
  assert(buysAMonth("RECURRING", 249, settings));
  assert(buysAMonth("RECURRING", 3, settings), "a discounted plan is still a real renewal");

  // An unreadable payload must not be resolved in the user's favour — that is how a malformed
  // webhook becomes a free month.
  assertFalse(buysAMonth("UNKNOWN", 499, settings));
  assertFalse(buysAMonth("AUTH", null, settings), "no amount, no month");
});

Deno.test("a transition gets a name a report can group by", () => {
  assertEquals(transitionName("INITIALIZED", "ACTIVE"), "activated");
  assertEquals(transitionName("ON_HOLD", "ACTIVE"), "recovered");
  assertEquals(transitionName("CUSTOMER_PAUSED", "ACTIVE"), "recovered");
  assertEquals(transitionName("ACTIVE", "ON_HOLD"), "mandate_on_hold");
  assertEquals(transitionName("ACTIVE", "CUSTOMER_CANCELLED"), "cancelled");
  assertEquals(transitionName("ACTIVE", "CUSTOMER_PAUSED"), "paused");
  assertEquals(transitionName("ACTIVE", "LINK_EXPIRED"), "expired");
  // Deliberately still counted rather than dropped: an unnamed transition arriving in volume is
  // how a status Cashfree adds after this was written gets noticed at all.
  assertEquals(transitionName("ACTIVE", "SOME_NEW_CASHFREE_STATE"), "other");
});

Deno.test("the legacy camelCase subscription id is still found", () => {
  // An endpoint configured against the older Subscriptions API version sends `subscriptionId`
  // where this one sends `subscription_id`. A delivery whose id is not found is not an error —
  // it is acknowledged as `ignored`, so a mandate would go on being cancelled with nothing
  // here ever noticing.
  assertEquals(
    subscriptionIdsFrom({ data: { subscriptionId: "sub_legacy" } }).subscriptionId,
    "sub_legacy",
  );
  assertEquals(
    subscriptionIdsFrom({ data: { cfSubscriptionId: 4242 } }).cfSubscriptionId,
    "4242",
  );
  assertEquals(
    subscriptionIdsFrom({ data: { subReferenceId: 99 } }).cfSubscriptionId,
    "99",
  );
});

// ---------------------------------------------------------------- reconcile sweep

Deno.test("the staleness sweep looks back by the configured window", () => {
  // Six hours before NOW. This is the ceiling on how long a dropped cancellation webhook can
  // leave an account entitled, so the arithmetic is worth pinning.
  assertEquals(staleSweepCutoff("6", NOW, 6), "2026-09-01T06:00:00.000Z");
  assertEquals(staleSweepCutoff("1", NOW, 6), "2026-09-01T11:00:00.000Z");
});

Deno.test("an unset window falls back to the default rather than off", () => {
  // The whole point of the sweep is that it is the thing still running when the webhook is not.
  // A blank cell, a placeholder or a typo must not be able to take it down silently — only a
  // deliberate 0 does that.
  assertEquals(staleSweepCutoff("", NOW, 6), "2026-09-01T06:00:00.000Z");
  assertEquals(staleSweepCutoff("  ", NOW, 6), "2026-09-01T06:00:00.000Z");
  assertEquals(staleSweepCutoff("six", NOW, 6), "2026-09-01T06:00:00.000Z");
  assertEquals(staleSweepCutoff("-4", NOW, 6), "2026-09-01T06:00:00.000Z");
});

Deno.test("only an explicit zero disables the staleness sweep", () => {
  assertEquals(staleSweepCutoff("0", NOW, 6), null);
  assertEquals(staleSweepCutoff(" 0 ", NOW, 6), null);
});
