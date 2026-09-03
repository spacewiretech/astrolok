import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app/assets.dart';
import '../app/theme/app_colors.dart';
import 'safe_asset.dart';

/// The oṃ disc and the two-tone wordmark.
///
/// The wordmark is drawn as text rather than shipped as an image so it stays crisp at any size
/// and inherits the type scale. Only the disc is artwork.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 40, this.showWordmark = true});

  /// Diameter of the disc; the wordmark scales from it.
  final double size;

  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: size),
        if (showWordmark) ...[
          SizedBox(width: size * 0.28),
          Wordmark(fontSize: size * 0.62),
        ],
      ],
    );
  }
}

/// The navy disc with the gold oṃ, on its own.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: SafeSvg(
        Svg.omMark,
        width: size * 0.58,
        height: size * 0.58,
        semanticLabel: 'Astrolok',
        // The glyph itself until the artwork lands — the disc is the recognisable part, and a
        // blank circle would read as a loading state.
        fallback: FittedBox(
          child: Text(
            'ॐ',
            style: GoogleFonts.notoSansDevanagari(
              color: AppColors.gold,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Astro" in navy, "lok" in gold.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.fontSize = 24});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.poppins(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.1,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Astro', style: base.copyWith(color: AppColors.navy)),
          TextSpan(text: 'lok', style: base.copyWith(color: AppColors.gold)),
        ],
      ),
      // One word to a screen reader, not two.
      semanticsLabel: 'Astrolok',
    );
  }
}

/// A heading whose last word is picked out in gold — "Read Your **Palm**", "Show us your
/// **Face**". The design uses this shape on every titled screen.
class AccentHeading extends StatelessWidget {
  const AccentHeading({
    super.key,
    required this.lead,
    required this.accent,
    this.style,
    this.textAlign = TextAlign.center,
  });

  final String lead;
  final String accent;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.headlineMedium!;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$lead ', style: base),
          TextSpan(text: accent, style: base.copyWith(color: AppColors.gold)),
        ],
      ),
      textAlign: textAlign,
      semanticsLabel: '$lead $accent',
    );
  }
}
