import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_user.dart';
import '../models/birth_chart.dart';

/// Holds the session token issued by `verify-otp`.
///
/// The token is a bearer credential for this account, so it belongs in the Keychain/Keystore
/// rather than shared preferences. The cached user beside it is only a convenience for
/// rendering before `me` responds — the server is always the authority on who is signed in.
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'astrolok.session_token';
  static const _userKey = 'astrolok.cached_user';

  /// Bumped whenever the cached shape changes. An older payload is dropped rather than
  /// half-parsed, so a build that adds a field cannot inherit a stale entitlement from one
  /// that did not have it.
  static const _version = 1;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> save({required String token, required AppUser user}) async {
    await _storage.write(key: _tokenKey, value: token);
    await _cacheUser(user);
  }

  Future<void> _cacheUser(AppUser user) => _storage.write(
        key: _userKey,
        value: jsonEncode({
          'v': _version,
          'id': user.id,
          'phone': user.phone,
          'name': user.name,
          // Stored as YYYY-MM-DD, matching the wire format, so the cached copy cannot drift
          // by a day the way an ISO instant would across a timezone change.
          'birthDate':
              user.birthDate == null ? null : AppUser.formatBirthDate(user.birthDate!),
          'paymentType': user.paymentType.name,
          'trialEndsAt': user.trialEndsAt?.toIso8601String(),
          'currentPeriodEnd': user.currentPeriodEnd?.toIso8601String(),
          'entitled': user.entitled,
          'trialAvailable': user.trialAvailable,
          'chatLanguage': user.chatLanguage,
          'birthTime': user.birthTime,
          // In the server's own shape, so it reads back through the same parser as a fresh one.
          'chart': user.chart?.toJson(),
          // Server shape too. The paywall prices itself from this, so an offline relaunch must not
          // fall back to the configured price for an account on the other side of the split.
          'plan': user.plan?.toJson(),
        }),
      );

  Future<void> cacheUser(AppUser user) => _cacheUser(user);

  /// The last known user, with entitlement re-derived from the stored dates.
  ///
  /// The stored `entitled` flag was true at the moment it was written, which says nothing about
  /// now — without [AppUser.recomputeOffline] a trial that ended overnight would keep opening
  /// the app for as long as the device stayed offline.
  Future<AppUser?> readCachedUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['v'] != _version) {
        await _storage.delete(key: _userKey);
        return null;
      }

      return AppUser(
        id: map['id'] as String,
        phone: map['phone'] as String? ?? '',
        name: map['name'] as String? ?? '',
        birthDate: AppUser.parseBirthDate(map['birthDate']),
        paymentType: PaymentType.parse(map['paymentType']),
        trialEndsAt: DateTime.tryParse(map['trialEndsAt'] as String? ?? ''),
        currentPeriodEnd: DateTime.tryParse(map['currentPeriodEnd'] as String? ?? ''),
        entitled: map['entitled'] as bool? ?? false,
        // Absent in a cache written before this field existed. Left null so [isTrialAvailable]
        // falls back to the dates rather than asserting an answer — deliberately not a reason to
        // bump `_version`, which would sign an offline user out over a field that has a safe
        // default.
        trialAvailable: map['trialAvailable'] as bool?,
        // Absent in an older cache, and null is already the correct answer for that — "follow
        // the configured default". Another field that must not bump `_version`: signing an
        // offline user out over which language Astro greets them in would be a poor trade.
        chatLanguage: map['chatLanguage'] as String?,
        // Both absent in an older cache, where null is the honest answer — not known here yet —
        // and the next `me` fills them in. Neither is a reason to bump `_version` either.
        birthTime: AppUser.parseBirthTime(map['birthTime']),
        chart: BirthChart.fromServer(map['chart']),
        // Absent in a cache written before the price split, where null — the configured price — is
        // the right answer. Not a reason to bump `_version` either.
        plan: UserPlan.fromServer(map['plan']),
      ).recomputeOffline();
    } catch (_) {
      // A cache written by an older build is not worth crashing over.
      await clear();
      return null;
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }
}
