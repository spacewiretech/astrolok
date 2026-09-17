import { assertEquals } from "jsr:@std/assert@1";

import { CANCEL_REASONS, parseCancellationFeedback } from "../_shared/cancellation_feedback.ts";

const NOTIFICATION = "8a1f5c2e-1234-4abc-9def-001122334455";

Deno.test("every listed reason is accepted, with its comment and source", () => {
  for (const reason of CANCEL_REASONS) {
    const parsed = parseCancellationFeedback({ reason, comment: "  Too costly  for me ", source: "push", notification_id: NOTIFICATION });
    assertEquals(parsed?.reason, reason);
    assertEquals(parsed?.notificationId, NOTIFICATION);
    assertEquals(parsed?.comment, reason === "dismissed" ? null : "Too costly for me");
  }
});

Deno.test("no reason, or an unknown one, is not an answer", () => {
  assertEquals(parseCancellationFeedback({}), null);
  assertEquals(parseCancellationFeedback({ reason: "bored" }), null);
  assertEquals(parseCancellationFeedback(null), null);
  assertEquals(parseCancellationFeedback([{ reason: "other" }]), null);
});

Deno.test("a malformed extra costs the extra, never the answer", () => {
  const parsed = parseCancellationFeedback({ reason: "other", comment: 42, source: "carrier pigeon", notification_id: "nope" });
  assertEquals(parsed, { reason: "other", comment: null, source: "push", notificationId: null });
  assertEquals(parseCancellationFeedback({ reason: "not_useful", source: "in_app" })?.source, "in_app");
});
