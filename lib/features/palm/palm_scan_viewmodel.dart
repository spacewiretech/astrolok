import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/providers.dart';
import '../../data/repositories/palm_repository.dart';
import 'palm_capture_viewmodel.dart';
import 'palm_scan_state.dart';

/// Requests the reading and paces the screen while it is in flight.
class PalmScanViewModel extends AutoDisposeNotifier<PalmScanState> {
  bool _disposed = false;
  Timer? _ticker;

  /// The request in flight, kept so a retry can re-send the same bytes rather than making the
  /// user photograph their hand again after a long wait.
  PalmScanRequest? _request;

  /// The screen must not flash past. A response that arrives almost immediately — a cached
  /// rejection, say — still gets long enough to be seen as a step rather than a glitch.
  static const _minimumDwell = Duration(milliseconds: 2500);

  @override
  PalmScanState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _ticker?.cancel();
    });

    return PalmScanState(startedAt: DateTime.now());
  }

  /// Starts a reading. Called once from the view's first frame.
  Future<void> start(PalmScanRequest request) async {
    _request = request;
    await _run();
  }

  /// Re-sends the photo already in memory.
  Future<void> retry() async {
    final request = _request;
    if (request == null) return;

    _attempt += 1;
    state = PalmScanState(startedAt: DateTime.now());
    await _run();
  }

  /// Which try this is. A reading that only succeeds on the second attempt is a very different
  /// product experience from one that succeeds first time, and both end as `Reading Succeeded`.
  int _attempt = 1;

  Future<void> _run() async {
    final request = _request;
    if (request == null) return;

    _startTicker();
    state = state.copyWith(stage: PalmPrepStage.sent, clearError: true, slow: false);

    final startedAt = DateTime.now();

    analytics.track(Ev.readingScanStarted, {
      P.feature: ReadingFeature.palm,
      P.focus: request.focus.name,
      P.bytes: request.image.length,
      P.attempt: _attempt,
    });

    try {
      final reading = await ref
          .read(palmRepositoryProvider)
          .read(image: request.image, focus: request.focus);

      if (_disposed) return;

      // The photo becomes this reading's, and its name is stored on the reading so the results
      // screen can show the hand it is talking about.
      final fileName =
          await ref.read(palmImageStoreProvider).commitPending(reading.id);
      if (_disposed) return;

      final saved = reading.copyWith(imageFileName: fileName);
      await ref.read(palmReadingStoreProvider).save(saved);
      if (_disposed) return;

      await _holdMinimum(startedAt);
      if (_disposed) return;

      _ticker?.cancel();
      state = state.copyWith(
        complete: true,
        reading: saved,
        outcome: PalmScanOutcome.ready,
      );

      analytics.track(Ev.readingSucceeded, {
        P.feature: ReadingFeature.palm,
        P.readingId: saved.id,
        P.focus: request.focus.name,
        P.lineCount: saved.lines.length,
        P.attempt: _attempt,
        // Measured to the model's answer, not to the screen: `_holdMinimum` pads short waits so
        // the progress animation reads as work, and including that padding would flatter the
        // number that actually matters.
        P.ms: DateTime.now().difference(startedAt).inMilliseconds,
      });
    } on NoPalmDetectedException catch (e) {
      // Nothing went wrong — the photo simply was not a palm — so the capture is dropped and
      // the user goes back to the viewfinder rather than being shown an error state.
      await ref.read(palmImageStoreProvider).discardPending();
      await _settle(startedAt, e.message, PalmScanOutcome.rejected);
    } on PalmLimitReachedException catch (e) {
      // Caught by name, before the generic branch below. Falling through to `failed` offered a
      // "Try again" button that was guaranteed to fail identically — a dead-end retry loop for
      // the rest of the day.
      await ref.read(palmImageStoreProvider).discardPending();
      await _settle(startedAt, e.message, PalmScanOutcome.limitReached);
    } on PalmNotEntitledException catch (e) {
      await _settle(startedAt, e.message, PalmScanOutcome.notEntitled);
    } on PalmSignedOutException catch (e) {
      await _settle(startedAt, e.message, PalmScanOutcome.signedOut);
    } on PalmException catch (e) {
      // Retryable. The bytes stay in memory and the screen offers the button, because
      // demanding a fresh photo after a long wait is the cruellest possible failure.
      await _settle(startedAt, e.message, PalmScanOutcome.failed, stay: true);
    } catch (error) {
      debugPrint('[palm] scan failed: $error');
      await _settle(
        startedAt,
        'Something went wrong. Please try again.',
        PalmScanOutcome.failed,
        stay: true,
      );
    }
  }

  /// Holds the screen for [_minimumDwell] measured from [startedAt].
  Future<void> _holdMinimum(DateTime startedAt) async {
    final spent = DateTime.now().difference(startedAt);
    if (spent < _minimumDwell) {
      await Future<void>.delayed(_minimumDwell - spent);
    }
  }

  /// The one exit every failure takes, so no branch can end without saying why.
  ///
  /// [outcome] is the honest reason: `rejected` is a photo that was not a palm and is not a
  /// system failure at all, `limitReached` is the daily quota, `notEntitled` and `signedOut` are
  /// the gate, and only `failed` is something broken.
  Future<void> _settle(
    DateTime startedAt,
    String message,
    PalmScanOutcome outcome, {
    bool stay = false,
  }) async {
    // Before the dwell padding, so a failure's `ms` is the real time to the answer rather than
    // the time the animation was held on screen.
    analytics.track(Ev.readingFailed, {
      P.feature: ReadingFeature.palm,
      P.outcome: outcome.name,
      P.message: message,
      P.focus: _request?.focus.name,
      P.attempt: _attempt,
      // Whether the user is offered a retry. `false` here is a dead end, and a dead end after a
      // long wait is the worst moment this flow has.
      P.blocked: !stay,
      P.ms: DateTime.now().difference(startedAt).inMilliseconds,
    });

    await _holdMinimum(startedAt);
    if (_disposed) return;

    _ticker?.cancel();
    state = state.copyWith(error: message, slow: stay, outcome: outcome);
  }

  void _startTicker() {
    _ticker?.cancel();
    // 100ms is smooth enough for a bar that moves slowly, and cheap: the widget rebuilding is
    // a progress indicator and two labels.
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_disposed) return;
      state = state.copyWith(
        elapsed: DateTime.now().difference(state.startedAt),
      );
    });
  }
}

final palmScanViewModelProvider =
    AutoDisposeNotifierProvider<PalmScanViewModel, PalmScanState>(
  PalmScanViewModel.new,
);
