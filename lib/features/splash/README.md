# lib/features/splash

## Purpose

The launch screen. Resolves the stored session and decides where the user actually belongs.

## Files

- `splash_view.dart` — Declares: `SplashView`.
- `splash_viewmodel.dart` — Declares: `SplashDestination` (enum: `onboarding`, `name`, `birth`,
  `subscribe`, `home`) and `splashDestinationProvider` (`FutureProvider.autoDispose`).

## Notes

- **There is no ViewModel class here** despite the filename — just the enum and a provider.
- This is the onboarding gate, and it is the reason the splash and every onboarding step agree
  about where a given user belongs:

  ```
  !signedIn      -> onboarding
  !hasName       -> onboarding (name step)
  !hasBirthDate  -> birth
  !entitled      -> subscribe
                    home
  ```
- `SplashDestination` is turned into a path by the `SplashDestinationRoute` extension in
  [../../app/router.dart](../../app/router.dart) — the view routes on the destination, the
  viewmodel never touches the router.
- Covered by `test/onboarding_gate_test.dart`.
