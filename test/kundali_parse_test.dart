import 'package:astrolok/data/fake/fake_kundali_chart.dart';
import 'package:astrolok/data/fake/fake_kundali_repository.dart';
import 'package:astrolok/data/models/app_user.dart';
import 'package:astrolok/data/models/birth_place.dart';
import 'package:astrolok/data/models/kundali.dart';
import 'package:astrolok/features/kundali/kundali_stages.dart';
import 'package:astrolok/widgets/stage_checklist.dart';
import 'package:flutter_test/flutter_test.dart';

/// The kundali as the server sends it. The chart is a real one from the server's own engine
/// (`fake_kundali_chart.dart`), so these parse exactly the shape production writes.

Map<String, Object?> _summary({
  String state = 'waiting',
  String requested = '2026-09-17T00:00:00Z',
  String unlock = '2026-09-18T00:00:00Z',
  String serverNow = '2026-09-17T12:00:00Z',
}) =>
    {
      'id': 'k-1',
      'state': state,
      'requested_at': requested,
      'unlock_at': unlock,
      'server_now': serverNow,
      'unlock_hours': 24,
      'birth': {'dob': '1995-03-21', 'birth_time': '10:30', 'place_label': 'Tirupati, Andhra Pradesh, India', 'place_id': 'p1', 'time_zone_id': 'Asia/Kolkata'},
      'teaser': {'moon_rashi': 'Vrischika', 'moon_sign': 'Scorpio', 'nakshatra': 'Vishakha', 'pada': 4},
      'stages': [
        {'key': 'positions', 'completes_at': '2026-09-17T00:28:48Z'},
        {'key': 'lagna', 'completes_at': '2026-09-17T02:24:00Z'},
        {'key': 'dasha', 'completes_at': '2026-09-17T13:12:00Z'},
        {'key': 'insights', 'completes_at': '2026-09-18T00:00:00Z'},
      ],
      'viewed': false,
      'regenerations_left': 2,
    };

