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
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({super.key, required this.slides});

  final List<PromoSlide> slides;

  /// The export is 712x346.
  static const cardAspect = 712 / 346;

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: PromoCarousel.cardAspect,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => _Slide(slide: widget.slides[i]),
          ),
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
