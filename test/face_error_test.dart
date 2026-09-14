import 'dart:typed_data';

import 'package:astrolok/data/models/face_reading.dart';
import 'package:astrolok/data/models/palm_reading.dart' show PalmFocus;
import 'package:astrolok/data/repositories/face_repository.dart';
import 'package:astrolok/data/supabase/edge_functions.dart';
import 'package:astrolok/data/supabase/session_store.dart';
import 'package:astrolok/data/supabase/supabase_face_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two dead ends of the face endpoint, and that the app keeps them apart.
///
/// The full mapping is covered for palms in `palm_error_test.dart`; the face repository is a
/// mirror of it. What is worth pinning here is the pair that look alike and are not: the daily
/// limit lifts tomorrow, the trial allowance lifts when the trial ends, and the capture screen
/// explains the second with a popup.
void main() {
  late _FakeEdgeFunctions functions;
  late SupabaseFaceRepository repository;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'astrolok.session_token': 'a-valid-token',
    });
    functions = _FakeEdgeFunctions();
    repository = SupabaseFaceRepository(functions, SessionStore());
  });

  Future<FaceReading> read() =>
      repository.read(image: Uint8List(64), focus: PalmFocus.love);

  test('trial_limit_reached is its own dead end', () async {
    functions.error = const EdgeError(
      'trial_limit_reached',
      'Trial users can scan their face only once.',
    );

    await expectLater(
      read(),
      throwsA(
        isA<FaceTrialLimitException>().having(
          (e) => e.message,
          'message',
          'Trial users can scan their face only once.',
        ),
      ),
    );
  });

  test('limit_reached is still the daily limit', () async {
    functions.error = const EdgeError('limit_reached', "You've used all 10 today.");
    await expectLater(read(), throwsA(isA<FaceLimitReachedException>()));
  });
}

class _FakeEdgeFunctions implements EdgeFunctions {
  EdgeError? error;

  @override
  Future<Map<String, dynamic>> call(
    String name, {
    Map<String, dynamic>? body,
    String? bearerToken,
    bool delete = false,
    Duration? timeout,
  }) async {
    final failure = error;
    if (failure != null) throw failure;
    return const {};
  }
}
