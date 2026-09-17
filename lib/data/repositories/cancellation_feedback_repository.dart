/// Why someone cancelled, sent to the `cancellation-feedback` Edge Function.
///
/// Works for an account that is no longer entitled — a trial user loses access the minute they
/// cancel, and that is exactly whose answer is wanted.
abstract interface class CancellationFeedbackRepository {
  /// Records [reason] (one of the server's `CANCEL_REASONS`) against the account's most recently
  /// cancelled plan. Returns false when an answer was already recorded — not an error.
  Future<bool> submit({
    required String reason,
    String? comment,
    String source = 'push',
    String? notificationId,
  });
}

class CancellationFeedbackException implements Exception {
  const CancellationFeedbackException(this.message);

  final String message;

  @override
  String toString() => 'CancellationFeedbackException: $message';
}

/// There is no cancelled plan on this account to tell us about.
class NoCancelledPlanException extends CancellationFeedbackException {
  const NoCancelledPlanException(super.message);
}

/// Where there is no backend: accepts the answer and forgets it, so the screen stays walkable.
class FakeCancellationFeedbackRepository implements CancellationFeedbackRepository {
  const FakeCancellationFeedbackRepository();

  @override
  Future<bool> submit({required String reason, String? comment, String source = 'push', String? notificationId}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return true;
  }
}
