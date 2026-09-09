import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app/assets.dart';
import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import 'safe_asset.dart';

/// The paywall's promo clip.
///
/// The URL comes from `app_config`, so it can be changed without a release — and is routinely
/// empty, which is the normal state before any footage exists. Every failure path lands on the
/// same poster card: an empty URL, a malformed one, a network that is down, a codec the device
/// will not play. A paywall that cannot show its video must still take money.
class PromoVideo extends StatefulWidget {
  const PromoVideo({
    super.key,
    required this.url,
    required this.muted,
    this.aspectRatio = 20 / 20,
  });

  /// Empty means "no video configured" — the poster shows and no player is created.
  final String url;

  /// Driven by the speaker button in the paywall's top bar.
  final bool muted;

  final double aspectRatio;

  @override
  State<PromoVideo> createState() => _PromoVideoState();
}

class _PromoVideoState extends State<PromoVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(covariant PromoVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _dispose();
      _open();
    } else if (oldWidget.muted != widget.muted) {
      _controller?.setVolume(widget.muted ? 0 : 1);
    }
  }

  Future<void> _open() async {
    final url = widget.url.trim();
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.hasScheme) {
      // Not a failure worth reporting — no video configured is the expected state today.
      setState(() => _failed = url.isNotEmpty);
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(widget.muted ? 0 : 1);
      await controller.play();
      setState(() => _controller = controller);
    } catch (error) {
      debugPrint('[paywall] could not play $url: $error');
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  void _dispose() {
    _controller?.dispose();
    _controller = null;
    _failed = false;
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppShape.card,
          border: Border.all(color: AppColors.gold, width: 1.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: controller == null
            ? _Poster(loading: !_failed && widget.url.trim().isNotEmpty)
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
