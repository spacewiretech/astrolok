import 'package:astrolok/data/fake/fake_kundali_chart.dart';
import 'package:astrolok/data/fake/fake_kundali_repository.dart';
import 'package:astrolok/data/models/birth_place.dart';
import 'package:astrolok/data/repositories/cancellation_feedback_repository.dart';
import 'package:astrolok/data/repositories/kundali_repository.dart';
import 'package:astrolok/data/repositories/place_repository.dart';
import 'package:astrolok/data/supabase/edge_functions.dart';
import 'package:astrolok/data/supabase/session_store.dart';
import 'package:astrolok/data/supabase/supabase_cancellation_feedback_repository.dart';
import 'package:astrolok/data/supabase/supabase_kundali_repository.dart';
import 'package:astrolok/data/supabase/supabase_place_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the kundali, place-search and cancellation-feedback endpoints send, and what the app turns
/// each failure into. `not_ready` matters most: it is the reveal lock, and it must land the user on
/// the waiting screen, never on an error.

const _place = BirthPlace(placeId: 'p1', label: 'Tirupati, Andhra Pradesh, India', latitude: 13.6288, longitude: 79.4192, timeZoneId: 'Asia/Kolkata');

Map<String, Object?> _summary({String state = 'waiting'}) => {
      'id': 'k-1',
      'state': state,
      'requested_at': '2026-09-17T00:00:00Z',
      'unlock_at': '2026-09-18T00:00:00Z',
      'server_now': '2026-09-17T00:00:01Z',
      'birth': {'dob': '1995-03-21', 'birth_time': '10:30', 'place_label': 'Tirupati', 'time_zone_id': 'Asia/Kolkata'},
      'teaser': {'moon_rashi': 'Vrischika'},
      'stages': [],
      'viewed': false,
      'regenerations_left': 2,
    };

