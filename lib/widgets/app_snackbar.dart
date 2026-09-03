import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';

/// Shows a snackbar, replacing whatever is already up.
///
/// The theme already styles these — floating, navy, `AppShape.control` — so this only exists
/// to stop half a dozen call sites repeating the `hideCurrentSnackBar` dance. Without it, two
/// messages in quick succession queue up and the second appears seconds after the thing that
/// caused it.
void showAppSnackBar(
  BuildContext context,
  String message, {
  /// Tints the bar red. For "we couldn't read that photo", which the user has to act on.
  bool error = false,
  Duration duration = const Duration(seconds: 4),
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        backgroundColor: error ? AppColors.danger : null,
      ),
    );
}
