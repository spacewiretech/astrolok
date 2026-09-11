import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/env.dart';
import '../repositories/app_config_repository.dart';

/// Reads `app_config` from Supabase, with a disk cache in front of it.
///
/// The splash waits on this, so it must never hang on a bad network: a cached copy is served
/// immediately when it is fresh, a stale copy is served when the fetch fails, and
/// [shippedAppConfig] — the env rows over the compiled defaults — catches the very first launch
/// offline. Every exit below merges onto that same base, so no two paths can disagree about
/// what a key the server never sent falls back to.
class SupabaseAppConfigRepository implements AppConfigRepository {
  SupabaseAppConfigRepository(this._client, {this.ttl = const Duration(hours: 6)});

  final SupabaseClient _client;
  final Duration ttl;

  static const _cacheKey = 'astrolok.app_config';
  static const _cacheAtKey = 'astrolok.app_config_at';

  /// Only public rows are readable with the anon key; RLS enforces that server-side, so a
  /// private row simply will not appear here.
  static const _timeout = Duration(seconds: 8);

  Set<String> _remoteKeys = const {};

  @override
  Set<String> get remoteKeys => _remoteKeys;

  @override
  Future<Map<String, String>> load({bool force = false, Duration? maxAge}) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _readCacheRows(prefs);
    if (cached != null) _remoteKeys = cached.keys.toSet();

    if (!force && cached != null && _isFresh(prefs, maxAge ?? ttl)) {
      return {...shippedAppConfig, ...cached};
    }

    try {
      final rows = await _client
          .from('app_config')
          .select('key, value')
          .timeout(_timeout);

      final config = <String, String>{
        for (final row in rows as List<dynamic>)
          (row as Map<String, dynamic>)['key'] as String:
              row['value']?.toString() ?? '',
      };

      await prefs.setString(_cacheKey, jsonEncode(config));
      await prefs.setInt(_cacheAtKey, DateTime.now().millisecondsSinceEpoch);
      _remoteKeys = config.keys.toSet();
      return {...shippedAppConfig, ...config};
    } catch (error) {
      debugPrint(
        'app_config fetch failed, using '
        '${cached == null ? 'the shipped config' : 'a stale cache'}: $error',
      );
      // Stale beats nothing, and nothing still beats blocking the splash.
      return cached == null ? shippedAppConfig : {...shippedAppConfig, ...cached};
    }
  }

  /// The env rows under the cached config, with no client and no network.
  ///
  /// Exists for exactly one caller: the boot sequence, which needs the Mixpanel token before
  /// `runApp` and cannot wait on a fetch to get it. Static because at that point there may be no
  /// `SupabaseClient` to construct a repository around — `Supabase.initialize` is allowed to have
  /// failed, and a checkout with no `app.env` never called it at all.
  ///
  /// Deliberately **not** merged with [defaultAppConfig], unlike every other read path here. The
  /// caller's rule is that a *missing* `mixpanel_token` means "no token yet, queue the events",
  /// and the compiled map has no entry for that key precisely so absence stays meaningful. The
  /// env rows are safe to merge because a key absent from both the file and the cache is still
  /// absent from the result.
  static Future<Map<String, String>> readCachedConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rows = _decodeRows(prefs.getString(_cacheKey));
      return {...Env.appConfigFallback, ...?rows};
    } catch (error) {
      debugPrint('app_config cache read failed: $error');
      return Env.appConfigFallback;
    }
  }

  /// Whether the cache is younger than [window] — [ttl] for most callers, something shorter for
  /// a screen that has just promised the user a dashboard edit will show up.
  bool _isFresh(SharedPreferences prefs, Duration window) {
    final at = prefs.getInt(_cacheAtKey);
    if (at == null) return false;
    final age = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(at));
    return age < window;
  }

  /// The cached rows exactly as the server sent them, with nothing merged in.
  ///
  /// Raw rather than merged so that [load] can both build the merged map *and* answer
  /// [remoteKeys] from the same read — the two would drift if the merge happened here.
  Map<String, String>? _readCacheRows(SharedPreferences prefs) =>
      _decodeRows(prefs.getString(_cacheKey));

  static Map<String, String>? _decodeRows(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries) entry.key: entry.value.toString(),
      };
    } catch (_) {
      return null;
    }
  }
}

/// Used until Supabase is configured, and by tests.
class FakeAppConfigRepository implements AppConfigRepository {
  const FakeAppConfigRepository([this.overrides = const {}]);

  final Map<String, String> overrides;

  @override
  Future<Map<String, String>> load({bool force = false, Duration? maxAge}) async =>
      {...shippedAppConfig, ...overrides};

  /// The overrides stand in for what a server served. The env rows and the compiled defaults
  /// are not remote by definition, so they are not counted here.
  @override
  Set<String> get remoteKeys => overrides.keys.toSet();
}
