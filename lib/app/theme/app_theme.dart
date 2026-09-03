import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Geometry the design repeats across every screen.
///
/// PLACEHOLDER VALUES — see [AppColors].
abstract final class AppShape {
  /// Horizontal padding inside the sheet.
  static const gutter = 24.0;

  /// Bottom sheets carry a large radius on the top two corners only.
  static const sheetRadius = 32.0;

  static const cardRadius = 16.0;
  static const controlRadius = 12.0;

  static const buttonHeight = 52.0;
  static const inputHeight = 56.0;
  static const avatar = 56.0;

  static const card = BorderRadius.all(Radius.circular(cardRadius));
  static const control = BorderRadius.all(Radius.circular(controlRadius));
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      primary: AppColors.brand,
    ),
    scaffoldBackgroundColor: AppColors.scaffold,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineSmall: AppText.display,
      titleMedium: AppText.title,
      bodyLarge: AppText.body,
      bodyMedium: AppText.meta,
    ),
    splashFactory: InkRipple.splashFactory,
  );
}
