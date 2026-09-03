import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/palm_reading.dart';

/// The recent readings, cached on the device.
///
/// This is what makes `/palm/reading/:id` survive a cold start: the results and detail screens
/// are routed to by id, and without a cache a user who backgrounds the app on the detail
/// screen would come back to an empty one. It also means a saved reading can be re-read with
/// no network.
///
/// `shared_preferences` rather than the secure store — a reading is personal but it is not a
/// credential, and the Keychain is for things that are.
class PalmReadingStore {
  PalmReadingStore();

  static const _key = 'astrolok.palm_readings';

  /// Bumped whenever the stored shape changes. An older payload is dropped rather than
  /// half-parsed, so a build that adds a field cannot inherit a broken record from one that
  /// did not have it.
  static const _version = 1;

  /// Matches what [PalmImageStore] keeps, so a cached reading and its photo age out together.
  static const _keep = 10;

  Future<List<PalmReading>> all() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const [];

      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['v'] != _version) return const [];

      final entries = decoded['readings'];
      if (entries is! List) return const [];

      return [
        for (final entry in entries) ?PalmReading.fromServer(entry),
      ];
    } catch (error) {
      // A corrupt cache must never stop the app opening a screen; it just has nothing to show.
      debugPrint('[palm] could not read the cache: $error');
      return const [];
    }
  }

  Future<PalmReading?> byId(String id) async {
    for (final reading in await all()) {
      if (reading.id == id) return reading;
    }
    return null;
  }

  /// Adds or replaces a reading, keeping the newest [_keep].
  Future<void> save(PalmReading reading) async {
    try {
      // Filtered into a new list rather than mutated: `all()` returns `const []` when the
      // cache is empty, and removeWhere on an immutable list throws — which would be every
      // first save on a fresh install.
      final existing = await all();
      final readings = [
        reading,
        for (final r in existing)
          if (r.id != reading.id) r,
      ].take(_keep).toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'v': _version,
          'readings': [for (final r in readings) r.toJson()],
        }),
      );
    } catch (error) {
      // The reading is already on screen; failing to cache it costs only the ability to
      // reopen it later, which is not worth interrupting the user for.
      debugPrint('[palm] could not cache the reading: $error');
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (error) {
      debugPrint('[palm] could not clear the cache: $error');
    }
  }
}
