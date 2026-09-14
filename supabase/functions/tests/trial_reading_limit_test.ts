import { assert, assertEquals } from "jsr:@std/assert@1";

import { isInTrial, UserRow } from "../_shared/entitlement.ts";
import {
  countedReadingsFilter,
  PENDING_HOLD_MS,
  TRIAL_LIMIT_KEYS,
  trialLimitMessage,
  trialReadingLimitFrom,
} from "../_shared/trial_reading_limit.ts";

/**
 * The trial allowance: one palm reading and one face reading per trial.
 *
 * The count itself is a query against a live table. Everything that decides what that query means
 * — who is limited, how far, and which rows count — is pure, and is tested here.
 */

const now = new Date("2026-09-14T10:00:00Z");

function user(over: Partial<UserRow> = {}): UserRow {
  return {
    user_id: "u1",
    mobile_no: "9931145610",
    name: "Asha",
    dob: null,
    payment_type: "trial",
    trial_started_at: "2026-09-14T09:00:00Z",
    trial_ends_at: "2026-09-15T09:00:00Z",
    current_period_end: null,
    active_subscription_id: null,
    ...over,
  };
}

Deno.test("the allowance is one reading when no row is configured", () => {
  assertEquals(trialReadingLimitFrom(new Map(), TRIAL_LIMIT_KEYS.palm_readings), 1);
});

Deno.test("a configured allowance is honoured, per feature", () => {
  const config = new Map([["trial_palm_readings", "3"], ["trial_face_readings", "2"]]);

  assertEquals(trialReadingLimitFrom(config, TRIAL_LIMIT_KEYS.palm_readings), 3);
  assertEquals(trialReadingLimitFrom(config, TRIAL_LIMIT_KEYS.face_readings), 2);
});

Deno.test("a nonsensical allowance falls back to one rather than opening or closing the gate", () => {
  // Zero would lock every trial user out of a reading they were sold; a placeholder would read as
  // zero without the fallback.
  for (const value of ["0", "-3", "abc", "-", "", "0.5"]) {
    const config = new Map([["trial_face_readings", value]]);
    assertEquals(trialReadingLimitFrom(config, TRIAL_LIMIT_KEYS.face_readings), 1, value);
  }
});

Deno.test("a fractional allowance rounds down", () => {
  const config = new Map([["trial_palm_readings", "2.7"]]);
  assertEquals(trialReadingLimitFrom(config, TRIAL_LIMIT_KEYS.palm_readings), 2);
});

Deno.test("only a live trial is limited", () => {
  assert(isInTrial(user(), 2, now));

  // Paying and cancelled-but-paid-up accounts keep only the daily quota.
  assert(!isInTrial(user({ payment_type: "active", current_period_end: "2026-10-14T10:00:00Z" }), 2, now));
  assert(!isInTrial(user({ payment_type: "cancelled", current_period_end: "2026-10-14T10:00:00Z" }), 2, now));

  // A lapsed trial is refused by the entitlement check before the allowance is ever consulted.
  assert(!isInTrial(user({ trial_ends_at: "2026-09-13T10:00:00Z" }), 2, now));
});

Deno.test("ready readings always count, pending ones only while they could be in flight", () => {
  const filter = countedReadingsFilter(now);
  const cutoff = new Date(now.getTime() - PENDING_HOLD_MS).toISOString();

  assert(filter.startsWith("status.eq.ready,"));
  assert(filter.includes(`and(status.eq.pending,created_at.gte."${cutoff}")`));

  // A rejected photo or a model outage must never spend the user's one reading.
  assert(!filter.includes("rejected"));
  assert(!filter.includes("failed"));
});

Deno.test("the refusal says once for one, and the number otherwise", () => {
  assertEquals(
    trialLimitMessage("palm", 1),
    "Trial users can scan their palm only once. " +
      "Please wait for your trial period to finish to scan again.",
  );
  assert(trialLimitMessage("face", 2).includes("scan their face only 2 times"));
});
