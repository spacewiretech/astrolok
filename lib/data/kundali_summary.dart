import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'entitlement.dart';
import 'models/kundali.dart';
import 'providers.dart';

/// What a refresh learned.
///
/// The distinction [none] draws from [unknown] is the whole point of this type. "The server says
/// this account has no kundali" sends the user to the form; "I could not find out" must not,
/// because the form invites a re-cast and a re-cast spends one of the account's regenerations.
/// Before this existed both were a null `KundaliSummary?`, and every caller read the second as the
/// first — so a push tapped on a cold start, with the session still resolving, offered the form to
/// someone whose kundali was sitting there half-written.
enum KundaliRefreshOutcome { found, none, unknown }

@immutable
class KundaliRefresh {
  const KundaliRefresh.found(KundaliSummary this.summary) : outcome = KundaliRefreshOutcome.found;
  const KundaliRefresh.none()
      : summary = null,
        outcome = KundaliRefreshOutcome.none;
  const KundaliRefresh.unknown()
      : summary = null,
        outcome = KundaliRefreshOutcome.unknown;

  final KundaliRefreshOutcome outcome;

  /// The summary, when there is one. Null for both [none] and [unknown] — check [outcome], never
  /// this, to tell those apart.
  final KundaliSummary? summary;

  /// The server said this account has no live kundali. The only outcome the form belongs on.
  bool get isNone => outcome == KundaliRefreshOutcome.none;

  /// Could not find out. Show what is cached, or try again — decide nothing on it.
  bool get isUnknown => outcome == KundaliRefreshOutcome.unknown;
}

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

  /// Whether a null [state] is an answer — the server saying this account has no live kundali —
  /// rather than simply not having asked yet. Without this the two are indistinguishable, and
  /// "I don't know" reads as "there is none".
  bool _answered = false;

  @override
  Future<KundaliSummary?> build() async {
    _userId = ref.watch(entitlementProvider.select((user) => user?.id));
    _lastRefresh = null;
    _answered = false;
    final userId = _userId;
    if (userId == null) return null;
    final cached = await ref.read(kundaliStoreProvider).readSummary(userId);
    // A cached summary is an answer; an empty cache is not.
    _answered = cached != null;
    return cached;
  }

  /// [state] as an outcome: what is known right now, and whether it is known at all.
  KundaliRefresh get _current {
    final value = state.valueOrNull;
    if (value != null) return KundaliRefresh.found(value);
    return _answered ? const KundaliRefresh.none() : const KundaliRefresh.unknown();
  }

  /// Asks the server. [surface] `waiting` also tells it the waiting screen was opened.
  ///
  /// Never reports [KundaliRefresh.none] on a guess: every path that fails to find out — no
  /// session yet, the account changing mid-flight, a request that threw — reports
  /// [KundaliRefresh.unknown] instead, so a caller cannot mistake a failure for an empty account.
  Future<KundaliRefresh> refresh({bool force = false, String surface = 'home'}) async {
    final userId = _userId ?? ref.read(entitlementProvider)?.id;
    if (userId == null) return const KundaliRefresh.unknown();

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
      return _current;
    }
    _lastRefresh = DateTime.now();

    try {
      final fresh = await ref.read(kundaliRepositoryProvider).status(surface: surface);
      // Signed in as someone else while this was in flight: this answer is about the wrong
      // account, so it is not an answer about this one.
      if (_userId != userId) return const KundaliRefresh.unknown();
      _answered = true;
      state = AsyncData(fresh);
      unawaited(ref.read(kundaliStoreProvider).saveSummary(userId, fresh));
      return fresh == null ? const KundaliRefresh.none() : KundaliRefresh.found(fresh);
    } catch (error) {
      debugPrint('[kundali] status refresh failed: $error');
      // Keep what was already known. A refresh that could not reach the server says nothing about
      // whether the account has a kundali, so it must not answer that question.
      return _current;
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
    _answered = true;
    state = AsyncData(summary);
    if (userId != null) unawaited(ref.read(kundaliStoreProvider).saveSummary(userId, summary));
  }
}

final kundaliSummaryProvider =
    AsyncNotifierProvider<KundaliSummaryNotifier, KundaliSummary?>(KundaliSummaryNotifier.new);
