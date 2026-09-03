import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Geometry the design repeats across every screen.
abstract final class AppShape {
  /// Horizontal padding from the screen edge to content.
  static const gutter = 24.0;

  /// The onboarding sheet's top corners.
  static const sheetRadius = 32.0;

  static const cardRadius = 16.0;
  static const controlRadius = 14.0;

  /// A fully rounded control — the gold CTA pills, the UPI chip, the "Log out" button.
  static const pillRadius = 999.0;

  static const buttonHeight = 56.0;
  static const inputHeight = 58.0;
  static const avatar = 44.0;

  /// The circular chevron on an Explore Readings row, and the paywall's feature discs.
  static const chevronDisc = 40.0;
  static const featureDisc = 52.0;

  static const card = BorderRadius.all(Radius.circular(cardRadius));
  static const control = BorderRadius.all(Radius.circular(controlRadius));
  static const pill = BorderRadius.all(Radius.circular(pillRadius));
  static const sheetTop = BorderRadius.vertical(top: Radius.circular(sheetRadius));
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.gold,
      primary: AppColors.gold,
      surface: AppColors.surface,
    ),
    // Screens paint AstralBackground over this; the colour matters only for the moment before
    // the first frame and for any route that does not.
    scaffoldBackgroundColor: AppColors.cream,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineMedium: AppText.display,
      headlineSmall: AppText.sheetTitle,
      titleLarge: AppText.section,
      titleMedium: AppText.title,
      bodyLarge: AppText.body,
      bodyMedium: AppText.meta,
      labelSmall: AppText.legal,
    ),
    splashFactory: InkRipple.splashFactory,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.navy,
      contentTextStyle: AppText.meta.copyWith(color: Colors.white),
      shape: const RoundedRectangleBorder(borderRadius: AppShape.control),
    ),
  );
}
