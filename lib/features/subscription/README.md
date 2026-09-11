# lib/features/subscription

## Purpose

The paywall: the offer, the Cashfree UPI Autopay mandate, and the entitlement polling that
follows it.

## Files

- `subscription_view.dart` — Declares: `SubscriptionView` (trial headline, price row, rating
  row, UPI app chips, the promo video card).
- `subscription_viewmodel.dart` — Declares: `SubscriptionPhase`, `SubscriptionState`,
  `SubscriptionViewModel`, `subscriptionViewModelProvider`, and `subscriptionPollDelaysProvider`
  (overridden in tests so the poll schedule does not make the suite slow).

## Notes

- **The client sends no amount and no plan id**, only its session token; everything billable is
  resolved server-side from `app_config`. Prices shown here come from `SubscriptionOffer`.
- **The Cashfree SDK callback is never treated as proof of payment.** It means the UPI app
  handed control back, not that money moved — so every outcome ends by polling
  `subscription-status`, which reconciles against Cashfree. `subscriptionPollDelaysProvider` is
  that schedule.
- Outcomes are three-valued, not two: `pending` exists so a real payment whose webhook is late
  is never reported as a failure. See [../payment_status/](../payment_status/).
- State lives in the viewmodel file; there is no `_state.dart` and no `_copy.dart`.
- The promo clip is streamed from a URL in `app_config` so it can be swapped without shipping a
  release; absent config falls back to a static poster.
- **The player is opened back at the onboarding phone sheet, not here.** Opening one is a network
  round trip, and doing it on mount is what made this screen's video card a spinner. `PromoVideo`
  is handed the warmed controller and must not dispose it — see
  [../../data/media/](../../data/media/). This screen gates on `isLoading || hasError` rather
  than reading `valueOrNull`, because a refreshing provider keeps handing back the previous —
  already disposed — player.
- Ungated on purpose — this *is* the paywall.
- Tests: `layout_test.dart` (paywall layout), `offer_test.dart` (pricing defaults).
