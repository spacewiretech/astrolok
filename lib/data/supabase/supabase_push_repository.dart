import 'package:flutter/foundation.dart';

import '../repositories/push_repository.dart';
import 'edge_functions.dart';
import 'session_store.dart';

/// Push registration against the `push-token` Edge Function.
///
/// Nothing here throws. Registration happens behind the user's back, on launch and on resume, and
/// the only consequence of a failure is that the next attempt tries again.
class SupabasePushRepository implements PushRepository {
  SupabasePushRepository(this._functions, this._sessions);

  final EdgeFunctions _functions;
  final SessionStore _sessions;

  @override
  Future<bool> register({
    required String token,
    required String platform,
    int? appBuild,
    bool? notificationsAuthorized,
  }) async {
    final bearer = await _sessions.readToken();
    // Signed out. Not a failure: the device token is bound to a session, so there is nothing to
    // bind it to until the next sign-in resolves a user and asks again.
    if (bearer == null) return false;

    try {
      await _functions.call(
        'push-token',
        bearerToken: bearer,
        body: {
          'token': token,
          'platform': platform,
          'app_build': ?appBuild,
          'notifications_authorized': ?notificationsAuthorized,
        },
      );
      return true;
    } catch (error) {
      debugPrint('[push] could not register the device token: $error');
      return false;
    }
  }
}
