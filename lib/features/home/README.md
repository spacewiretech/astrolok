# lib/features/home

## Purpose

The signed-in, paid-for home screen: the promo carousel and the Explore Readings rows that lead
into the palm, face and chat flows.

## Files

- `home_view.dart` — Declares: `HomeView`. **The only file in this feature** — no viewmodel, no
  state, no copy; it composes shared widgets and reads existing providers.

## Notes

- Behind `EntitlementGate`, and the destination the splash gate sends an entitled user to.
- Draws on `Img.bgHome` (a distinctly warmer ground than the onboarding one) plus
  `PromoCarousel` and `ReadingCard` from [../../widgets/](../../widgets/). The promo cards are
  exported flattened — artwork, heading and button are all pixels — so each carries its own
  Semantics label.
- The billing notice here is the same one `profile_view.dart` shows, for an account in grace or
  about to lapse.
- Invalidates `promoVideoProvider` after the first frame: the paywall is behind this user, so the
  player onboarding warmed is a video decoder held open for nothing. Safe because nothing is
  listening by then — Riverpod disposes an invalidated provider without rebuilding it, so this
  frees the player rather than starting a fresh download.
- Tests: `promo_carousel_test.dart` covers the strip's auto-advance, swipe cooldown and
  reduce-motion behaviour.
