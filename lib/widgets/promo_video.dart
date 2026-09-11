import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app/assets.dart';
import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import 'safe_asset.dart';

/// The paywall's promo clip.
///
/// The player is **borrowed**, not built here: `promoVideoProvider` owns it and warms it from
/// the onboarding phone sheet, so by the time the paywall builds the network round trip is
/// usually finished and there is a frame to paint instead of a spinner. Which means this widget
/// must never dispose what it is handed — the player outlives the paywall, and a second visit
/// would otherwise attach to a dead one.
///
/// A null [controller] with [loading] set is the open still running. A null one without it is
/// every other case at once — no video configured, a malformed URL, a network that is down, a
/// codec the device will not play — and they share the one poster card, because a paywall that
/// cannot show its video must still take money.
class PromoVideo extends StatefulWidget {
  const PromoVideo({
    super.key,
    required this.controller,
    required this.loading,
    required this.muted,
    this.aspectRatio = 20 / 20,
  });

  /// Owned by the caller. Started and stopped here, never disposed here.
  final VideoPlayerController? controller;

  /// Whether a player is still on its way. Decides between the spinner and the play button.
  final bool loading;

  /// Driven by the speaker button in the paywall's top bar.
  final bool muted;

  final double aspectRatio;

  @override
  State<PromoVideo> createState() => _PromoVideoState();
}

class _PromoVideoState extends State<PromoVideo> {
  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(covariant PromoVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A player that has just arrived has to be started *and* have its volume set. Reacting only
    // to a change in `muted` would leave a warmed clip playing silently for ever: the warm-up
    // leaves it at volume zero, and its arrival is a change of controller, not of muted.
    if (oldWidget.controller != widget.controller) {
      _attach();
    } else if (oldWidget.muted != widget.muted) {
      widget.controller?.setVolume(widget.muted ? 0 : 1);
    }
  }

  /// Starts the borrowed player at the volume the paywall is asking for.
  void _attach() {
    final controller = widget.controller;
    if (controller == null || !controller.value.isInitialized) return;
    controller.setVolume(widget.muted ? 0 : 1);
    controller.play();
  }

  @override
  void dispose() {
    // Stopped, not disposed — and this is load-bearing rather than tidy. The player belongs to
    // the provider and survives this screen, so without it the clip would go on playing, with
    // sound, behind whatever the user navigated to, and the next visit to the paywall would
    // join it part-way through.
    final controller = widget.controller;
    controller?.setVolume(0);
    controller?.pause();
    controller?.seekTo(Duration.zero);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppShape.card,
          border: Border.all(color: AppColors.gold, width: 1.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: controller == null
            ? _Poster(loading: widget.loading)
            : FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
      ),
    );
  }
}

/// What the card shows with no player: the poster art, or the gold play button on the cream
/// ground when even that is missing.
class _Poster extends StatelessWidget {
  const _Poster({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.cream,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const SafeImage(Img.paywallPoster, fit: BoxFit.cover),
          Center(
            child: loading
                ? const CircularProgressIndicator(color: AppColors.gold)
                : Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      gradient: AppColors.goldFill,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 36,
                      color: Colors.white,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
