import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// One prepared player for the paywall's promo clip.
///
/// `VideoPlayerController.initialize()` is a network round trip and a codec handshake — seconds
/// on a mobile connection — and until it returns the paywall's video card is a spinner over a
/// poster, on the one screen that asks the user for money. This exists so the open can be
/// started from onboarding and finished long before the paywall is built.
///
/// Shaped like `DeviceCamera` and `ReadingSpeech`: a plain object wrapping a plugin, so
/// `providers.dart` stays wiring and the widget that draws the clip never learns about Riverpod.
class PromoVideoSource {
  VideoPlayerController? _controller;

  /// Completed by [close]. See [open] for why an aborted open needs one.
  final _cancelled = Completer<void>();

  bool get _isClosed => _cancelled.isCompleted;

  /// An initialised, looping, silent player for [url] — or null when there is nothing to play.
  ///
  /// Null is the ordinary answer, not a failure: no video configured, a malformed URL, a network
  /// that is down, a codec the device will not play. Every one of them lands on the same poster,
  /// because a paywall that cannot show its video must still take money.
  ///
  /// Deliberately does **not** `play()`. The warm-up runs while the user is somewhere else
  /// entirely, and a clip that started then would arrive at the paywall a minute in, having made
  /// noise the whole way. The paywall is what starts it.
  Future<VideoPlayerController?> open(String url) async {
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (trimmed.isEmpty || uri == null || !uri.hasScheme) return null;

    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;

    try {
      // Raced against [close] rather than simply awaited. `initialize()`'s future is only ever
      // completed from inside the plugin's own event listener, and that listener returns early
      // once the controller has been disposed — so a close landing mid-flight would leave this
      // await pending for the life of the app, and the paywall spinning forever. `Future.any`
      // handles the loser's error itself, so the abandoned initialize cannot go unhandled.
      await Future.any([controller.initialize(), _cancelled.future]);
      if (_isClosed) return null;

      await controller.setLooping(true);
      // Silent until the paywall says otherwise, so nothing can be heard during onboarding.
      await controller.setVolume(0);
      return controller;
    } catch (error) {
      debugPrint('[paywall] could not open $trimmed: $error');
      await controller.dispose();
      return null;
    }
  }

  /// Aborts an open still in flight and frees the player.
  ///
  /// Safe to call after [open] has already given up on a failure: `VideoPlayerController.dispose`
  /// returns early once it has run, so the second call is a no-op rather than an assertion.
  Future<void> close() async {
    if (!_cancelled.isCompleted) _cancelled.complete();
    await _controller?.dispose();
    _controller = null;
  }
}
