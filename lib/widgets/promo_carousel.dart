import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';
import 'primary_button.dart';
import 'safe_asset.dart';

/// One dark promo card: artwork bled to the edges, a two-tone heading, a line of copy and a
/// gold pill.
class PromoSlide {
  const PromoSlide({
    required this.image,
    required this.lead,
    required this.accent,
    required this.body,
    required this.cta,
    required this.onTap,
    this.ctaIcon,
  });

  final String image;

  /// "Chat with" + "Astro" — the accent half renders gold.
  final String lead;
  final String accent;

  final String body;
  final String cta;
  final IconData? ctaIcon;
  final VoidCallback? onTap;
}

/// Home's swipeable promo strip, with its dot row beneath.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({super.key, required this.slides, this.height = 190});

  final List<PromoSlide> slides;
  final double height;

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
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => _Slide(slide: widget.slides[i]),
          ),
        ),
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
    return ClipRRect(
      borderRadius: AppShape.card,
      child: ColoredBox(
        color: AppColors.promoInk,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Aligned right: the artwork is a portrait sitting on the card's right half, and
            // centring it would push the face behind the text.
            Align(
              alignment: Alignment.centerRight,
              child: SafeImage(slide.image, fit: BoxFit.cover),
            ),

            // Keeps the copy legible whatever the artwork does behind it. Without this the
            // heading sits directly on a bright image at the card's midpoint.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xF2120C06), Color(0x99120C06), Color(0x00120C06)],
                  stops: [0.0, 0.5, 0.95],
                ),
              ),
              child: SizedBox.expand(),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${slide.lead} ',
                          style: AppText.display.copyWith(color: Colors.white, fontSize: 24),
                        ),
                        TextSpan(
                          text: slide.accent,
                          style: AppText.display
                              .copyWith(color: AppColors.gold, fontSize: 24),
                        ),
                      ],
                    ),
                    semanticsLabel: '${slide.lead} ${slide.accent}',
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 200,
                    child: Text(
                      slide.body,
                      style: AppText.meta.copyWith(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GoldPillButton(
                    label: slide.cta,
                    icon: slide.ctaIcon,
                    compact: true,
                    onPressed: slide.onTap,
                  ),
                ],
              ),
            ),
          ],
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
