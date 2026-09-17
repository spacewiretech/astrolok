# lib/features/onboarding

## Purpose

Phone number and OTP — Figma frames rendered as one screen with a swapping bottom sheet over a
changing hero. Verifying always leaves the screen: a new account goes on to
[../language/](../language/), and the name is asked after payment on [../birth/](../birth/).

## Files

- `onboarding_view.dart` — Declares: `OnboardingView` (takes `initialStep`).
- `onboarding_viewmodel.dart` — Declares: `OnboardingViewModel`, `onboardingViewModelProvider`.
- `onboarding_state.dart` — Declares: `OnboardingStep` (with `parse`), `OnboardingState`.

## Notes

- One screen, not two routes: the hero slides through `Img.onboardHero` while only the sheet
  below it swaps. `?step=name` from an older build parses to `phone`.
- "Have an invite code?" used to sit on the name sheet. It moved to the language screen as
  [../../widgets/invite_code_row.dart](../../widgets/invite_code_row.dart), not after payment:
  `referral-claim` refuses any account that has had a trial.
- No `_copy.dart` — the strings are inline here.
- Auth runs through `authRepositoryProvider`, which is the only capability with all three
  backend rungs (Supabase → Fast2SMS direct → fake). On the fake tier any 6-digit code works.
- Resend uses a wall-clock countdown, so backgrounding the app does not pause it.
- **This screen warms the paywall's promo video** with one `ref.read(promoVideoProvider)` — a
  screen two routes away, but opening a player is a network round trip and the paywall is where
  it would otherwise be paid for, as a spinner. `read` rather than `watch`: nothing here redraws
  when the player lands, and the provider is kept alive, so the one read outlives onboarding.
- `TermsFooter` on the sheets links to `astrolok.app/privacy` and `/terms` — those URLs are
  served by [../../website/](../../website/), which is why the marketing site exists.
- Tests: `widget_test.dart` (`OnboardingState`: Indian mobile validation, code invalidation on
  number change, resend countdown) and `field_focus_test.dart`.
