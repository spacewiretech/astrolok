import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/analytics/analytics.dart';
import '../data/analytics/analytics_events.dart';
import '../data/entitlement.dart';
import '../data/local/trial_scan_tracker.dart';
import '../data/providers.dart';
import '../widgets/trial_scan_limit_dialog.dart';

/// Stops a trial account at the tap once its [feature] reading (`palm` or `face`) is spent, and
/// shows the popup saying why. True when the tap was stopped, in which case the caller must not
/// navigate.
///
/// Only as good as [TrialScanTracker], which is a device-side hint. The reading functions enforce
/// the allowance whatever this answers, and the capture screens show the same popup when they do.
///
/// [source] is the surface that was tapped, for analytics.
Future<bool> guardTrialScan(
  BuildContext context,
  WidgetRef ref,
  String feature, {
  required String source,
}) async {
  final user = ref.read(entitlementProvider);
  if (user == null || !user.inTrial) return false;

  final limit = TrialScanTracker.limitFrom(ref.read(appConfigProvider).valueOrNull, feature);
  final used = await ref.read(trialScanTrackerProvider).used(user.id, feature);
  if (used < limit) return false;

  // Still stopped when the screen went away mid-read: navigating from a dead context is worse than
  // doing nothing.
  if (context.mounted) await showTrialScanLimit(context, ref, feature, source: source);
  return true;
}

/// The trial popup, with the details only the data layer knows, and its analytics event.
///
/// Shared by [guardTrialScan] and the capture screens, which show it when the server refused a
/// photo the device did not know to stop.
Future<void> showTrialScanLimit(
  BuildContext context,
  WidgetRef ref,
  String feature, {
  required String source,
}) {
  analytics.track(Ev.trialScanLimitShown, {P.feature: feature, P.source: source});

  return showTrialScanLimitDialog(
    context,
    limit: TrialScanTracker.limitFrom(ref.read(appConfigProvider).valueOrNull, feature),
    trialEndsAt: ref.read(entitlementProvider)?.trialEndsAt,
  );
}
