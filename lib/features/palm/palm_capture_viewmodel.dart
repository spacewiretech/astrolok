import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/camera/reading_camera.dart';
import '../../data/camera/reading_image.dart';
import '../../data/models/palm_reading.dart';
import '../../data/providers.dart';
import 'palm_copy.dart';
import 'palm_capture_state.dart';

/// What the scan screen needs to do its work, handed over through the route.
///
/// Carries the prepared bytes rather than a file path: they are already in memory, and a scan
/// that has to re-read them from disk is a scan that can fail for a second reason.
@immutable
class PalmScanRequest {
  const PalmScanRequest({required this.image, required this.focus});

  final Uint8List image;
  final PalmFocus focus;
}

/// Runs the camera and turns a shutter press into a [PalmScanRequest].
///
/// Does not navigate — the view does that with what [capture] returns, following the
/// convention that a ViewModel never touches the router.
class PalmCaptureViewModel extends AutoDisposeNotifier<PalmCaptureState> {
  /// Every method here awaits hardware or an isolate, and this provider is autoDispose — so
  /// the user can leave the screen mid-await and the continuation still runs. Assigning to
  /// `state` after that throws. Riverpod 2's Ref has no `mounted`, so the flag is kept by hand.
  bool _disposed = false;

  /// The one camera this screen uses.
  ///
  /// Resolved with `watch`, not `read`. `palmCameraProvider` is autoDispose, and an autoDispose
  /// provider with no listener is torn down and rebuilt on the next read — so reading it per
  /// call handed out a *different* camera each time: one instance got initialised, and the
  /// next `isReady` asked a fresh one that had never been started. The viewfinder then waited
  /// on a camera nobody had opened, forever. Watching gives the screen a single instance for
  /// as long as it is on screen.
  late final ReadingCamera _camera;

  @override
  PalmCaptureState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _camera = ref.watch(palmCameraProvider);

    // The camera is not started here: `build` must stay synchronous, and the view starts it
    // from its first frame instead.
    return const PalmCaptureState();
  }

  /// The live preview, so the view does not have to resolve the camera itself and risk
  /// getting a second one.
  Widget preview() => _camera.preview();

  double get previewAspectRatio =>
      _camera.aspectRatio > 0 ? _camera.aspectRatio : 1;

  /// Opens the camera. Safe to call again — the retry button after a denial does.
  Future<void> startCamera() async {
    final first = !_cameraReported;
    await _camera.initialize();
    if (_disposed) return;

    state = state.copyWith(
      cameraReady: _camera.isReady,
      cameraFailure: _camera.failure,
      clearFailure: _camera.failure == null,
    );

    // The top of the reading funnel. Reported after initialize rather than on mount, because a
    // capture screen with no working camera is not a capture opportunity — and the split between
    // the two is the permission question this app has no other way to answer.
    if (first) {
      _cameraReported = true;
      analytics.track(Ev.readingCaptureOpened, {
        P.feature: ReadingFeature.palm,
        P.cameraReady: _camera.isReady,
      });
    }
    analytics.track(Ev.cameraPermissionResult, {
      P.feature: ReadingFeature.palm,
      P.result: _camera.isReady ? 'granted' : 'denied',
      P.error: _camera.failure,
      // A retry after a denial, which is the user going to Settings and coming back.
      P.trigger: first ? 'open' : 'retry',
    });
  }

  bool _cameraReported = false;

  void setFocus(PalmFocus focus) {
    // What the user says they want read. The single most useful property on a palm reading:
    // it is a stated intent, volunteered before any result exists to bias it.
    if (focus != state.focus) {
      analytics.track(Ev.readingFocusSelected, {
        P.feature: ReadingFeature.palm,
        P.focus: focus.name,
        P.previousFocus: state.focus.name,
      });
    }
    state = state.copyWith(focus: focus, clearError: true);
  }

  /// Records that the day's allowance is gone, so the buttons close rather than spending
  /// another round trip to be refused again.
  void setLimitReached(String message) {
    state = state.copyWith(limitReached: message);
  }

  /// Takes a photo, prepares it, and returns what the scan screen needs. Null on failure, with
  /// the reason already in `state.error`.
  ///
  /// The camera is the only source. There is no gallery path here on purpose — a palm is read
  /// from a photo taken on the spot — which is why this is no longer the shared `_prepare` the
  /// face flow still has.
  Future<PalmScanRequest?> capture() async {
    if (state.busy) return null;
    state = state.copyWith(busy: true, clearError: true);
    final startedAt = DateTime.now();

    try {
      final raw = await _camera.capture();
      if (raw == null) {
        // A failed shutter, and now unambiguously that: this branch used to be shared with a
        // cancelled gallery pick, which must not read as an error, so it stayed silent — and
        // a failed capture said nothing at all. `DeviceCamera.capture` swallows its own
        // exceptions and returns null, so the catch below never covered this.
        state = state.copyWith(busy: false, error: PalmCopy.captureFailed);
        analytics.track(Ev.readingCaptureFailed, {
          P.feature: ReadingFeature.palm,
          P.reason: 'shutter_failed',
          P.focus: state.focus.name,
        });
        return null;
      }

      final prepared = await prepareReadingImage(raw);
      if (_disposed) return null;

      if (prepared == null) {
        state = state.copyWith(busy: false, error: PalmCopy.imageUnreadable);
        analytics.track(Ev.readingCaptureFailed, {
          P.feature: ReadingFeature.palm,
          P.reason: 'unreadable',
          P.focus: state.focus.name,
        });
        return null;
      }

      debugPrint('[palm] prepared ${prepared.width}x${prepared.height}, '
          '${prepared.sizeInKb}KB');

      // Stashed before the reading is requested so the scan screen can show the hand while it
      // waits, and so the results screen has it whatever happens next.
      await ref.read(palmImageStoreProvider).savePending(prepared.bytes);
      if (_disposed) return null;

      state = state.copyWith(busy: false);

      analytics.track(Ev.readingPhotoCaptured, {
        P.feature: ReadingFeature.palm,
        P.focus: state.focus.name,
        // The downscaled size that actually goes to the model. A drift upward here is a cost
        // and latency problem long before it is a visible one.
        P.bytes: prepared.bytes.length,
        P.msToCapture: DateTime.now().difference(startedAt).inMilliseconds,
      });

      return PalmScanRequest(image: prepared.bytes, focus: state.focus);
    } catch (error) {
      debugPrint('[palm] capture failed: $error');
      if (_disposed) return null;
      state = state.copyWith(busy: false, error: PalmCopy.captureFailed);
      analytics.track(Ev.readingCaptureFailed, {
        P.feature: ReadingFeature.palm,
        P.reason: 'exception',
        P.error: error.toString(),
        P.focus: state.focus.name,
      });
      return null;
    }
  }
}

final palmCaptureViewModelProvider =
    AutoDisposeNotifierProvider<PalmCaptureViewModel, PalmCaptureState>(
  PalmCaptureViewModel.new,
);
