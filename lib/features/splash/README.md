# lib/features/splash

## Purpose

The launch screen. Resolves the stored session and decides where the user actually belongs.

## Files

- `splash_view.dart` — Declares: `SplashView`.
- `splash_viewmodel.dart` — Declares: `SplashDestination` (enum: `onboarding`, `language`,
  `subscribe`, `birth`, `home`), `destinationForSession`, `destinationForUser`,
  `destinationAfterPayment` and `splashDestinationProvider` (`FutureProvider.autoDispose`).

## Notes

- **There is no ViewModel class here** despite the filename — just the enum and a provider.
- This is the onboarding gate, and it is the reason the splash and every onboarding step agree
  about where a given user belongs:

  ```
  !signedIn                  -> onboarding (phone → OTP)
  !entitled && !hasLanguage  -> language
  !entitled                  -> subscribe
  !hasName || !hasBirthDate  -> birth (name + date of birth, after payment)
                                home
  ```
- The language is only asked of an **unentitled** account that has never chosen one. A subscriber
  with no saved language follows `chat_language_default` and is never stopped to pick.
- `destinationAfterPayment` is what the payment-status screen routes on. It ignores entitlement on
  purpose: the paywall does not refresh `entitlementProvider`, so the user held straight after
  checkout still reads as unentitled.
- `SplashDestination` is turned into a path by the `SplashDestinationRoute` extension in
  [../../app/router.dart](../../app/router.dart) — the view routes on the destination, the
  viewmodel never touches the router.
- Covered by `test/onboarding_gate_test.dart`.
