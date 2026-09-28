/**
 * When to retry a debit that failed for insufficient funds.
 *
 * Cashfree makes one attempt per billing cycle on our UPI mandates and never retries on its own,
 * so a user whose ₹499/₹299 bounced for want of balance waited a month for the next debit — locked
 * out the whole time. The schedule counts from the IST day the charge failed:
 *
 *   attempt 1  failure day + 2   (48 h)
 *   attempt 2  failure day + 4   (~92 h)
 *   attempt 3  the next 5th after attempt 2
 *
 * Any attempt that would land on or after the mandate's regular monthly charge is skipped: that
 * charge is the next attempt anyway, and Cashfree allows 3 retries per billing cycle.
 *
 * Dates only, as `YYYY-MM-DD` in IST. Cashfree's retry reads only the date, and doing the
 * arithmetic on date strings keeps a stray timezone from moving a debit by a day.
 *
 * Pure: no database, no network. `payment-retry` does the I/O.
 */

import { AppConfig, configSetting } from "./config.ts";

export interface RetryPolicy {
  /** Days after the failure day for the first retries, in order. */
  offsetsDays: number[];
  /** Day of the month for the last retry. */
  dayOfMonth: number;
  /** A retry is never scheduled sooner than this many days after today. */
  minLeadDays: number;
}

export const DEFAULT_POLICY: RetryPolicy = { offsetsDays: [2, 4], dayOfMonth: 5, minLeadDays: 1 };

/** Cashfree allows 3 retries per billing cycle, and `payment_retries.attempt` is checked to match. */
export const MAX_ATTEMPTS = 3;

export type SkipReason = "after_regular_charge" | "exhausted";

export type RetryPlan =
  | { attempt: number; date: string }
  | { attempt: number; skip: SkipReason };

/**
 * The policy from app_config, falling back per field to [DEFAULT_POLICY] rather than failing.
 *
 * A malformed offsets list, or one long enough to need a fourth attempt, falls back whole: half a
 * schedule is worse than the documented one.
 */
export function retryPolicy(config: AppConfig): RetryPolicy {
  const offsets = configSetting(config, "cashfree_retry_offsets_days")
    .split(",")
    .map((part) => Number(part.trim()))
    .filter((n) => Number.isInteger(n) && n > 0);
  const offsetsValid = offsets.length >= 1 && offsets.length < MAX_ATTEMPTS &&
    offsets.every((n, i) => i === 0 || n > offsets[i - 1]);

  const day = Number(configSetting(config, "cashfree_retry_day_of_month"));
  const lead = Number(configSetting(config, "cashfree_retry_min_lead_days"));

  return {
    offsetsDays: offsetsValid ? offsets : DEFAULT_POLICY.offsetsDays,
    // 1–28 so every month has the day.
    dayOfMonth: Number.isInteger(day) && day >= 1 && day <= 28 ? day : DEFAULT_POLICY.dayOfMonth,
    minLeadDays: Number.isInteger(lead) && lead >= 1 ? lead : DEFAULT_POLICY.minLeadDays,
  };
}

/** The IST calendar date of [instant], as `YYYY-MM-DD`. */
export function istDate(instant: Date): string {
  return new Date(instant.getTime() + 5.5 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

/** [date] plus [days] calendar days. */
export function addDaysToDate(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/** The first date on or after [date] whose day of the month is [day]. */
export function onOrAfterDayOfMonth(date: string, day: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  if (d.getUTCDate() > day) d.setUTCMonth(d.getUTCMonth() + 1, day);
  else d.setUTCDate(day);
  return d.toISOString().slice(0, 10);
}

function later(a: string, b: string): string {
  return a >= b ? a : b;
}

/**
 * The date for [attempt] of a chain counted from [baseDate].
 *
 * [today] only ever moves a date later: a result that arrived late, or a backlog started from a
 * past day, is retried as soon as the lead allows rather than on a day already gone.
 * [regularNext] is the mandate's regular next debit, when known.
 */
export function planRetry(
  attempt: number,
  baseDate: string,
  today: string,
  regularNext: string | null,
  policy: RetryPolicy = DEFAULT_POLICY,
): RetryPlan {
  const { offsetsDays, dayOfMonth, minLeadDays } = policy;
  const earliest = addDaysToDate(today, minLeadDays);

  let date: string;
  if (attempt >= 1 && attempt <= offsetsDays.length) {
    date = later(addDaysToDate(baseDate, offsetsDays[attempt - 1]), earliest);
  } else if (attempt === offsetsDays.length + 1 && attempt <= MAX_ATTEMPTS) {
    // Strictly after the last offset day, so the 5th is never the same day as attempt 2.
    const afterLast = addDaysToDate(baseDate, offsetsDays[offsetsDays.length - 1] + 1);
    date = onOrAfterDayOfMonth(later(afterLast, earliest), dayOfMonth);
  } else {
    return { attempt, skip: "exhausted" };
  }

  // A regular date that is not after today is a stale row, not a charge still to come.
  if (regularNext && regularNext > today && date >= regularNext) {
    return { attempt, skip: "after_regular_charge" };
  }
  return { attempt, date };
}

/** Whether a failure reason is the one this retries. Revoked or paused mandates cannot be debited. */
export function isInsufficientFunds(reason: string | null | undefined): boolean {
  return /insufficient/i.test(reason ?? "");
}
