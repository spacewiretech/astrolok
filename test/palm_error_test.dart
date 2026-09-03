import 'dart:typed_data';

import 'package:astrolok/data/models/palm_reading.dart';
import 'package:astrolok/data/repositories/palm_repository.dart';
import 'package:astrolok/data/supabase/edge_functions.dart';
import 'package:astrolok/data/supabase/session_store.dart';
import 'package:astrolok/data/supabase/supabase_palm_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every way the reading endpoint can fail, and what the app turns it into.
///
/// The mapping matters because the four outcomes are handled very differently on screen — a
/// rejection sends the user back to the camera, a failure keeps their photo and offers a
/// retry, a lapsed subscription goes to the paywall — so getting one wrong strands them.
void main() {
  late _FakeEdgeFunctions functions;
  late SupabasePalmRepository repository;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'astrolok.session_token': 'a-valid-token',
    });
    functions = _FakeEdgeFunctions();
    repository = SupabasePalmRepository(functions, SessionStore());
  });

  Future<PalmReading> read() =>
      repository.read(image: Uint8List(64), focus: PalmFocus.love);

  test('a good response parses into a reading', () async {
    functions.response = {
      'reading': {
        'id': 'r1',
        'created_at': '2026-09-04T10:00:00Z',
        'focus': 'love',
        'headline': 'A warm hand.',
        'lines': [
          {
            'key': 'heart',
            'title': 'Heart Line',
            'status': 'Strong',
            'summary': 'Warm.',
            'detail': 'A paragraph.',
          },
        ],
      },
    };

    final reading = await read();

    expect(reading.id, 'r1');
    expect(reading.lines, hasLength(1));
    // The image is sent base64-encoded under `image`, with the focus alongside it.
    expect(functions.lastBody!['focus'], 'love');
    expect(functions.lastBody!['image'], isA<String>());
    expect(functions.lastName, 'palm-reading');
  });

  test('waits far longer than the default, because the model does', () async {
    functions.response = {'reading': null};
    await expectLater(read(), throwsA(isA<PalmUnavailableException>()));

    // The 20s default is generous for every other function here and far too short for this
    // one. Just past the function's own 70s ceiling, so an orderly server-side give-up gets to
    // return its own message rather than being cut off and reported as a timeout.
    expect(functions.lastTimeout, const Duration(seconds: 75));
  });

  group('error codes map to the right outcome', () {
    test('no_palm is a rejection, not a failure', () async {
      functions.error = const EdgeError('no_palm', 'That photo is a bit too dark.');

      // The specific reason survives: "a bit too dark" tells the user what to change, where a
      // generic "no palm" would send them to retake the same photo the same way.
      await expectLater(
        read(),
        throwsA(
          isA<NoPalmDetectedException>().having(
            (e) => e.message,
            'message',
            'That photo is a bit too dark.',
          ),
        ),
      );
    });

    test('limit_reached', () async {
      functions.error = const EdgeError('limit_reached', "You've used all 10 today.");
      await expectLater(read(), throwsA(isA<PalmLimitReachedException>()));
    });

    test('not_entitled', () async {
      functions.error = const EdgeError('not_entitled', 'Your subscription has ended.');
      await expectLater(read(), throwsA(isA<PalmNotEntitledException>()));
    });

    test('unauthorized', () async {
      functions.error = const EdgeError('unauthorized', 'Please sign in again.');
      await expectLater(read(), throwsA(isA<PalmSignedOutException>()));
    });

    test('ai_unavailable is retryable', () async {
      functions.error = const EdgeError('ai_unavailable', 'Our reader is very busy.');
      await expectLater(read(), throwsA(isA<PalmUnavailableException>()));
    });

    test('a transport failure keeps its own message', () async {
      // `code` is null when the request never reached the function, and the message already
      // explains the network rather than the server — so it is passed through untouched.
      functions.error = const EdgeError(null, 'No internet connection.');

      await expectLater(
        read(),
        throwsA(
          isA<PalmUnavailableException>()
              .having((e) => e.message, 'message', 'No internet connection.'),
        ),
      );
    });

    test('an unrecognised code is treated as retryable', () async {
      functions.error = const EdgeError('something_new', 'Something went wrong.');
      await expectLater(read(), throwsA(isA<PalmUnavailableException>()));
    });
  });

  test('a body that is not a reading is retryable, not a crash', () async {
    functions.response = {'reading': 'nonsense'};
    await expectLater(read(), throwsA(isA<PalmUnavailableException>()));
  });

  test('no session asks the user to sign in, and sends nothing', () async {
    FlutterSecureStorage.setMockInitialValues({});

    await expectLater(read(), throwsA(isA<PalmSignedOutException>()));
    // The photo must not leave the device when there is nobody to attribute it to.
    expect(functions.lastName, isNull);
  });
}

class _FakeEdgeFunctions implements EdgeFunctions {
  Map<String, dynamic> response = const {};
  EdgeError? error;

  String? lastName;
  Map<String, dynamic>? lastBody;
  Duration? lastTimeout;

  @override
  Future<Map<String, dynamic>> call(
    String name, {
    Map<String, dynamic>? body,
    String? bearerToken,
    bool delete = false,
    Duration? timeout,
  }) async {
    lastName = name;
    lastBody = body;
    lastTimeout = timeout;

    final failure = error;
    if (failure != null) throw failure;
    return response;
  }
}
