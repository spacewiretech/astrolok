import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    state = PalmScanState(startedAt: DateTime.now());
    await _run();
  }

  Future<void> _run() async {
    final request = _request;
    if (request == null) return;

    _startTicker();
    state = state.copyWith(stage: PalmPrepStage.sent, clearError: true, slow: false);

    final startedAt = DateTime.now();

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
    } on NoPalmDetectedException catch (e) {
      // Nothing went wrong — the photo simply was not a palm — so the capture is dropped and
      // the user goes back to the viewfinder rather than being shown an error state.
      await ref.read(palmImageStoreProvider).discardPending();
      await _settle(startedAt, e.message, PalmScanOutcome.rejected);
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

  Future<void> _settle(
    DateTime startedAt,
    String message,
    PalmScanOutcome outcome, {
    bool stay = false,
  }) async {
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
