import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/models/palm_reading.dart';
import 'palm_copy.dart';

/// How far the on-device work got before the request went out.
enum PalmPrepStage { captured, compressed, sent }

/// How the scan ended, so the view knows where to send the user.
///
/// Held in state rather than delivered through a Completer, because a scan can end more than
/// once: a failure leaves the user on this screen with a retry button, and a Completer could
/// only ever report the first attempt.
enum PalmScanOutcome {
  /// A reading is ready; go to it.
  ready,

  /// Not a palm. Back to the camera with the reason.
  rejected,

  /// The day's allowance is gone. Back to the camera, with the buttons closed.
  limitReached,

  /// The subscription lapsed while waiting.
  notEntitled,

  /// The session went away.
  signedOut,

  /// Retryable — stay here and offer the button.
  failed,
}

/// The scan screen's state.
///
/// [progress] and the labels are derived rather than stored, so there is exactly one source of
/// truth — the clock — and nothing to keep in step. That also makes the whole progress model
/// testable without pumping a widget.
@immutable
class PalmScanState {
  const PalmScanState({
    required this.startedAt,
    this.elapsed = Duration.zero,
    this.stage = PalmPrepStage.captured,
    this.complete = false,
    this.slow = false,
    this.error,
    this.reading,
    this.outcome,
  });

  /// When the request went out. Progress is measured from here against the wall clock rather
  /// than by counting ticks, so an app that spends twenty seconds backgrounded comes back with
  /// a correct bar instead of a rewound one.
  final DateTime startedAt;

  final Duration elapsed;
  final PalmPrepStage stage;

  /// The reading has arrived and the bar may finish.
  final bool complete;

  /// Past the client timeout. The screen offers to retry rather than throwing the photo away.
  final bool slow;

  final String? error;
  final PalmReading? reading;

  /// Null while the reading is still in flight. Set once it resolves, and reset to null by a
  /// retry so the view acts on the new attempt rather than the old one.
  final PalmScanOutcome? outcome;

  /// Where the on-device work leaves the bar before the network is involved at all.
  static const _prepCeiling = 0.08;

  /// Everything between prep and the response.
  static const _span = 0.82;

  /// Sets how fast the curve flattens. Tuned so a typical 9-11 second reading sits around
  /// 55-60% when the answer lands — moving well, rather than parked at 95% and looking stuck.
  static const _tau = 14.0;

  /// Where the bar waits when the model takes longer than usual.
  static const _ceiling = 0.89;

  /// How far along, 0 to 1.
  ///
  /// An exponential approach to a ceiling below 1: fast where most calls finish, flattening
  /// where they do not, and — the point — **structurally unable to reach 100% without a
  /// response**. It never claims to have finished something that has not finished. The shape
  /// is a decay model of expected remaining work, which is the honest version of a bar that
  /// cannot know its own denominator.
  double get progress {
    if (complete) return 1;

    final prep = switch (stage) {
      PalmPrepStage.captured => 0.03,
      PalmPrepStage.compressed => 0.06,
      PalmPrepStage.sent => _prepCeiling,
    };

    if (stage != PalmPrepStage.sent) return prep;

    final t = elapsed.inMilliseconds / 1000;
    final eased = 1 - math.exp(-t / _tau);
    return math.min(_prepCeiling + _span * eased, _ceiling);
  }

  int get percent => (progress * 100).round();

  /// Which of the four chips is lit. Six seconds each, then held on the last.
  int get stageIndex {
    if (complete) return 3;
    return (elapsed.inSeconds ~/ 6).clamp(0, 3);
  }

  /// True only when the failure arrived after a wait long enough to call slow.
  ///
  /// The retry card used to be titled "That's taking longer than usual" whatever went wrong,
  /// so an outage that answered in 300ms told the user their photo was taking a long time.
  /// The client gives the model 75 seconds, so anything that fails inside 20 is a hard
  /// failure and should say so.
  bool get failedSlowly => elapsed >= const Duration(seconds: 20);

  /// The line under the heading.
  ///
  /// Advances every 3.5s and then **sticks** on the final entry rather than wrapping. Cycling
  /// back to "Looking at your palm…" at thirty seconds would read as the scan having started
  /// over, which is the opposite of reassuring when someone is already waiting.
  String get statusLine {
    final index = (elapsed.inMilliseconds ~/ 3500)
        .clamp(0, PalmCopy.statusLines.length - 1);
    return PalmCopy.statusLines[index];
  }

  /// The "Did you know?" text. Wraps freely — these are ambient, not progress.
  String get fact {
    final index = (elapsed.inSeconds ~/ 5) % PalmCopy.facts.length;
    return PalmCopy.facts[index];
  }

  PalmScanState copyWith({
    Duration? elapsed,
    PalmPrepStage? stage,
    bool? complete,
    bool? slow,
    String? error,
    PalmReading? reading,
    PalmScanOutcome? outcome,
    bool clearError = false,
  }) {
    return PalmScanState(
      startedAt: startedAt,
      elapsed: elapsed ?? this.elapsed,
      stage: stage ?? this.stage,
      complete: complete ?? this.complete,
      slow: slow ?? this.slow,
      error: clearError ? null : (error ?? this.error),
      reading: reading ?? this.reading,
      outcome: outcome ?? this.outcome,
    );
  }
}
