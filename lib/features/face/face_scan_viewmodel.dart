import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/providers.dart';
import '../../data/repositories/face_repository.dart';
import 'face_capture_viewmodel.dart';
import 'face_scan_state.dart';

/// Requests the reading and paces the screen while it is in flight.
class FaceScanViewModel extends AutoDisposeNotifier<FaceScanState> {
  bool _disposed = false;
  Timer? _ticker;

  /// The request in flight, kept so a retry can re-send the same bytes rather than making the
  /// user photograph themselves again after a long wait.
  FaceScanRequest? _request;

  /// The screen must not flash past. A response that arrives almost immediately — a cached
  /// rejection, say — still gets long enough to be seen as a step rather than a glitch.
  static const _minimumDwell = Duration(milliseconds: 2500);

  @override
  FaceScanState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _ticker?.cancel();
    });

    return FaceScanState(startedAt: DateTime.now());
  }

  /// Starts a reading. Called once from the view's first frame.
  Future<void> start(FaceScanRequest request) async {
    _request = request;
    await _run();
  }

  /// Re-sends the photo already in memory.
  Future<void> retry() async {
    final request = _request;
    if (request == null) return;

    _attempt += 1;

    state = FaceScanState(startedAt: DateTime.now());
    await _run();
  }

  /// Which try this is. A reading that only succeeds on the second attempt is a very different
  /// product experience from one that succeeds first time, and both end as `Reading Succeeded`.
  int _attempt = 1;

  Future<void> _run() async {
    final request = _request;
    if (request == null) return;

    _startTicker();
    state = state.copyWith(stage: FacePrepStage.sent, clearError: true, slow: false);

    final startedAt = DateTime.now();

    analytics.track(Ev.readingScanStarted, {
      P.feature: ReadingFeature.face,
      P.focus: request.focus.name,
      P.bytes: request.image.length,
      P.attempt: _attempt,
    });

    try {
      final reading = await ref
          .read(faceRepositoryProvider)
          .read(image: request.image, focus: request.focus);

      if (_disposed) return;

      // The photo becomes this reading's, and its name is stored on the reading so the results
      // screen can show the face it is talking about.
      final fileName =
          await ref.read(faceImageStoreProvider).commitPending(reading.id);
      if (_disposed) return;

      final saved = reading.copyWith(imageFileName: fileName);
      await ref.read(faceReadingStoreProvider).save(saved);
      if (_disposed) return;

      await _holdMinimum(startedAt);
      if (_disposed) return;

      _ticker?.cancel();
      state = state.copyWith(
        complete: true,
        reading: saved,
        outcome: FaceScanOutcome.ready,
      );

      analytics.track(Ev.readingSucceeded, {
        P.feature: ReadingFeature.face,
        P.readingId: saved.id,
        P.focus: request.focus.name,
        P.sectionCount: saved.parts.length,
        P.attempt: _attempt,
        // To the model's answer, not to the screen: `_holdMinimum` pads short waits so the
        // progress animation reads as work, and that padding would flatter this number.
        P.ms: DateTime.now().difference(startedAt).inMilliseconds,
      });
    } on NoFaceDetectedException catch (e) {
      // Nothing went wrong — the photo simply was not a face — so the capture is dropped and
      // the user goes back to the viewfinder rather than being shown an error state.
      await ref.read(faceImageStoreProvider).discardPending();
      await _settle(startedAt, e.message, FaceScanOutcome.rejected);
    } on FaceLimitReachedException catch (e) {
      // Caught by name, before the generic branch. Falling through to `failed` would offer a
      // "Try again" button that is guaranteed to fail the same way — a dead-end retry loop,
      // which is exactly what the palm screen used to do.
      await ref.read(faceImageStoreProvider).discardPending();
      await _settle(startedAt, e.message, FaceScanOutcome.limitReached);
    } on FaceNotEntitledException catch (e) {
      await _settle(startedAt, e.message, FaceScanOutcome.notEntitled);
    } on FaceSignedOutException catch (e) {
      await _settle(startedAt, e.message, FaceScanOutcome.signedOut);
    } on FaceException catch (e) {
      // Retryable. The bytes stay in memory and the screen offers the button, because
      // demanding a fresh photo after a long wait is the cruellest possible failure.
      await _settle(startedAt, e.message, FaceScanOutcome.failed, stay: true);
    } catch (error) {
      debugPrint('[face] scan failed: $error');
      await _settle(
        startedAt,
        'Something went wrong. Please try again.',
        FaceScanOutcome.failed,
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
  /// [outcome] is the honest reason: `rejected` is a photo that was not a face and is not a
  /// system failure at all, `limitReached` is the daily quota, `notEntitled` and `signedOut` are
  /// the gate, and only `failed` is something broken.
  Future<void> _settle(
    DateTime startedAt,
    String message,
    FaceScanOutcome outcome, {
    bool stay = false,
  }) async {
    // Before the dwell padding, so a failure's `ms` is the real time to the answer.
    analytics.track(Ev.readingFailed, {
      P.feature: ReadingFeature.face,
      P.outcome: outcome.name,
      P.message: message,
      P.focus: _request?.focus.name,
      P.attempt: _attempt,
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
    // a progress indicator, a checklist and two labels.
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_disposed) return;
      state = state.copyWith(
        elapsed: DateTime.now().difference(state.startedAt),
      );
    });
  }
}

final faceScanViewModelProvider =
    AutoDisposeNotifierProvider<FaceScanViewModel, FaceScanState>(
  FaceScanViewModel.new,
);
