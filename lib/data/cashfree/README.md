# lib/data/cashfree

## Purpose

The UPI Autopay checkout wrapper around the Cashfree SDK, and the remembered UPI app.

## Files

- `cashfree_checkout.dart` — the checkout port and the SDK implementation. Declares:
  `CheckoutOutcome` (enum: `verified`, `failed`), `CheckoutResult`, `CashfreeCheckout`
  (`installedApps`, `openWithApp`, `open`), `SdkCashfreeCheckout`.
- `upi_app_preference.dart` — remembers which UPI app the user last paid with, so the paywall
  opens on it next time. Declares: `UpiAppPreference` (`read`, `save`).

## Notes

- **The SDK callback is never treated as proof of payment.** `CheckoutOutcome.verified` means
  the UPI app handed control back, not that money moved — every outcome ends by polling
  `subscription-status`, which reconciles against Cashfree. See
  [../../features/subscription/](../../features/subscription/).
- The client sends no amount and no plan id, only its session token; everything billable is
  resolved server-side from `app_config`.
- `UpiAppPreference` uses `shared_preferences`, deliberately not `SessionStore` — the Keychain
  is for credentials, and this is a cosmetic preference.
- The fake tier substitutes `FakeCashfreeCheckout` from
  [../fake/fake_subscription_repository.dart](../fake/fake_subscription_repository.dart).