void main() {
  group('summary', () {
    test('a waiting summary is read in full', () {
      final s = KundaliSummary.fromServer(_summary(), receivedAt: DateTime.parse('2026-09-17T12:00:00Z'))!;
      expect(s.state, KundaliState.waiting);
      expect(s.birth.birthDate, DateTime(1995, 3, 21));
      expect(s.birth.birthTime, '10:30');
      expect(s.teaser.nakshatra, 'Vishakha');
      expect(s.stages, hasLength(4));
      expect(s.regenerationsLeft, 2);
    });

    test('the countdown runs on the server clock, not a wrong phone clock', () {
      // The phone is two hours slow: it thinks it is 10:00 when the server says 12:00.
      final s = KundaliSummary.fromServer(_summary(), receivedAt: DateTime.parse('2026-09-17T10:00:00Z'))!;
      final deviceNow = DateTime.parse('2026-09-17T10:00:00Z');
      expect(s.remaining(deviceNow), const Duration(hours: 12));
      expect(s.isPastUnlock(DateTime.parse('2026-09-17T21:59:59Z')), isFalse);
      expect(s.isPastUnlock(DateTime.parse('2026-09-17T22:00:00Z')), isTrue);
    });

    test('the reading stage only ticks off when the server says ready', () {
      final waiting = KundaliSummary.fromServer(_summary(), receivedAt: DateTime.parse('2026-09-17T12:00:00Z'))!;
      // Past every timed stage, even past the reveal, but not ready: the last stage stays open.
      final late = DateTime.parse('2026-09-18T06:00:00Z');
      expect(waiting.currentStage(late), 3);
      expect(kundaliStageItems(waiting, late).last.status, StageStatus.active);

      final ready = KundaliSummary.fromServer(_summary(state: 'ready'), receivedAt: DateTime.parse('2026-09-17T12:00:00Z'))!;
      expect(ready.currentStage(late), 4);
      expect(kundaliStageItems(ready, late).every((i) => i.status == StageStatus.done), isTrue);
    });

    test('stages follow the clock until the reading', () {
      final s = KundaliSummary.fromServer(_summary(), receivedAt: DateTime.parse('2026-09-17T12:00:00Z'))!;
      final items = kundaliStageItems(s, DateTime.parse('2026-09-17T12:00:00Z'));
      expect(items.map((i) => i.status), [StageStatus.done, StageStatus.done, StageStatus.active, StageStatus.pending]);
    });

    test('a paid-for kundali has no wait, and is being written until the server says ready', () {
      const at = '2026-09-17T12:00:00Z';
      final instant = KundaliSummary.fromServer(
        _summary(state: 'delayed', requested: at, unlock: at, serverNow: '2026-09-17T12:00:05Z'),
        receivedAt: DateTime.parse('2026-09-17T12:00:05Z'),
      )!;
      expect(instant.isInstant, isTrue);
      expect(instant.isWritingNow(DateTime.parse('2026-09-17T12:00:30Z')), isTrue);
      // Past the window it is late, and the screen says so rather than "a few seconds" forever.
      expect(instant.isWritingNow(DateTime.parse('2026-09-17T12:03:00Z')), isFalse);

      final written = KundaliSummary.fromServer(
        _summary(state: 'ready', requested: at, unlock: at, serverNow: '2026-09-17T12:00:20Z'),
        receivedAt: DateTime.parse('2026-09-17T12:00:20Z'),
      )!;
      expect(written.isWritingNow(DateTime.parse('2026-09-17T12:00:20Z')), isFalse);

      // A trial's is a day's wait, counting down rather than being written.
      final trial = KundaliSummary.fromServer(_summary(), receivedAt: DateTime.parse('2026-09-17T12:00:00Z'))!;
      expect(trial.isInstant, isFalse);
      expect(trial.isWritingNow(DateTime.parse('2026-09-17T12:00:00Z')), isFalse);
    });

    test('a failed kundali shows nothing in progress', () {
      final s = KundaliSummary.fromServer(_summary(state: 'failed'), receivedAt: DateTime.parse('2026-09-17T12:00:00Z'))!;
      expect(kundaliStageItems(s, DateTime.parse('2026-09-17T12:00:00Z')).any((i) => i.status == StageStatus.active), isFalse);
    });

    test('the cached copy reads back as what was cached', () {
      final s = KundaliSummary.fromServer(_summary(), receivedAt: DateTime.parse('2026-09-17T11:00:00Z'))!;
      final back = KundaliSummary.fromServer(s.toJson())!;
      expect(back.id, s.id);
      expect(back.clockOffset, s.clockOffset);
      expect(back.stages.length, 4);
    });

    test('a payload this build cannot read is null, not half a summary', () {
      expect(KundaliSummary.fromServer(null), isNull);
      expect(KundaliSummary.fromServer({'id': 'k'}), isNull);
      expect(KundaliSummary.fromServer({..._summary(), 'birth': {'dob': 'yesterday'}}), isNull);
    });
  });

  group('chart and report', () {
    test('the engine-cast chart parses: nine grahas in twelve houses', () {
      final chart = KundaliChart.fromServer(fakeKundaliChart)!;
      expect(chart.planets.map((p) => p.key), ['sun', 'moon', 'mars', 'mercury', 'jupiter', 'venus', 'saturn', 'rahu', 'ketu']);
      expect(chart.houses.map((h) => h.house), [for (var i = 1; i <= 12; i++) i]);
      expect(chart.lagna.rashi, 'Vrishabha');
      expect(chart.houses.expand((h) => h.occupants).length, 9);
      expect(chart.planet('mars')!.showRetrograde, isTrue);
      expect(chart.planet('rahu')!.showRetrograde, isFalse, reason: 'the nodes are always retrograde and never marked');
      expect(chart.dasha!.sequence.where((s) => s.current), hasLength(1));
    });

    test('a chart missing a graha is refused', () {
      final broken = Map<String, Object?>.from(fakeKundaliChart)..['planets'] = (fakeKundaliChart['planets'] as List).take(8).toList();
      expect(KundaliChart.fromServer(broken), isNull);
    });

    test('the report parses its highlights, insights and houses', () {
      final report = KundaliReport.fromServer(fakeKundaliReport)!;
      expect(report.highlights, hasLength(9));
      expect(report.insights.keys, KundaliInsightKey.all);
      expect(report.houseThemes, hasLength(12));
      expect(report.insights['love']!.evidence, contains('moon_h7'));
    });

    test('a reading needs all three parts', () {
      final full = KundaliReading.fromServer({..._summary(state: 'ready'), 'chart': fakeKundaliChart, 'report': fakeKundaliReport});
      expect(full, isNotNull);
      expect(KundaliReading.fromServer({..._summary(state: 'ready'), 'chart': fakeKundaliChart}), isNull);
      expect(KundaliReading.fromServer(full!.toJson())!.chart.planets, hasLength(9));
    });
  });

  group('birth place', () {
    test('the account carries its place, and loses it with its coordinates', () {
      final user = AppUser.fromServer({
        'user_id': 'u1',
        'birth_place': 'Tirupati, Andhra Pradesh, India',
        'birth_place_id': 'p1',
        'birth_lat': 13.6288,
        'birth_lng': 79.4192,
        'birth_tz': 'Asia/Kolkata',
        'push_marketing_opt_out': true,
      })!;
      expect(user.birthPlace!.timeZoneId, 'Asia/Kolkata');
      expect(user.pushMarketingOptOut, isTrue);

      // After 30 days the server has nulled the coordinates: no place to cast from.
      final aged = AppUser.fromServer({'user_id': 'u1', 'birth_place': 'Tirupati', 'birth_tz': 'Asia/Kolkata'})!;
      expect(aged.birthPlace, isNull);
    });

    test('a place resolves with the label the user chose', () {
      final place = BirthPlace.fromServer(
        {'place_id': 'p1', 'label': 'Tirupati, AP 517501, India', 'lat': 13.6288, 'lng': 79.4192, 'time_zone_id': 'Asia/Calcutta'},
        label: 'Tirupati, Andhra Pradesh, India',
      )!;
      expect(place.label, 'Tirupati, Andhra Pradesh, India');
      expect(place.toRequest()['time_zone_id'], 'Asia/Calcutta');
    });
  });

  group('wording', () {
    test('the countdown is coarse far off and exact close in', () {
      expect(formatRemaining(const Duration(hours: 14, minutes: 22, seconds: 9)), '14h 22m');
      expect(formatRemaining(const Duration(minutes: 22, seconds: 5)), '22m 05s');
      expect(formatRemaining(const Duration(seconds: 45)), '45s');
      expect(formatCountdown(const Duration(hours: 18, minutes: 42, seconds: 9)), '18 : 42 : 09');
    });

    test('the reveal says today, tomorrow or the date', () {
      final now = DateTime(2026, 9, 17, 10);
      expect(formatReveal(DateTime(2026, 9, 17, 21, 5), now), 'today at 9:05 PM');
      expect(formatReveal(DateTime(2026, 9, 18, 9, 41), now), 'tomorrow at 9:41 AM');
      expect(formatReveal(DateTime(2026, 9, 21, 0, 0), now), 'on 21 Sep at 12:00 AM');
    });
  });
}
