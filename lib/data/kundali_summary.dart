import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'entitlement.dart';
import 'models/kundali.dart';
import 'providers.dart';

/// The signed-in account's kundali summary, shared by the Home card, the gate and the waiting
/// screen so all three agree on the countdown.
///
/// The cached copy paints first; a network refresh follows. Refreshes are throttled to one a minute
/// unless forced, because Home is every back-navigation's destination and those arrive in bursts.
/// A failed refresh keeps what was already known — a countdown that vanishes on a flaky connection
/// is worse than a slightly stale one.
///
/// Keyed on the account, so signing in as someone else starts from nothing rather than from the
/// last person's chart.
class KundaliSummaryNotifier extends AsyncNotifier<KundaliSummary?> {
  static const _minRefreshGap = Duration(minutes: 1);

  DateTime? _lastRefresh;
  String? _userId;

  @override
  Future<KundaliSummary?> build() async {
    _userId = ref.watch(entitlementProvider.select((user) => user?.id));
    _lastRefresh = null;
    final userId = _userId;
    if (userId == null) return null;
    return ref.read(kundaliStoreProvider).readSummary(userId);
  }

  /// Asks the server. [surface] `waiting` also tells it the waiting screen was opened.
  Future<KundaliSummary?> refresh({bool force = false, String surface = 'home'}) async {
    final userId = _userId ?? ref.read(entitlementProvider)?.id;
    if (userId == null) return null;

    // Let the cached read finish first. Otherwise a screen that refreshes on its first frame can
    // have its fresh answer overwritten a moment later when the slower cache read lands — a
    // countdown that appears and then vanishes.
    try {
      await future;
    } catch (_) {
      // A failed cache read is not a reason to skip the network.
    }

    final last = _lastRefresh;
    if (!force && last != null && DateTime.now().difference(last) < _minRefreshGap) {
      return state.valueOrNull;
    }
    _lastRefresh = DateTime.now();

    try {
      final fresh = await ref.read(kundaliRepositoryProvider).status(surface: surface);
      if (_userId != userId) return null;
      state = AsyncData(fresh);
      unawaited(ref.read(kundaliStoreProvider).saveSummary(userId, fresh));
      return fresh;
    } catch (error) {
      debugPrint('[kundali] status refresh failed: $error');
      return state.valueOrNull;
    }
  }

  /// Takes a summary the app already holds — the answer to a request, or a reveal just viewed.
  Future<void> set(KundaliSummary summary) async {
    try {
      await future;
    } catch (_) {
      // As in [refresh]: the cache read must not land on top of this.
    }
    final userId = _userId ?? ref.read(entitlementProvider)?.id;
    state = AsyncData(summary);
    if (userId != null) unawaited(ref.read(kundaliStoreProvider).saveSummary(userId, summary));
  }
}

final kundaliSummaryProvider =
    AsyncNotifierProvider<KundaliSummaryNotifier, KundaliSummary?>(KundaliSummaryNotifier.new);
