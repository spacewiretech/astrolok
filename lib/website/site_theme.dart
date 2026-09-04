import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app/theme/app_colors.dart';

/// Where the layout changes shape. Below [Breaks.mobile] everything is one column; between
/// the two the grids halve; above [Breaks.tablet] the hero splits in two.
abstract final class Breaks {
  static const mobile = 720.0;
  static const tablet = 1024.0;
}

abstract final class SiteShape {
  /// Content never runs wider than this, however wide the window gets.
  static const maxWidth = 1120.0;

  static const gutter = 24.0;
  static const gutterMobile = 20.0;

  /// Height of the nav bar, and the offset in-page anchors have to clear.
  static const navHeight = 72.0;

  static const cardRadius = BorderRadius.all(Radius.circular(20));
  static const pillRadius = BorderRadius.all(Radius.circular(999));
}

bool isMobile(BuildContext context) => MediaQuery.sizeOf(context).width < Breaks.mobile;

bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= Breaks.tablet;

/// How many columns a card grid gets at this width: 4 / 2 / 1.
int gridColumns(BuildContext context, {int max = 4}) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < Breaks.mobile) return 1;
  if (width < Breaks.tablet) return max >= 4 ? 2 : max;
  return max;
}

/// Extra palette the site needs and the app does not — the app never renders a dark band, and
/// its cream grounds come from full-bleed artwork that a wide desktop page cannot tile.
abstract final class SiteColors {
  /// The dark band behind the closing call to action. A shade off [AppColors.navy] so gold
  /// still separates from it, matching the promo card on Home.
  static const ink = Color(0xFF080A1F);

  /// Section ground that separates a band from the white above it. The warm end of the app's
  /// home gradient, flattened — the site alternates white and this rather than running one
  /// gradient the length of a long page.
  static const tint = Color(0xFFFFF8EC);

  /// A slightly deeper tint for the hero, so the fold reads as its own band.
  static const heroTint = Color(0xFFFEF1DC);

  static const border = Color(0xFFF0E7D6);

  /// Footer body copy on [ink].
  static const onInkMuted = Color(0xFFB5AE9E);

  /// Gold reads well on ink as-is — it is a light hue on a dark ground — so unlike Circle360's
  /// blue there is no lifted variant. Named anyway so the footer says what it means.
  static const brandOnInk = AppColors.gold;
}

/// Web-scale type. The app's [AppText] tops out at 28px for a phone sheet; a landing page hero
/// needs double that, so the site keeps its own ramp on the same two families — Poppins for
/// headings, Inter for body.
abstract final class SiteText {
  static TextStyle hero(BuildContext context) => GoogleFonts.poppins(
        fontSize: isMobile(context) ? 36 : (isDesktop(context) ? 56 : 44),
        fontWeight: FontWeight.w700,
        height: 1.12,
        letterSpacing: -1.2,
        color: AppColors.heading,
      );

  static TextStyle heroSub(BuildContext context) => GoogleFonts.inter(
        fontSize: isMobile(context) ? 16 : 19,
        height: 1.6,
        color: AppColors.body,
      );

  /// Section headings — "Three ways to read your future".
  static TextStyle section(BuildContext context) => GoogleFonts.poppins(
        fontSize: isMobile(context) ? 27 : 38,
        fontWeight: FontWeight.w600,
        height: 1.22,
        letterSpacing: -0.6,
        color: AppColors.heading,
      );

  /// The line under a section heading.
  static TextStyle sectionSub(BuildContext context) => GoogleFonts.inter(
        fontSize: isMobile(context) ? 15 : 17,
        height: 1.6,
        color: AppColors.muted,
      );

  static TextStyle cardTitle(BuildContext context) => GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: AppColors.heading,
      );

  static TextStyle cardBody(BuildContext context) => GoogleFonts.inter(
        fontSize: 15,
        height: 1.62,
        color: AppColors.muted,
      );

  /// Long-form policy paragraphs. Looser than [cardBody] — these pages are read, not scanned.
  static TextStyle prose(BuildContext context) => GoogleFonts.inter(
        fontSize: 15.5,
        height: 1.78,
        color: AppColors.body,
      );

  static TextStyle policyHeading(BuildContext context) => GoogleFonts.poppins(
        fontSize: isMobile(context) ? 19 : 21,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: AppColors.heading,
      );

  static TextStyle navLink = GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.heading,
  );

  static TextStyle eyebrow = GoogleFonts.inter(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.9,
    // The gold is tuned for a filled button; on cream at 12.5px it is too light to read, so
    // the eyebrow takes the deeper end of the pair.
    color: AppColors.goldDeep,
  );

  static TextStyle footerLink = GoogleFonts.inter(
    fontSize: 14.5,
    height: 2.0,
    color: SiteColors.onInkMuted,
  );

  static TextStyle footerHeading = GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    color: Colors.white,
  );
}

ThemeData buildSiteTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.gold,
      primary: AppColors.gold,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.surface,
  );

  return base.copyWith(
    // A landing page is read with a mouse; the phone app's ink splash reads as a misfire here.
    splashFactory: NoSplash.splashFactory,
    dividerTheme: const DividerThemeData(color: SiteColors.border, thickness: 1, space: 1),
  );
}
