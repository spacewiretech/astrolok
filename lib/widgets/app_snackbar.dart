import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../data/analytics/analytics.dart';
import '../data/analytics/analytics_events.dart';

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

  /// Where this message came from, when the caller knows something the text does not — which
  /// screen the observer reports is often enough, but "the save failed" and "the upload failed"
  /// on one screen are different problems.
  String? source,
}) {
  // Only the failures. A confirmation snackbar is a success the feature already tracked under a
  // better name; an error one is frequently the only record that anything went wrong at all.
  if (error) {
    analytics.track(Ev.errorShown, {
      P.message: message,
      P.source: source,
    });
  }

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
