import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/astro_message.dart';
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

  /// Drops one entry, if it is here.
  ///
  /// Without this, something the user deleted on the server would come back from the cache on the
  /// next cold start — which reads as the deletion having silently failed.
  Future<void> remove(String id) async {
    try {
      final existing = await all();
      final kept = [
        for (final reading in existing)
          if (idOf(reading) != id) reading,
      ];
      if (kept.length == existing.length) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        storageKey,
        jsonEncode({
          'v': version,
          'readings': [for (final r in kept) encode(r)],
        }),
      );
    } catch (error) {
      debugPrint('[$logTag] could not drop the cached entry: $error');
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

/// The conversations, cached so a cold start paints instantly and yesterday's counsel is still
/// readable with no signal.
///
/// One entry per thread, each holding its whole transcript — not `ReadingStore<AstroMessage>`
/// where each turn is an entry: `_keep` is a non-overridable `static const` 10, which as "ten
/// conversations" is generous and as "ten messages" would silently eat the eleventh. The cost is
/// re-encoding a transcript on every turn, which at a few tens of kilobytes is not worth a second
/// storage class.
///
/// The ten newest conversations are cached; older ones still open, they just wait for the server
/// the first time. That matches [ReadingImageStore], which keeps ten of everything else.
class ChatThreadStore extends ReadingStore<ChatThread> {
  const ChatThreadStore();

  @override
  String get storageKey => 'astrolok.chat_thread';

  /// Bumped to 2 when the conversation became conversations. A version 1 payload held a single
  /// thread under a fixed id and no verdicts, so it is dropped whole rather than half-parsed into
  /// a sidebar that would show one untitled row. The transcript is not lost — it is on the
  /// server, and the first `chat-history` call brings it back with its real thread.
  @override
  int get version => 2;

  @override
  String get logTag => 'chat';

  @override
  ChatThread? parse(Object? raw) => ChatThread.fromServer(raw);

  @override
  Map<String, dynamic> encode(ChatThread thread) => thread.toJson();

  @override
  String idOf(ChatThread thread) => thread.id;

  /// One conversation, or null when it has not been cached.
  Future<ChatThread?> load(String id) => byId(id);

  /// Every cached conversation, newest first, as the sidebar lists them.
  ///
  /// What lets the drawer show something on a cold start instead of a spinner. `all()` already
  /// returns them newest-first — `save` prepends — so this only drops the ones with nothing to
  /// preview.
  Future<List<ChatThreadSummary>> recent() async => [
        for (final thread in await all())
          if (!thread.isEmpty) thread.summary,
      ];
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
