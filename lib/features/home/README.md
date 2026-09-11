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
- **Re-reads `app_config` on arrival**, when the cache is over a minute old. This is where a
  dashboard edit reaches an installed app: Home is the one screen every session passes through,
  and the refresh in `providers.dart` only fires on a key being *absent*, so a changed **value**
  — a language added to `chat_languages` — would otherwise sit behind the six-hour cache TTL.
  Throttled rather than unconditional because Home is also every back-navigation's destination,
  and it only invalidates `appConfigProvider` when something actually moved, so the price labels
  and menu rows watching it are not rebuilt on every visit for nothing.
- Tests: `promo_carousel_test.dart` covers the strip's auto-advance, swipe cooldown and
  reduce-motion behaviour; the config refresh's two halves are in `app_config_fallback_test.dart`.
