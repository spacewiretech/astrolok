import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/face_reading.dart';
import '../models/palm_reading.dart';

/// The recent readings, cached on the device.
///
/// This is what makes `/palm/reading/:id` and `/face/reading/:id` survive a cold start: the
/// results and detail screens are routed to by id, and without a cache a user who backgrounds
/// the app on a detail screen would come back to an empty one. It also means a saved reading can
/// be re-read with no network.
///
/// `shared_preferences` rather than the secure store — a reading is personal but it is not a
/// credential, and the Keychain is for things that are.
///
/// Generic over the reading type so palm and face share the versioning, the pruning and the
/// corrupt-cache handling rather than keeping two copies of it that can drift.
abstract class ReadingStore<T> {
  const ReadingStore();

  /// The `shared_preferences` key. Distinct per feature, so the two caches are independent.
  String get storageKey;

  /// Bumped whenever the stored shape changes. An older payload is dropped rather than
  /// half-parsed, so a build that adds a field cannot inherit a broken record from one that
  /// did not have it.
  int get version;

  /// Matches what [ReadingImageStore] keeps, so a cached reading and its photo age out together.
  static const _keep = 10;

  /// Null for an entry this build cannot make sense of. Dropped, never half-built.
  T? parse(Object? raw);

  Map<String, dynamic> encode(T reading);

  String idOf(T reading);

  /// Used only for the log prefix, so a console line says which feature it came from.
  String get logTag;

  Future<List<T>> all() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) return const [];

      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['v'] != version) return const [];

      final entries = decoded['readings'];
      if (entries is! List) return const [];

      return [
        for (final entry in entries) ?parse(entry),
      ];
    } catch (error) {
      // A corrupt cache must never stop the app opening a screen; it just has nothing to show.
      debugPrint('[$logTag] could not read the cache: $error');
      return const [];
    }
  }

  Future<T?> byId(String id) async {
    for (final reading in await all()) {
      if (idOf(reading) == id) return reading;
    }
    return null;
  }

  /// Adds or replaces a reading, keeping the newest [_keep].
  Future<void> save(T reading) async {
    try {
      // Filtered into a new list rather than mutated: `all()` returns `const []` when the
      // cache is empty, and removeWhere on an immutable list throws — which would be every
      // first save on a fresh install.
      final existing = await all();
      final id = idOf(reading);
      final readings = [
        reading,
        for (final r in existing)
          if (idOf(r) != id) r,
      ].take(_keep).toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        storageKey,
        jsonEncode({
          'v': version,
          'readings': [for (final r in readings) encode(r)],
        }),
      );
    } catch (error) {
      // The reading is already on screen; failing to cache it costs only the ability to
      // reopen it later, which is not worth interrupting the user for.
      debugPrint('[$logTag] could not cache the reading: $error');
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (error) {
      debugPrint('[$logTag] could not clear the cache: $error');
    }
  }
}

class PalmReadingStore extends ReadingStore<PalmReading> {
  const PalmReadingStore();

  @override
  String get storageKey => 'astrolok.palm_readings';

  /// Bumped to 2 when the invocation and blessing landed. A version 1 payload is simply dropped
  /// — the reading is a few days old at most, and half-parsing one into a screen that now
  /// expects an opening line is worse than an empty history.
  @override
  int get version => 2;

  @override
  String get logTag => 'palm';

  @override
  PalmReading? parse(Object? raw) => PalmReading.fromServer(raw);

  @override
  Map<String, dynamic> encode(PalmReading reading) => reading.toJson();

  @override
  String idOf(PalmReading reading) => reading.id;
}

class FaceReadingStore extends ReadingStore<FaceReading> {
  const FaceReadingStore();

  @override
  String get storageKey => 'astrolok.face_readings';

  @override
  int get version => 1;

  @override
  String get logTag => 'face';

  @override
  FaceReading? parse(Object? raw) => FaceReading.fromServer(raw);

  @override
  Map<String, dynamic> encode(FaceReading reading) => reading.toJson();

  @override
  String idOf(FaceReading reading) => reading.id;
}
