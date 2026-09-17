# lib/features/cancellation

## Purpose

"Why are you leaving?" — asked by the `mid_cancel` push minutes after a mandate is cancelled in a
UPI app. Before this, the reason was null on every trial cancellation on record.

## Files

- `cancellation_reason_viewmodel.dart` — Declares: `cancellationReasons` (keys match the server's
  `CANCEL_REASONS`), `CancellationReasonState`, `CancellationReasonViewModel` keyed by the push's
  notification id.
- `cancellation_reason_view.dart` — the reasons, an optional comment, Send or Skip, then a thank-you
  with a way back. Declares: `CancellationReasonView`.

## Notes

- **Ungated** in `router.dart`, like `/payment-status`. A trial user who cancels loses access that
  same minute; behind `EntitlementGate` this screen would bounce exactly the person it asks.
- `cancellation-feedback` resolves the subscription server-side and keeps one answer per mandate;
  a second answer returns `recorded: false`, which the screen treats as success.
- Skip records `dismissed`, so "asked and declined" is distinguishable from "never asked".
- The comment is stored in `cancellation_feedback.comment`; Mixpanel only gets `has_comment`.
