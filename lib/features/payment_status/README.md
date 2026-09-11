# lib/features/payment_status

## Purpose

Where the user lands after checkout, whichever way it went.

## Files

- `payment_outcome.dart` — Declares: `PaymentOutcome` (three-valued, with a `.slug` used in the
  route). This is the state file under a different name.
- `payment_status_view.dart` — Declares: `PaymentStatusView`. There is no viewmodel.

## Notes

- **Three outcomes, not two.** `pending` exists so a real payment whose webhook is late is
  never reported to the user as a failure.
- Routed as `/payment-status/:outcome` and **deliberately ungated** — wrapping it in
  `EntitlementGate` would bounce a just-paid user back to the paywall while the mandate is still
  settling, which is the exact moment the screen exists for.
- **Only the `pending` case polls** (12 attempts, 5s apart) — slower and longer than the
  paywall's poll, because by the time the user is here the fast path has been tried and what is
  left is waiting on a webhook. `success` and `failed` are presented as they arrive.
- `paymentStatusViewed` records the verdict the user was *shown*, which is not always the one
  that turned out to be true — `pending` frequently becomes `success`.
