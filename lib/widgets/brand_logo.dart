import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app/assets.dart';
import '../app/theme/app_colors.dart';
import 'safe_asset.dart';

/// The full lockup: the oṃ disc and the two-tone "Astrolok".
///
/// Rendered from the exported artwork rather than composed from a disc and two `TextSpan`s —
/// the export has letterspacing and a glyph the font does not reproduce. The drawn version is
/// kept as the fallback, so a missing file still leaves a legible, correctly coloured wordmark
/// rather than a gap where the brand should be.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 40, this.showWordmark = true});

  /// Height of the mark; the lockup scales from it.
  final double size;

  final bool showWordmark;

  /// The export is 278x80 — the lockup is this many times wider than it is tall.
  static const _lockupAspect = 278 / 80;

  @override
  Widget build(BuildContext context) {
    if (!showWordmark) return BrandMark(size: size);

    return SafeImage(
      Brand.wordmark,
      height: size,
      width: size * _lockupAspect,
      fit: BoxFit.contain,
      semanticLabel: 'Astrolok',
      fallback: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandMark(size: size),
          SizedBox(width: size * 0.28),
          Wordmark(fontSize: size * 0.62),
        ],
      ),
    );
  }
}

/// The navy disc with the gold oṃ, on its own.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SafeImage(
      Brand.mark,
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'Astrolok',
      fallback: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: FittedBox(
          child: Padding(
            padding: EdgeInsets.all(size * 0.22),
            child: Text(
              'ॐ',
              style: GoogleFonts.notoSansDevanagari(
                color: AppColors.gold,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Astro" in navy, "lok" in gold. The drawn wordmark, used as [BrandLogo]'s fallback.
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

/// A heading with one word picked out in gold — "Read Your **Palm**", "Show us your
/// **Face**", "Your **Face** Readings". The design uses this shape on every titled screen.
class AccentHeading extends StatelessWidget {
  const AccentHeading({
    super.key,
    required this.lead,
    required this.accent,
    this.tail = '',
    this.style,
    this.textAlign = TextAlign.center,
  });

  final String lead;
  final String accent;

  /// What follows the gold word, when the accent is not the last one — "Your **Face**
  /// Readings". Empty for the more common case where the heading ends on the accent.
  final String tail;

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
          if (tail.isNotEmpty) TextSpan(text: tail, style: base),
        ],
      ),
      textAlign: textAlign,
      semanticsLabel: '$lead $accent$tail',
    );
  }
}