void main() {
  late _FakeEdgeFunctions functions;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'astrolok.session_token': 'a-valid-token'});
    functions = _FakeEdgeFunctions();
  });

  group('kundali', () {
    late SupabaseKundaliRepository repository;
    setUp(() => repository = SupabaseKundaliRepository(functions, SessionStore()));

    test('a request sends the birth moment and the place, and reads back a summary', () async {
      functions.response = {'kundali': _summary()};
      final summary = await repository.request(birthDate: DateTime(1995, 3, 21), birthTime: '10:30', place: _place);

      expect(functions.lastName, 'kundali');
      expect(functions.lastBody!['action'], 'request');
      expect(functions.lastBody!['dob'], '1995-03-21');
      expect(functions.lastBody!['birth_time'], '10:30');
      expect((functions.lastBody!['place'] as Map)['time_zone_id'], 'Asia/Kolkata');
      expect(summary.id, 'k-1');
    });

    test('no kundali yet is null, not an error', () async {
      functions.response = {'kundali': null};
      expect(await repository.status(surface: 'waiting'), isNull);
      expect(functions.lastBody!['surface'], 'waiting');
    });

    test('a revealed kundali parses with its chart and report', () async {
      functions.response = {
        'kundali': {..._summary(state: 'ready'), 'chart': fakeKundaliChart, 'report': fakeKundaliReport},
      };
      final reading = await repository.report();
      expect(reading.chart.planets, hasLength(9));
      expect(reading.report.insights, hasLength(4));
    });

    test('a report missing its chart is unavailable, never half-shown', () async {
      functions.response = {'kundali': _summary(state: 'ready')};
      await expectLater(repository.report(), throwsA(isA<KundaliUnavailableException>()));
    });

    final cases = <String, Matcher>{
      'not_ready': isA<KundaliNotReadyException>(),
      'limit_reached': isA<KundaliLimitException>(),
      'invalid_request': isA<KundaliInvalidException>(),
      'not_found': isA<KundaliNotFoundException>(),
      'not_entitled': isA<KundaliNotEntitledException>(),
      'unauthorized': isA<KundaliSignedOutException>(),
      'server_error': isA<KundaliUnavailableException>(),
    };
    for (final MapEntry(key: code, value: matcher) in cases.entries) {
      test('$code maps to its exception', () async {
        functions.error = EdgeError(code, 'message for $code');
        await expectLater(repository.report(), throwsA(matcher));
      });
    }

    test('a transport failure is retryable', () async {
      functions.error = const EdgeError(null, 'offline');
      await expectLater(repository.status(), throwsA(isA<KundaliUnavailableException>()));
    });

    test('no session means signed out before any call', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final signedOut = SupabaseKundaliRepository(functions, SessionStore());
      await expectLater(signedOut.status(), throwsA(isA<KundaliSignedOutException>()));
      expect(functions.lastName, isNull);
    });
  });

  group('place search', () {
    late SupabasePlaceRepository repository;
    setUp(() => repository = SupabasePlaceRepository(functions, SessionStore()));

    test('suggestions are read, and the chosen label is the one kept', () async {
      functions.response = {
        'suggestions': [
          {'place_id': 'p1', 'primary': 'Tirupati', 'secondary': 'Andhra Pradesh, India'},
          {'place_id': '', 'primary': 'broken'},
        ],
      };
      final suggestions = await repository.autocomplete('Tiru', sessionToken: 'tok');
      expect(suggestions, hasLength(1));
      // Searching is typing: it gives up long before the default twenty seconds.
      expect(functions.lastTimeout, const Duration(seconds: 10));

      functions.response = {
        'place': {'place_id': 'p1', 'label': 'Tirupati, AP 517501', 'lat': 13.63, 'lng': 79.42, 'time_zone_id': 'Asia/Kolkata'},
      };
      final place = await repository.details(suggestions.single, sessionToken: 'tok', birthDate: DateTime(1943, 6, 1), birthTime: '12:00');
      expect(place.label, 'Tirupati, Andhra Pradesh, India');
      expect(functions.lastBody!['dob'], '1943-06-01');
      expect(functions.lastBody!['session_token'], 'tok');
    });

    test('throttling and outages are told apart', () async {
      functions.error = const EdgeError('throttled', 'slow down');
      await expectLater(repository.autocomplete('Ti', sessionToken: 't'), throwsA(isA<PlaceThrottledException>()));
      functions.error = const EdgeError('place_unavailable', 'down');
      await expectLater(repository.autocomplete('Ti', sessionToken: 't'), throwsA(isA<PlaceUnavailableException>()));
    });
  });

  group('cancellation feedback', () {
    test('an answer is sent with its source, and a repeat is not an error', () async {
      final repository = SupabaseCancellationFeedbackRepository(functions, SessionStore());
      functions.response = {'ok': true, 'recorded': false};
      final recorded = await repository.submit(reason: 'too_expensive', comment: 'costly', notificationId: 'n-1');
      expect(recorded, isFalse);
      expect(functions.lastBody, {'reason': 'too_expensive', 'comment': 'costly', 'source': 'push', 'notification_id': 'n-1'});
    });

    test('no cancelled plan is its own exception', () async {
      final repository = SupabaseCancellationFeedbackRepository(functions, SessionStore());
      functions.error = const EdgeError('not_found', 'none');
      await expectLater(repository.submit(reason: 'other'), throwsA(isA<NoCancelledPlanException>()));
    });
  });

  group('the fake tier', () {
    test('walks the whole journey: none, waiting, then revealed', () async {
      final fake = FakeKundaliRepository(unlockAfter: Duration.zero, latency: false);
      expect(await fake.status(), isNull);

      final summary = await fake.request(birthDate: DateTime(1995, 3, 21), birthTime: '10:30', place: _place);
      expect(summary.regenerationsLeft, 2);

      final reading = await fake.report();
      expect(reading.chart.lagna.rashi, 'Vrishabha');

      // Same details again is the same kundali; different ones spend a regeneration.
      expect((await fake.request(birthDate: DateTime(1995, 3, 21), birthTime: '10:30', place: _place)).id, summary.id);
      final recast = await fake.request(birthDate: DateTime(1995, 3, 21), birthTime: '11:30', place: _place);
      expect(recast.regenerationsLeft, 1);
    });

    test('refuses the report before the reveal', () async {
      final fake = FakeKundaliRepository(unlockAfter: const Duration(hours: 1), latency: false);
      await fake.request(birthDate: DateTime(1995, 3, 21), birthTime: '10:30', place: _place);
      await expectLater(fake.report(), throwsA(isA<KundaliNotReadyException>()));
    });
  });
}

class _FakeEdgeFunctions implements EdgeFunctions {
  Map<String, dynamic> response = {};
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
    if (error != null) throw error!;
    return response;
  }
}
