import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// The type scale.
///
/// PLACEHOLDER VALUES, like [AppColors] — sizes and families are provisional until the Figma
/// exports are read. Screens reference these names, so the real scale lands as one edit here.
///
/// Poppins carries headings, labels and buttons; Inter carries body copy.
abstract final class AppText {
  /// Screen titles.
  static TextStyle get display => GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: AppColors.heading,
      );

  /// Same size as [display] in a lighter weight, for a two-line greeting.
  static TextStyle get welcome => GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w500,
        height: 1.2,
        color: AppColors.heading,
      );

  /// Row and card titles.
  static TextStyle get title => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 22 / 16,
        color: AppColors.heading,
      );

  static TextStyle get button => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      );

  static TextStyle get price => GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.heading,
      );

  /// Subtitles and paragraph copy.
  static TextStyle get body => GoogleFonts.inter(
        fontSize: 16,
        height: 22 / 16,
        color: AppColors.body,
      );

  /// Secondary detail lines.
  static TextStyle get meta => GoogleFonts.inter(
        fontSize: 14,
        height: 22 / 14,
        color: AppColors.muted,
      );

  /// Text typed into a field.
  static TextStyle get input => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: AppColors.heading,
      );

  /// Terms and privacy footer.
  static TextStyle get legal => GoogleFonts.inter(
        fontSize: 10,
        color: AppColors.muted,
      );
}
