/**
 * Why someone ended their subscription: the pure half of `cancellation-feedback`.
 *
 * Asked by the `mid_cancel` push, minutes after the mandate is cancelled. Before this the reason was
 * null on every one of the 525 trial cancellations on record — the cancel happens in the user's UPI
 * app, where we have no say in the flow.
 */

import { normaliseFeedbackComment } from "./chat_feedback.ts";

/** Matches the CHECK on `cancellation_feedback.reason` and the options the app lists. */
export const CANCEL_REASONS = [
  "too_expensive",
  "not_accurate",
  "not_useful",
  "only_exploring",
  "payment_trouble",
  "technical_issue",
  "found_alternative",
  "other",
  "dismissed",
] as const;
export type CancelReason = typeof CANCEL_REASONS[number];

export interface CancellationFeedback {
  reason: CancelReason;
  comment: string | null;
  source: "push" | "in_app";
  notificationId: string | null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * A feedback submission out of an untrusted body, or null. Only the reason is required; a malformed
 * comment or notification id costs the user their comment, never their answer.
 */
export function parseCancellationFeedback(body: unknown): CancellationFeedback | null {
  if (typeof body !== "object" || body === null || Array.isArray(body)) return null;
  const b = body as Record<string, unknown>;

  if (!(CANCEL_REASONS as readonly unknown[]).includes(b.reason)) return null;
  const reason = b.reason as CancelReason;

  return {
    reason,
    // A dismissal has nothing to say, whatever the body carried.
    comment: reason === "dismissed" ? null : normaliseFeedbackComment(b.comment),
    source: b.source === "in_app" ? "in_app" : "push",
    notificationId: typeof b.notification_id === "string" && UUID.test(b.notification_id) ? b.notification_id : null,
  };
}
