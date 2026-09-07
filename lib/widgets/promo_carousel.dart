import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';
import 'safe_asset.dart';

/// One promo card.
///
/// The card is exported flattened — artwork, heading and button are all pixels — so there is
/// nothing to lay out and [label] is the only way a screen reader learns what it says. Whatever
/// the image reads, [label] must match it.
class PromoSlide {
  const PromoSlide({required this.image, required this.label, required this.onTap});

  final String image;

  /// Announced in place of the flattened text.
  final String label;

  final VoidCallback? onTap;
}

/// Home's swipeable promo strip, with its dot row beneath.
///
/// The whole card is the tap target rather than just the drawn button: the button is part of
/// the image, so there is no way to hit-test it, and a card where only one painted region
/// responded would be worse than one where all of it does.
///
/// The strip advances on its own every [_interval] and wraps at the end. It is a promo, so it
/// has to show more than the card the user happens to have landed on — but it yields to the
/// user: a swipe restarts the clock rather than being fought for the next page.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({super.key, required this.slides});

  final List<PromoSlide> slides;

  /// The export is 712x346.
  static const cardAspect = 712 / 346;

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  /// The visible channel between two cards mid-swipe. It is taken out of the page, not out of
  /// the card: the strip bleeds half of it into the gutter on each side so a card at rest is
  /// still exactly as wide as the reading rows below it.
  static const _gap = 12.0;

  /// Long enough to read a card before it moves. The wrap back to the first slide covers more
  /// ground, so it gets its own, longer duration and does not read as a snap.
  static const _interval = Duration(seconds: 4);
  static const _step = Duration(milliseconds: 450);
  static const _rewind = Duration(milliseconds: 700);

  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-read here rather than in initState: `disableAnimations` is a MediaQuery value and can
    // change under us while the screen is up.
    _restartTimer();
  }

  @override
  void didUpdateWidget(PromoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.slides.length != oldWidget.slides.length) _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    // Nothing to advance to, or the platform has asked for no motion — a strip that moves on
    // its own is the exact thing that setting is turning off. Swiping still works.
    if (widget.slides.length < 2) return;
    if (MediaQuery.of(context).disableAnimations) return;
    _timer = Timer.periodic(_interval, (_) => _advance());
  }

  void _advance() {
    if (!_controller.hasClients || widget.slides.length < 2) return;
    final next = (_page + 1) % widget.slides.length;
    _controller.animateToPage(
      next,
      duration: next == 0 ? _rewind : _step,
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return SizedBox(
              height: width / PromoCarousel.cardAspect,
              // The PageView is one gap wider than the space it was given, centred, so each
              // page can carry half a gap of padding and still leave the card full width.
              child: OverflowBox(
                maxWidth: width + _gap,
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.slides.length,
                  onPageChanged: (i) {
                    setState(() => _page = i);
                    // Give the next auto-advance a full interval from here, whoever turned the
                    // page. A card the user just swiped to should not slide away early.
                    _restartTimer();
                  },
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _gap / 2),
                    child: _Slide(slide: widget.slides[i]),
                  ),
                ),
              ),
            );
          },
        ),
        // Hidden at one slide: a single dot is not an indicator, it is a dot.
        if (widget.slides.length > 1) ...[
          const SizedBox(height: 14),
          _Dots(count: widget.slides.length, active: _page),
        ],
      ],
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.slide});

  final PromoSlide slide;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: slide.label,
      child: Material(
        color: AppColors.promoInk,
        borderRadius: AppShape.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: slide.onTap,
          child: SafeImage(
            slide.image,
            fit: BoxFit.cover,
            // Until the card is exported: its heading on the dark ground, so the strip still
            // reads as a promo rather than a black rectangle.
            fallback: Padding(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  slide.label,
                  style: AppText.title.copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The page indicator: the active dot stretches into a short bar.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == active ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == active ? AppColors.gold : AppColors.gold.withValues(alpha: 0.3),
              borderRadius: AppShape.pill,
            ),
          ),
        ],
      ],
    );
  }
}
