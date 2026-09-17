import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/entitlement.dart';
import '../../data/providers.dart';
import '../../data/repositories/cancellation_feedback_repository.dart';

/// The reasons offered, in the order drawn. Keys match the server's `CANCEL_REASONS`.
const cancellationReasons = <(String, String)>[
  ('too_expensive', "It's too expensive"),
  ('not_accurate', "The readings didn't feel accurate"),
  ('not_useful', "I didn't find it useful"),
  ('only_exploring', 'I was only trying it out'),
  ('payment_trouble', 'I had trouble with payment or autopay'),
  ('technical_issue', "Something wasn't working"),
  ('found_alternative', "I'm using another app"),
  ('other', 'Something else'),
];

@immutable
class CancellationReasonState {
  const CancellationReasonState({this.reason, this.comment = '', this.busy = false, this.done = false, this.error});

  final String? reason;
  final String comment;
  final bool busy;

  /// Answered (or dismissed). The screen thanks them and offers a way on.
  final bool done;
  final String? error;

  bool get canSubmit => reason != null && !busy;

  CancellationReasonState copyWith({String? reason, String? comment, bool? busy, bool? done, String? error, bool clearError = false}) =>
      CancellationReasonState(
        reason: reason ?? this.reason,
        comment: comment ?? this.comment,
        busy: busy ?? this.busy,
        done: done ?? this.done,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Keyed by the push's notification id, when a push opened it.
class CancellationReasonViewModel extends AutoDisposeFamilyNotifier<CancellationReasonState, String?> {
  @override
  CancellationReasonState build(String? notificationId) {
    final user = ref.read(entitlementProvider);
    analytics.track(Ev.cancellationReasonViewed, {
      P.source: notificationId == null ? 'in_app' : 'push',
      P.notificationId: ?notificationId,
      P.entitled: user?.entitled,
    });
    return const CancellationReasonState();
  }

  void choose(String reason) => state = state.copyWith(reason: reason, clearError: true);

  void setComment(String comment) => state = state.copyWith(comment: comment);

  Future<void> submit() async {
    final reason = state.reason;
    if (reason == null || state.busy) return;
    final comment = state.comment.trim();
    await _send(reason, comment.isEmpty ? null : comment);
  }

  Future<void> dismiss() async {
    if (state.busy) return;
    analytics.track(Ev.cancellationReasonDismissed, {P.notificationId: ?arg});
    await _send('dismissed', null);
  }

  Future<void> _send(String reason, String? comment) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final recorded = await ref.read(cancellationFeedbackRepositoryProvider).submit(
            reason: reason,
            comment: comment,
            source: arg == null ? 'in_app' : 'push',
            notificationId: arg,
          );
      if (reason != 'dismissed') {
        analytics.track(Ev.cancellationReasonSubmitted, {
          P.reason: reason,
          P.hasComment: comment != null,
          P.recorded: recorded,
          P.wasInTrial: ref.read(entitlementProvider)?.currentPeriodEnd == null,
          P.notificationId: ?arg,
        });
      }
      state = state.copyWith(busy: false, done: true);
    } on NoCancelledPlanException {
      // Nothing to attach the answer to — they re-subscribed, or opened a stale push. Thank them
      // anyway; there is nothing for them to fix.
      state = state.copyWith(busy: false, done: true);
    } on CancellationFeedbackException catch (error) {
      state = state.copyWith(busy: false, error: error.message);
    } catch (_) {
      state = state.copyWith(busy: false, error: 'Could not send that. Please try again.');
    }
  }
}

final cancellationReasonViewModelProvider =
    AutoDisposeNotifierProviderFamily<CancellationReasonViewModel, CancellationReasonState, String?>(
  CancellationReasonViewModel.new,
);
