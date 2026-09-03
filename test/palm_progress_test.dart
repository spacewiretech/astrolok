import 'package:astrolok/features/palm/palm_copy.dart';
import 'package:astrolok/features/palm/palm_scan_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// The scan screen's progress model.
///
/// Worth testing on its own because the whole point of the curve is a guarantee about what it
/// will never do — reach the end before the reading does — and that is invisible on screen
/// until the one time it matters.
void main() {
  final startedAt = DateTime(2026, 9, 4, 12);

  PalmScanState at(Duration elapsed, {bool complete = false}) => PalmScanState(
        startedAt: startedAt,
        elapsed: elapsed,
        stage: PalmPrepStage.sent,
        complete: complete,
      );

  group('progress', () {
    test('starts small and rises', () {
      expect(at(Duration.zero).progress, closeTo(0.08, 0.001));
      expect(at(const Duration(seconds: 5)).progress, greaterThan(0.3));
      expect(at(const Duration(seconds: 10)).progress, greaterThan(0.45));
    });

    test('never reaches the end before the reading does', () {
      // The guarantee. A bar that can hit 100% while the user is still waiting is a bar that
      // lies, and this is the case nobody would notice until a slow day in production.
      for (final seconds in [1, 5, 10, 20, 30, 60, 75, 120, 600, 36000]) {
        final progress = at(Duration(seconds: seconds)).progress;
        expect(
          progress,
          lessThan(0.9),
          reason: 'progress hit $progress at ${seconds}s without a response',
        );
      }
    });

    test('is exactly 1 only once complete', () {
      expect(at(const Duration(seconds: 3), complete: true).progress, 1);
      expect(at(const Duration(hours: 1)).progress, lessThan(1));
    });

    test('never goes backwards', () {
      var previous = 0.0;
      for (var ms = 0; ms <= 90000; ms += 250) {
        final progress = at(Duration(milliseconds: ms)).progress;
        expect(progress, greaterThanOrEqualTo(previous));
        previous = progress;
      }
    });

    test('the on-device stages advance before the request goes out', () {
      final captured = PalmScanState(
        startedAt: startedAt,
        stage: PalmPrepStage.captured,
      );
      final compressed = captured.copyWith(stage: PalmPrepStage.compressed);
      final sent = captured.copyWith(stage: PalmPrepStage.sent);

      expect(captured.progress, lessThan(compressed.progress));
      expect(compressed.progress, lessThan(sent.progress));
    });

    test('percent is a whole number the screen can print', () {
      expect(at(const Duration(seconds: 10)).percent, isA<int>());
      expect(at(Duration.zero).percent, 8);
      expect(at(Duration.zero, complete: true).percent, 100);
    });
  });

  group('stage', () {
    test('advances every six seconds and then holds', () {
      expect(at(Duration.zero).stageIndex, 0);
      expect(at(const Duration(seconds: 7)).stageIndex, 1);
      expect(at(const Duration(seconds: 13)).stageIndex, 2);
      expect(at(const Duration(seconds: 19)).stageIndex, 3);
      // Clamped, not wrapped — a fifth stage would index off the end of the chip list.
      expect(at(const Duration(seconds: 120)).stageIndex, 3);
    });

    test('a finished scan shows every stage done', () {
      expect(at(const Duration(seconds: 2), complete: true).stageIndex, 3);
    });
  });

  group('status line', () {
    test('advances every 3.5 seconds', () {
      expect(at(Duration.zero).statusLine, PalmCopy.statusLines.first);
      expect(at(const Duration(seconds: 4)).statusLine, PalmCopy.statusLines[1]);
    });

    test('sticks on the last line rather than wrapping', () {
      // Wrapping back to "Looking at your palm…" after half a minute would read as the scan
      // having restarted, which is the opposite of reassuring to someone already waiting.
      final late = at(const Duration(seconds: 90)).statusLine;
      final later = at(const Duration(minutes: 10)).statusLine;

      expect(late, PalmCopy.statusLines.last);
      expect(later, PalmCopy.statusLines.last);
    });
  });

  group('facts', () {
    test('cycle and are allowed to repeat', () {
      // Ambient rather than progress, so wrapping is fine here.
      final first = at(Duration.zero).fact;
      final wrapped = at(Duration(seconds: 5 * PalmCopy.facts.length)).fact;

      expect(first, PalmCopy.facts.first);
      expect(wrapped, first);
    });

    test('always lands inside the list', () {
      for (final seconds in [0, 5, 17, 61, 3600]) {
        expect(PalmCopy.facts, contains(at(Duration(seconds: seconds)).fact));
      }
    });
  });

  test('elapsed is measured against the clock, not accumulated ticks', () {
    // A backgrounded app misses every tick while it is away. Because the state carries
    // `startedAt` and the ticker recomputes from `DateTime.now()`, coming back thirty seconds
    // later shows thirty seconds of progress rather than the bar it left behind.
    final resumed = at(const Duration(seconds: 30));
    final never = at(const Duration(seconds: 2));

    expect(resumed.progress, greaterThan(never.progress));
    expect(resumed.startedAt, startedAt);
  });
}
