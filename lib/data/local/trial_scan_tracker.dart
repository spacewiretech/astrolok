import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How many readings an account has had during its trial, remembered on this device.
///
/// A hint, not the rule. `palm-reading` and `face-reading` count on the server and refuse past the
/// allowance whatever this says. It exists so that a trial user who has had their reading is told
/// so when they tap it on Home, rather than after opening the camera and taking a photo the server
/// was always going to refuse.
///
/// Keyed by account as well as by feature, because the reading caches are not: they belong to the
/// device, so a second account signing in on the same phone would otherwise inherit the first
/// one's count and be turned away from a reading it is owed.
///
/// Every failure reads as nothing used. Wrong in that direction costs one round trip to be refused;
/// wrong in the other blocks a reading the server would have allowed.
class TrialScanTracker {
  const TrialScanTracker();

  /// What the server applies when `app_config` has no usable row.
  static const defaultLimit = 1;

  /// The allowance for [feature] (`palm` or `face`), from the same public rows the server reads —
  /// `trial_palm_readings` and `trial_face_readings` — and parsed the same way, so raising one in
  /// the dashboard moves the app and the server together.
  static int limitFrom(Map<String, String>? config, String feature) {
    final value = double.tryParse(config?['trial_${feature}_readings']?.trim() ?? '');
    if (value == null || !value.isFinite) return defaultLimit;
    final limit = value.floor();
    return limit >= 1 ? limit : defaultLimit;
  }

  static String _key(String userId, String feature) => 'astrolok.trial_scans.$userId.$feature';

  Future<int> used(String userId, String feature) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt(_key(userId, feature)) ?? 0;
      return count < 0 ? 0 : count;
    } catch (error) {
      debugPrint('[trial] could not read the scan count: $error');
      return 0;
    }
  }

  /// One more reading received during the trial.
  Future<void> recordReading(String userId, String feature) async {
    await _write(userId, feature, await used(userId, feature) + 1);
  }

  /// The server refused on the trial allowance, so this device's count was behind — a reinstall,
  /// or a reading taken on another phone. Brought up to [limit] so the next tap says so up front.
  Future<void> markExhausted(String userId, String feature, int limit) async {
    if (await used(userId, feature) >= limit) return;
    await _write(userId, feature, limit);
  }

  Future<void> _write(String userId, String feature, int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key(userId, feature), count);
    } catch (error) {
      debugPrint('[trial] could not save the scan count: $error');
    }
  }
}
