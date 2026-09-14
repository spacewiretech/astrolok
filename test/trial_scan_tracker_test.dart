import 'package:astrolok/data/local/trial_scan_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The device-side count behind the trial popup on Home.
///
/// It is only a hint — the reading functions enforce the allowance — so the property that matters
/// most is the direction it fails in: never towards blocking a reading the server would allow.
void main() {
  const tracker = TrialScanTracker();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh account has used nothing', () async {
    expect(await tracker.used('u1', 'palm'), 0);
  });

  test('readings are counted per account and per feature', () async {
    await tracker.recordReading('u1', 'palm');

    expect(await tracker.used('u1', 'palm'), 1);
    // A face reading is its own allowance.
    expect(await tracker.used('u1', 'face'), 0);
    // A second account on the same phone does not inherit the first one's count.
    expect(await tracker.used('u2', 'palm'), 0);
  });

  test('a server refusal brings the count up to the allowance', () async {
    await tracker.markExhausted('u1', 'face', 1);
    expect(await tracker.used('u1', 'face'), 1);
  });

  test('a server refusal never lowers a count that is already past the allowance', () async {
    await tracker.recordReading('u1', 'palm');
    await tracker.recordReading('u1', 'palm');
    await tracker.recordReading('u1', 'palm');

    await tracker.markExhausted('u1', 'palm', 2);

    expect(await tracker.used('u1', 'palm'), 3);
  });

  test('a corrupt value reads as nothing used rather than blocking a reading', () async {
    SharedPreferences.setMockInitialValues({'astrolok.trial_scans.u1.palm': 'garbage'});
    expect(await tracker.used('u1', 'palm'), 0);
  });

  group('limitFrom', () {
    test('defaults to one when the config has no row, or no config has loaded', () {
      expect(TrialScanTracker.limitFrom(null, 'palm'), 1);
      expect(TrialScanTracker.limitFrom(const {}, 'palm'), 1);
    });

    test('reads the row for the feature asked about', () {
      const config = {'trial_palm_readings': '3', 'trial_face_readings': '2'};

      expect(TrialScanTracker.limitFrom(config, 'palm'), 3);
      expect(TrialScanTracker.limitFrom(config, 'face'), 2);
    });

    test('parses like the server: nonsense is one, fractions round down', () {
      for (final value in ['0', '-1', 'abc', '', '-', 'NaN', '0.5']) {
        expect(
          TrialScanTracker.limitFrom({'trial_palm_readings': value}, 'palm'),
          1,
          reason: value,
        );
      }
      expect(TrialScanTracker.limitFrom({'trial_palm_readings': '2.7'}, 'palm'), 2);
    });
  });
}
