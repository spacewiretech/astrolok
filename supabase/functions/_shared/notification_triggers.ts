/**
 * The two pushes that cannot wait for the five-minute dispatcher, raised from the subscription sync
 * the moment Cashfree tells us.
 *
 *  - `mid_cancel`: the user just cancelled their mandate. The average trial cancellation happens 1.7
 *    hours in, and the reason is null on every one of them on record, so the ask has to land while
 *    they are still holding the phone.
 *  - `billing_issue`: an autopay debit failed, or the mandate went on hold. Access usually still has
 *    days to run, which is exactly the window a nudge can save.
 *
 * The decisions are pure and tested. The hooks never throw and never delay the caller: they hand the
 * send to `notifyNow`, which runs after the response. The webhook, the hourly reconcile and the
 * app's status poll can all observe the same transition; the dedupe key makes that one push.
 */

import { SupabaseClient } from "jsr:@supabase/supabase-js@2";

import { isCancelledStatus } from "./cashfree.ts";
import { istDate } from "./notification_campaigns.ts";
import { notificationConfig, notificationFunctionName, notificationSettings, notifyNow } from "./notify.ts";

export interface TransitionFacts {
  fromStatus: string;
  toStatus: string;
  /** The Edge Function observing it: `cashfree-webhook`, `subscription-reconcile`, … */
  functionName: string;
  /** When the subscription row was last written before this sync — the last time it was seen live. */
  previousCheckedAt: string | null | undefined;
  now: Date;
  maxAgeMinutes: number;
}

/**
 * Whether a transition is a user's own cancellation, fresh enough to ask about.
 *
 * `CUSTOMER_CANCELLED` is a cancel from the UPI app. Plain `CANCELLED` is a cancel made through
 * Cashfree's API — by our own in-app endpoint (asked about), or by our housekeeping for a duplicate or
 * stale mandate (never asked about: the user did not choose to leave). The reconcile sweep can find a
 * cancellation hours after it happened; it asks only when the mandate was last seen live recently.
 */
export function midCancelDecision(facts: TransitionFacts): boolean {
  if (!isCancelledStatus(facts.toStatus) || isCancelledStatus(facts.fromStatus)) return false;

  const byUser = facts.toStatus === "CUSTOMER_CANCELLED" || facts.functionName === "subscription-cancel";
  if (!byUser) return false;

  if (facts.functionName === "subscription-reconcile") {
    const seen = facts.previousCheckedAt ? Date.parse(facts.previousCheckedAt) : NaN;
    if (!Number.isFinite(seen)) return false;
    return facts.now.getTime() - seen <= facts.maxAgeMinutes * 60_000;
  }
  return true;
}

/** A mandate that has just gone on hold. */
export function onHoldDecision(fromStatus: string, toStatus: string): boolean {
  return toStatus === "ON_HOLD" && fromStatus !== "ON_HOLD";
}

/**
 * A recurring debit that has just been seen failing — not a redelivery of a failure already known.
 * [failed] is `isFailedCharge(status)`, passed in by `recordPayment` rather than imported here, so this
 * module and the sync do not import each other.
 */
export function billingIssueDecision(
  { kind, status, failed, priorStatus }: {
    kind: string;
    status: string;
    failed: boolean;
    priorStatus: string | null | undefined;
  },
): boolean {
  return kind === "RECURRING" && failed && priorStatus !== status;
}

export async function onSubscriptionTransition(
  db: SupabaseClient,
  facts: { userId: string; subscriptionId: string; fromStatus: string; toStatus: string; previousCheckedAt?: string | null },
): Promise<void> {
  try {
    const config = notificationConfig();
    if (!config) return;
    const now = new Date();

    if (midCancelDecision({
      fromStatus: facts.fromStatus,
      toStatus: facts.toStatus,
      functionName: notificationFunctionName(),
      previousCheckedAt: facts.previousCheckedAt,
      now,
      maxAgeMinutes: notificationSettings(config).midCancelMaxAgeMinutes,
    })) {
      await notifyNow(db, {
        userId: facts.userId,
        campaign: "mid_cancel",
        dedupeKey: `mid_cancel:${facts.subscriptionId}`,
        params: { subscription_id: facts.subscriptionId },
        expiresAt: new Date(now.getTime() + 6 * 3600_000),
      });
    }

    if (onHoldDecision(facts.fromStatus, facts.toStatus)) {
      await notifyNow(db, {
        userId: facts.userId,
        campaign: "billing_issue",
        dedupeKey: `billing_issue:${facts.subscriptionId}:${istDate(now)}`,
        params: { subscription_id: facts.subscriptionId, cause: "on_hold" },
        expiresAt: new Date(now.getTime() + 2 * 86_400_000),
      });
    }
  } catch (error) {
    console.error("notification trigger (transition) failed", error);
  }
}

export async function onChargeRecorded(
  db: SupabaseClient,
  facts: { userId: string; subscriptionId: string; kind: string; status: string; failed: boolean; priorStatus?: string | null },
): Promise<void> {
  try {
    if (!notificationConfig()) return;
    if (!billingIssueDecision({ ...facts, priorStatus: facts.priorStatus ?? null })) return;
    const now = new Date();
    await notifyNow(db, {
      userId: facts.userId,
      campaign: "billing_issue",
      dedupeKey: `billing_issue:${facts.subscriptionId}:${istDate(now)}`,
      params: { subscription_id: facts.subscriptionId, cause: "charge_failed" },
      expiresAt: new Date(now.getTime() + 2 * 86_400_000),
    });
  } catch (error) {
    console.error("notification trigger (charge) failed", error);
  }
}
