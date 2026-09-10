# lib/data/media

## Purpose

The paywall's promo clip, opened well before the paywall is reached.

## Files

- `promo_video_source.dart` — Declares: `PromoVideoSource` (`open`, `close`).

## Notes

- **Why this exists at all.** `VideoPlayerController.initialize()` is a network round trip and a
  codec handshake, and until it returns the paywall's video card is a spinner over a poster — on
  the one screen that asks the user for money. Opening the player from the onboarding phone sheet
  turns onboarding and the birth date into lead time.
- `open()` returns **null for every failure**, not an exception: no URL configured, a malformed
  one, a dead network, an unplayable codec. They all land on the same poster, because a paywall
  that cannot show its video must still take money.
- `open()` deliberately never calls `play()`. The warm-up runs while the user is on another
  screen; a clip started there would arrive at the paywall a minute in, having made noise the
  whole way. [../../features/subscription/](../../features/subscription/) is what starts it.
- **`close()` races an open still in flight.** `initialize()`'s future is only ever completed
  from inside the plugin's own event listener, and that listener returns early once the
  controller is disposed — so a close landing mid-open would leave the await pending for the life
  of the app and the paywall spinning forever. That is what the internal `Completer` is for.
- Provided as `promoVideoProvider` in [../providers.dart](../providers.dart), deliberately not
  `autoDispose`: the screen that starts it is torn down four routes before the screen that uses
  it. `HomeView` invalidates it once the paywall is behind the user, to free the decoder.
- Tests: [../../../test/promo_video_test.dart](../../../test/promo_video_test.dart). Every path
  it asserts returns before a controller is built, which is what keeps the suite off the
  `video_player` platform channel.
