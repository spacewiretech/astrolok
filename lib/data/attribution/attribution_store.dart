import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'attribution.dart';

/// What the app remembers about where this install came from.
///
/// `shared_preferences`, not the secure store: none of this is a credential, and the analytics
/// context next door already keeps the install id and first-launch timestamps here under the same
/// `astrolok.` namespace.
///
/// ## The ordering rule that makes this safe
///
/// Everything here is written **before** the network call it describes, never after. The app is
/// routinely killed mid-flight — the UPI hand-off does it on every payment — and an attribution
/// recorded only in memory would be lost by exactly the users whose first session was interesting
/// enough to interrupt. Writing first means the worst case is a claim that is retried, and the
/// claim endpoint is idempotent precisely so that retrying costs nothing.
class AttributionStore {
  AttributionStore([SharedPreferencesAsync? preferences]) : _injected = preferences;

  final SharedPreferencesAsync? _injected;
  SharedPreferencesAsync? _resolved;

  /// Built on first use, never in the constructor.
  ///
  /// `SharedPreferencesAsync()` throws outright when no platform implementation is registered,
  /// which is the normal state under `flutter test`. The service that owns this store is a
  /// top-level `final`, so constructing it eagerly would make merely *touching* that global throw
  /// in any widget test that reaches the identity hook — which is how this was first found.
  ///
  /// Every caller below already runs inside a try/catch, so a construction that throws here is
  /// indistinguishable from storage that will not open: the store reports "nothing known", and
  /// the app carries on unattributed rather than not carrying on at all.
  SharedPreferencesAsync get _preferences =>
      _injected ?? (_resolved ??= SharedPreferencesAsync());

  /// The attribution waiting to be sent to the backend. Cleared only when the backend has given a
  /// terminal answer — accepted, refused, or "that code does not exist" — never on a transport
  /// failure, which is what makes an offline first launch lossless.
  static const _pendingKey = 'astrolok.attribution_pending';

  /// The first attribution ever resolved on this install. Write-once.
  static const _firstTouchKey = 'astrolok.attribution_first_touch';

  /// Set once the Play Install Referrer has been read. The API returns the same string for the
  /// life of the install, so re-reading it every launch would re-resolve an attribution that
  /// cannot have changed and bind a service connection for nothing.
  ///
  /// This is the *only* source of a referral code on a fresh install — there is no web click to
  /// fall back on — which is why it is read on every first launch rather than only when a
  /// referral is suspected.
  static const _referrerReadKey = 'astrolok.attribution_referrer_read';

  /// Set once a claim has reached a terminal answer, so a signed-in user who opens the app daily
  /// does not ask the backend about a referral that has already been settled.
  static const _claimSettledKey = 'astrolok.attribution_claim_settled';

  Future<Attribution?> readPending() => _read(_pendingKey);

  Future<void> writePending(Attribution attribution) =>
      _write(_pendingKey, attribution);

  Future<void> clearPending() => _guard(() => _preferences.remove(_pendingKey));

  Future<Attribution?> readFirstTouch() => _read(_firstTouchKey);

  /// Records the first touch, and answers whether this call was the one that set it.
  ///
  /// The check and the write are not atomic, and deliberately are not: the only writer is the
  /// attribution service, which resolves once per launch on a single isolate. The guarantee that
  /// actually matters is enforced by the backend, where the `first_*` columns are written by an
  /// insert that does nothing on conflict — this is the local convenience copy, and the backend
  /// is the record.
  Future<bool> recordFirstTouchIfAbsent(Attribution attribution) async {
    final existing = await readFirstTouch();
    if (existing != null) return false;
    await _write(_firstTouchKey, attribution);
    return true;
  }

  Future<bool> hasReadInstallReferrer() => _flag(_referrerReadKey);

  Future<void> markInstallReferrerRead() => _setFlag(_referrerReadKey);

  Future<bool> isClaimSettled() => _flag(_claimSettledKey);

  Future<void> markClaimSettled() => _setFlag(_claimSettledKey);

  /// Clears everything this install remembers about attribution.
  ///
  /// Not called on sign-out — attribution is a property of the *install*, not of the account, and
  /// wiping it when a user signs out would make the next sign-in on the same handset look like a
  /// fresh organic acquisition. Exists for tests and for a future "forget me" control.
  @visibleForTesting
  Future<void> clearAll() => _guard(() async {
        for (final key in [
          _pendingKey,
          _firstTouchKey,
          _referrerReadKey,
          _claimSettledKey,
        ]) {
          await _preferences.remove(key);
        }
      });

  Future<Attribution?> _read(String key) async {
    try {
      final raw = await _preferences.getString(key);
      if (raw == null || raw.isEmpty) return null;
      return Attribution.fromJson(jsonDecode(raw));
    } catch (error) {
      // A payload written by an older build, or storage that will not open. Neither is worth
      // failing a launch over, and both resolve to "we know nothing", which is a valid state.
      debugPrint('[attribution] could not read $key: $error');
      return null;
    }
  }

  Future<void> _write(String key, Attribution attribution) => _guard(
        () => _preferences.setString(key, jsonEncode(attribution.toJson())),
      );

  Future<bool> _flag(String key) async {
    try {
      return await _preferences.getBool(key) ?? false;
    } catch (error) {
      debugPrint('[attribution] could not read $key: $error');
      // Reported as "already done" on a storage failure. The alternative — defaulting to false —
      // would make a device with broken preferences re-read the install referrer on every single
      // launch, which is the noisier and more expensive way to be wrong.
      return true;
    }
  }

  Future<void> _setFlag(String key) => _guard(() => _preferences.setBool(key, true));

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('[attribution] write failed: $error');
    }
  }
}
