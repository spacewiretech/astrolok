/**
 * Tests for the retry schedule of debits that failed for insufficient funds. Run with:
 *
 *   deno test supabase/functions/tests/payment_retry_test.ts
 */

import { assertEquals } from "jsr:@std/assert@1";

import {
  DEFAULT_POLICY,
  isInsufficientFunds,
  istDate,
  onOrAfterDayOfMonth,
  planRetry,
  retryPolicy,
} from "../_shared/payment_retry.ts";

function chain(base: string, today: string, regular: string | null) {
  return [1, 2, 3].map((attempt) => planRetry(attempt, base, today, regular));
}

Deno.test("a new failure retries at 48 h, ~92 h, then the next 5th", () => {
  assertEquals(chain("2026-09-20", "2026-09-20", "2026-10-20"), [
    { attempt: 1, date: "2026-09-22" },
    { attempt: 2, date: "2026-09-24" },
    { attempt: 3, date: "2026-10-05" },
  ]);
});

Deno.test("the backlog, started from yesterday, retries tomorrow, 48 h later, then 5 Oct", () => {
  assertEquals(chain("2026-09-27", "2026-09-28", "2026-10-15"), [
    { attempt: 1, date: "2026-09-29" },
    { attempt: 2, date: "2026-10-01" },
    { attempt: 3, date: "2026-10-05" },
  ]);
});

Deno.test("the 5th is skipped when it would land after the regular monthly charge", () => {
  assertEquals(chain("2026-10-02", "2026-10-02", "2026-11-02"), [
    { attempt: 1, date: "2026-10-04" },
    { attempt: 2, date: "2026-10-06" },
    { attempt: 3, skip: "after_regular_charge" },
  ]);
});

Deno.test("the 5th is never the same day as attempt 2", () => {
  // Failed on 1 Oct: attempt 2 is on 5 Oct, so the last retry would be 5 Nov, after the 1 Nov charge.
  assertEquals(planRetry(2, "2026-10-01", "2026-10-01", "2026-11-01"), { attempt: 2, date: "2026-10-05" });
  assertEquals(planRetry(3, "2026-10-01", "2026-10-01", "2026-11-01"), {
    attempt: 3,
    skip: "after_regular_charge",
  });
});

Deno.test("a retry on the regular charge day itself is skipped", () => {
  assertEquals(planRetry(1, "2026-09-20", "2026-09-20", "2026-09-22"), {
    attempt: 1,
    skip: "after_regular_charge",
  });
});

Deno.test("a result that arrived late is retried tomorrow, not on a day already gone", () => {
  assertEquals(planRetry(2, "2026-09-20", "2026-09-25", "2026-10-20"), { attempt: 2, date: "2026-09-26" });
});

Deno.test("a regular charge date already in the past is stale and skips nothing", () => {
  assertEquals(planRetry(1, "2026-09-27", "2026-09-28", "2026-09-18"), { attempt: 1, date: "2026-09-29" });
});

Deno.test("there is no fourth attempt", () => {
  assertEquals(planRetry(4, "2026-09-20", "2026-09-20", null), { attempt: 4, skip: "exhausted" });
  assertEquals(planRetry(0, "2026-09-20", "2026-09-20", null), { attempt: 0, skip: "exhausted" });
});

Deno.test("the schedule crosses a year end", () => {
  assertEquals(chain("2026-12-28", "2026-12-28", "2027-01-28"), [
    { attempt: 1, date: "2026-12-30" },
    { attempt: 2, date: "2027-01-01" },
    { attempt: 3, date: "2027-01-05" },
  ]);
});

Deno.test("with no regular charge date known, the 5th is still used", () => {
  assertEquals(planRetry(3, "2026-09-20", "2026-09-24", null), { attempt: 3, date: "2026-10-05" });
});

Deno.test("onOrAfterDayOfMonth rolls into the next month only when the day has passed", () => {
  assertEquals(onOrAfterDayOfMonth("2026-10-02", 5), "2026-10-05");
  assertEquals(onOrAfterDayOfMonth("2026-10-05", 5), "2026-10-05");
  assertEquals(onOrAfterDayOfMonth("2026-10-06", 5), "2026-11-05");
  assertEquals(onOrAfterDayOfMonth("2026-01-31", 5), "2026-02-05");
  assertEquals(onOrAfterDayOfMonth("2026-12-20", 5), "2027-01-05");
});

Deno.test("istDate is the IST calendar day", () => {
  assertEquals(istDate(new Date("2026-09-27T18:29:59Z")), "2026-09-27");
  assertEquals(istDate(new Date("2026-09-27T18:30:00Z")), "2026-09-28");
});

Deno.test("retryPolicy reads app_config and falls back whole on a bad schedule", () => {
  assertEquals(retryPolicy(new Map()), DEFAULT_POLICY);
  assertEquals(
    retryPolicy(new Map([
      ["cashfree_retry_offsets_days", "1, 3"],
      ["cashfree_retry_day_of_month", "7"],
      ["cashfree_retry_min_lead_days", "2"],
    ])),
    { offsetsDays: [1, 3], dayOfMonth: 7, minLeadDays: 2 },
  );
  // Out of order, or long enough to need a fourth attempt.
  assertEquals(retryPolicy(new Map([["cashfree_retry_offsets_days", "4,2"]])).offsetsDays, [2, 4]);
  assertEquals(retryPolicy(new Map([["cashfree_retry_offsets_days", "1,2,3"]])).offsetsDays, [2, 4]);
  // A day some months do not have.
  assertEquals(retryPolicy(new Map([["cashfree_retry_day_of_month", "31"]])).dayOfMonth, 5);
});

Deno.test("only insufficient funds is retried", () => {
  assertEquals(isInsufficientFunds("DEBIT HAS BEEN FAILED|INSUFFICIENT FUNDS IN CUSTOMER (REMITTER) ACCOUN"), true);
  assertEquals(isInsufficientFunds("DEBIT FAILED | Insufficient Funds In Customer (Remitter) Account"), true);
  assertEquals(isInsufficientFunds("Mandate Has Been Revoked"), false);
  assertEquals(isInsufficientFunds("subscription is not active"), false);
  assertEquals(isInsufficientFunds(null), false);
});
