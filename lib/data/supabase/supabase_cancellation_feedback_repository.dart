import '../repositories/cancellation_feedback_repository.dart';
import 'edge_functions.dart';
import 'session_store.dart';

class SupabaseCancellationFeedbackRepository implements CancellationFeedbackRepository {
  SupabaseCancellationFeedbackRepository(this._functions, this._sessions);

  final EdgeFunctions _functions;
  final SessionStore _sessions;

  @override
  Future<bool> submit({
    required String reason,
    String? comment,
    String source = 'push',
    String? notificationId,
  }) async {
    final token = await _sessions.readToken();
    if (token == null) throw const CancellationFeedbackException('Please sign in again.');

    try {
      final data = await _functions.call(
        'cancellation-feedback',
        bearerToken: token,
        body: {
          'reason': reason,
          'comment': ?comment,
          'source': source,
          'notification_id': ?notificationId,
        },
      );
      return data['recorded'] == true;
    } on EdgeError catch (e) {
      throw switch (e.code) {
        'not_found' => NoCancelledPlanException(e.message),
        _ => CancellationFeedbackException(e.message),
      };
    }
  }
}
