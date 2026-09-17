import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/kundali.dart';

/// The last known kundali, on the device.
///
/// Two things are kept per account: the summary, so the Home card paints its countdown before the
/// network answers, and the revealed reading, so the report opens instantly and offline once it has
/// been seen. Nothing is kept that the server has not already revealed — the reading is only ever
/// written here after `report` returned it.
///
/// `shared_preferences`, like the palm and face readings: personal, but not a credential.
class KundaliStore {
  const KundaliStore();

  static const _version = 1;

  String _summaryKey(String userId) => 'astrolok.kundali.summary.$userId';
  String _readingKey(String userId) => 'astrolok.kundali.reading.$userId';

  Future<KundaliSummary?> readSummary(String userId) async {
    final map = await _read(_summaryKey(userId));
    return map == null ? null : KundaliSummary.fromServer(map);
  }

  Future<void> saveSummary(String userId, KundaliSummary? summary) =>
      summary == null ? _remove(_summaryKey(userId)) : _write(_summaryKey(userId), summary.toJson());

  /// The cached reading, but only if it belongs to [kundaliId] — a regeneration makes the old one
  /// a different chart.
  Future<KundaliReading?> readReading(String userId, String kundaliId) async {
    final map = await _read(_readingKey(userId));
    final reading = map == null ? null : KundaliReading.fromServer(map);
    return reading?.id == kundaliId ? reading : null;
  }

  Future<void> saveReading(String userId, KundaliReading reading) => _write(_readingKey(userId), reading.toJson());

  Future<Map<String, Object?>?> _read(String key) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['v'] != _version || decoded['data'] is! Map) return null;
      return (decoded['data'] as Map).cast<String, Object?>();
    } catch (error) {
      debugPrint('[kundali] could not read the cache: $error');
      return null;
    }
  }

  Future<void> _write(String key, Map<String, Object?> data) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, jsonEncode({'v': _version, 'data': data}));
    } catch (error) {
      debugPrint('[kundali] could not write the cache: $error');
    }
  }

  Future<void> _remove(String key) async {
    try {
      await (await SharedPreferences.getInstance()).remove(key);
    } catch (error) {
      debugPrint('[kundali] could not clear the cache: $error');
    }
  }
}
