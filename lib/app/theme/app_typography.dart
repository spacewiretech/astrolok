import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// The type scale, read off the Figma renders.
///
/// Poppins carries headings, labels and buttons; Inter carries body copy. If the Figma names a
/// different family, both are one-line changes here.
abstract final class AppText {
  /// "Namaste🙏", "Set Your Date of Birth", "Read Your Palm" — the screen title.
  static TextStyle get display => GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.4,
        color: AppColors.heading,
      );

  /// The sheet titles — "Enter your mobile number". A step down from [display].
  static TextStyle get sheetTitle => GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: -0.3,
        color: AppColors.heading,
      );

  /// "Explore Readings", "What would you like to explore?".
  static TextStyle get section => GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: AppColors.heading,
      );

  /// Card and row titles — "Palm Reading".
  static TextStyle get title => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: AppColors.heading,
      );

  static TextStyle get button => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: Colors.white,
      );

  /// The big gold trial price on the paywall.
  static TextStyle get priceHero => GoogleFonts.poppins(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        height: 1.1,
        color: AppColors.gold,
      );

  /// The struck-through monthly price beside it.
  static TextStyle get priceStrike => GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: AppColors.muted,
        decoration: TextDecoration.lineThrough,
        decorationColor: AppColors.muted,
        decorationThickness: 1.6,
      );

  /// Subtitles and paragraph copy.
  static TextStyle get body => GoogleFonts.inter(
        fontSize: 15,
        height: 1.5,
        color: AppColors.body,
      );

  /// Secondary detail lines — card subtitles, the resend countdown.
  static TextStyle get meta => GoogleFonts.inter(
        fontSize: 14,
        height: 1.45,
        color: AppColors.muted,
      );

  /// The two-line labels under the paywall's feature discs.
  ///
  /// Four to a row on a 393pt screen leaves roughly 78pt per column, which is what sets this
  /// size — at 12 the longest label breaks mid-word.
  static TextStyle get tileLabel => GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: AppColors.heading,
      );

  /// Text typed into a field, and the selected value in a picker wheel.
  static TextStyle get input => GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w500,
        color: AppColors.heading,
      );

  /// The unselected rows of a picker wheel.
  static TextStyle get wheelIdle => GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w400,
        color: AppColors.muted,
      );

  /// The row under the selection band.
  static TextStyle get wheelSelected => GoogleFonts.poppins(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        color: AppColors.gold,
      );

  /// Terms and privacy footer, and the UPI mandate consent line.
  static TextStyle get legal => GoogleFonts.inter(
        fontSize: 12,
        height: 1.45,
        color: AppColors.muted,
      );
}
