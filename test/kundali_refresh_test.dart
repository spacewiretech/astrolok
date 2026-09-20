import 'package:astrolok/data/entitlement.dart';
import 'package:astrolok/data/kundali_summary.dart';
import 'package:astrolok/data/models/app_user.dart';
import 'package:astrolok/data/models/birth_place.dart';
import 'package:astrolok/data/models/kundali.dart';
import 'package:astrolok/data/providers.dart';
import 'package:astrolok/data/repositories/kundali_repository.dart';
import 'package:astrolok/app/router.dart';
import 'package:astrolok/features/kundali/kundali_gate_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// That "I could not find out" never reads as "this account has no kundali".
///
/// The bug this guards: tapping the halfway push on a cold start landed on the kundali *form*
/// rather than the waiting screen. Both the gate and the waiting screen took a null summary as
/// proof that nothing had been asked for, when it also meant the status call had failed or the
/// session was still resolving. The form then offered to re-cast a kundali that existed and was
/// half-written — and a re-cast spends one of the account's regenerations.

const _place = BirthPlace(
  placeId: 'fake-tirupati',
  label: 'Tirupati, Andhra Pradesh, India',
  latitude: 13.6288,
  longitude: 79.4192,
  timeZoneId: 'Asia/Kolkata',
);

final _user = AppUser(
  id: 'u1',
  phone: '9931145610',
  name: 'Asha',
  birthDate: DateTime(1995, 3, 21),
  birthTime: '10:30',
  paymentType: PaymentType.trial,
  entitled: true,
  chatLanguage: 'English',
  birthPlace: _place,
);

class _SignedIn extends EntitlementNotifier {
  _SignedIn(this.user);

  final AppUser? user;

  @override
  AppUser? build() => user;

  @override
  void set(AppUser? user) => state = user;
}

/// A kundali mid-wait: the reading is written but the reveal has not come, which is exactly the
/// state the halfway push is sent in. The server reports this as `waiting`.
Map<String, Object?> _waitingPayload({String id = 'k1'}) {
  final now = DateTime.now().toUtc();
  return {
    'id': id,
    'state': 'waiting',
    'requested_at': now.subtract(const Duration(hours: 12)).toIso8601String(),
    'unlock_at': now.add(const Duration(hours: 12)).toIso8601String(),
    'server_now': now.toIso8601String(),
    'unlock_hours': 24,
    'birth': {
      'dob': '1995-03-21',
      'birth_time': '10:30',
      'place_label': _place.label,
      'place_id': _place.placeId,
      'time_zone_id': _place.timeZoneId,
    },
    'teaser': {'moon_rashi': 'Mesha', 'moon_sign': 'Aries', 'nakshatra': 'Ashwini', 'pada': 2},
    'stages': const <Object?>[],
    'viewed': false,
    'regenerations_left': 2,
  };
}

/// Answers however the test tells it to: with a summary, with "none", or by failing.
class _StubKundaliRepository implements KundaliRepository {
  _StubKundaliRepository({this.summary, this.error});

  Map<String, Object?>? summary;
  Object? error;
  int calls = 0;

  @override
  Future<KundaliSummary?> status({String surface = 'home'}) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    final raw = summary;
    return raw == null ? null : KundaliSummary.fromServer(raw, receivedAt: DateTime.now());
  }

  @override
  Future<KundaliReading> report() => throw UnimplementedError();

  @override
  Future<KundaliSummary> request({
    required DateTime birthDate,
    required String birthTime,
    required BirthPlace place,
  }) =>
      throw UnimplementedError();
}

ProviderContainer _containerWith(_StubKundaliRepository repository, {AppUser? user}) {
  final container = ProviderContainer(
    overrides: [
      kundaliRepositoryProvider.overrideWithValue(repository),
      entitlementProvider.overrideWith(() => _SignedIn(user)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('refresh outcomes', () {
    test('a kundali mid-wait is found, and routes to the waiting screen', () async {
      final repository = _StubKundaliRepository(summary: _waitingPayload());
      final container = _containerWith(repository, user: _user);

      final result = await container.read(kundaliSummaryProvider.notifier).refresh(force: true);

      expect(result.outcome, KundaliRefreshOutcome.found);
      expect(result.summary?.state, KundaliState.waiting);
      expect(KundaliGateView.routeFor(result.summary), Routes.kundaliWaiting);
    });

    test('the server saying there is none is an answer, and routes to the form', () async {
      final repository = _StubKundaliRepository();
      final container = _containerWith(repository, user: _user);

      final result = await container.read(kundaliSummaryProvider.notifier).refresh(force: true);

      expect(result.outcome, KundaliRefreshOutcome.none);
      expect(KundaliGateView.routeFor(result.summary), Routes.kundaliNew);
    });

    test('a failed status call with nothing cached is unknown, never none', () async {
      final repository = _StubKundaliRepository(error: const KundaliUnavailableException('offline'));
      final container = _containerWith(repository, user: _user);

      final result = await container.read(kundaliSummaryProvider.notifier).refresh(force: true);

      expect(result.outcome, KundaliRefreshOutcome.unknown);
      expect(result.isNone, isFalse, reason: 'a failure must never send anyone to the form');
    });

    test('a failed status call keeps a summary already known', () async {
      final repository = _StubKundaliRepository(summary: _waitingPayload());
      final container = _containerWith(repository, user: _user);
      final notifier = container.read(kundaliSummaryProvider.notifier);

      await notifier.refresh(force: true);
      repository.error = const KundaliUnavailableException('offline');
      final result = await notifier.refresh(force: true);

      expect(result.outcome, KundaliRefreshOutcome.found);
      expect(KundaliGateView.routeFor(result.summary), Routes.kundaliWaiting);
    });

    test('no session yet is unknown, and does not reach the server', () async {
      final repository = _StubKundaliRepository(summary: _waitingPayload());
      final container = _containerWith(repository);

      final result = await container.read(kundaliSummaryProvider.notifier).refresh(force: true);

      expect(result.outcome, KundaliRefreshOutcome.unknown);
      expect(repository.calls, 0);
    });

    test('a revealed kundali routes to the report', () async {
      final repository = _StubKundaliRepository(
        summary: {..._waitingPayload(), 'state': 'ready'},
      );
      final container = _containerWith(repository, user: _user);

      final result = await container.read(kundaliSummaryProvider.notifier).refresh(force: true);

      expect(result.summary?.state, KundaliState.ready);
      expect(KundaliGateView.routeFor(result.summary), Routes.kundaliReport);
    });
  });
}
