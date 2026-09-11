import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/camera/reading_camera.dart';
import '../../data/camera/reading_image.dart';
import '../../data/models/palm_reading.dart' show PalmFocus;
import '../../data/providers.dart';
import 'face_capture_state.dart';
import 'face_copy.dart';

/// What the scan screen needs to do its work, handed over through the route.
///
/// Carries the prepared bytes rather than a file path: they are already in memory, and a scan
/// that has to re-read them from disk is a scan that can fail for a second reason.
@immutable
class FaceScanRequest {
  const FaceScanRequest({required this.image, required this.focus});

  final Uint8List image;
  final PalmFocus focus;
}

/// Runs the front camera and turns a shutter press into a [FaceScanRequest].
///
/// Does not navigate — the view does that with what [capture] returns, following the
/// convention that a ViewModel never touches the router.
class FaceCaptureViewModel extends AutoDisposeNotifier<FaceCaptureState> {
  /// Every method here awaits hardware or an isolate, and this provider is autoDispose — so
  /// the user can leave the screen mid-await and the continuation still runs. Assigning to
  /// `state` after that throws. Riverpod 2's Ref has no `mounted`, so the flag is kept by hand.
  bool _disposed = false;

  /// The one camera this screen uses.
  ///
  /// Resolved with `watch`, not `read`. `faceCameraProvider` is autoDispose, and an autoDispose
  /// provider with no listener is torn down and rebuilt on the next read — so reading it per
  /// call would hand out a *different* camera each time: one instance gets initialised, and the
  /// next `isReady` asks a fresh one that has never been started. The viewfinder then waits on
  /// a camera nobody opened, forever. Watching gives the screen a single instance for as long
  /// as it is on screen. (This exact bug cost an afternoon on the palm screen; do not "tidy" it
  /// back to `read`.)
  late final ReadingCamera _camera;

  @override
  FaceCaptureState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _camera = ref.watch(faceCameraProvider);

    // The camera is not started here: `build` must stay synchronous, and the view starts it
    // from its first frame instead.
    return const FaceCaptureState();
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

    if (first) {
      _cameraReported = true;
      analytics.track(Ev.readingCaptureOpened, {
        P.feature: ReadingFeature.face,
        P.cameraReady: _camera.isReady,
      });
    }
    analytics.track(Ev.cameraPermissionResult, {
      P.feature: ReadingFeature.face,
      P.result: _camera.isReady ? 'granted' : 'denied',
      P.error: _camera.failure,
      P.trigger: first ? 'open' : 'retry',
    });
  }

  bool _cameraReported = false;

  void setFocus(PalmFocus focus) {
    if (focus != state.focus) {
      analytics.track(Ev.readingFocusSelected, {
        P.feature: ReadingFeature.face,
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
  Future<FaceScanRequest?> capture() =>
      _prepare(() => _camera.capture(), source: 'camera');

  /// The gallery path. Also the only way to get a photo on a simulator, which has no camera.
  Future<FaceScanRequest?> pickFromGallery() =>
      _prepare(pickPhotoFromGallery, source: 'gallery');

  /// [source] is `camera` or `gallery`. Threaded through rather than inferred, because the two
  /// share every line below and yet mean different things at the empty-result branch — and a
  /// gallery photo is a materially different input to the model than one framed in our own
  /// viewfinder.
  Future<FaceScanRequest?> _prepare(
    Future<Uint8List?> Function() photo, {
    required String source,
  }) async {
    if (state.busy) return null;
    state = state.copyWith(busy: true, clearError: true);
    final startedAt = DateTime.now();

    try {
      final raw = await photo();
      if (raw == null) {
        // Covers a cancelled gallery pick as well as a failed shutter, so it must not read as
        // an error in the cancelled case — hence no message on an empty result from the
        // picker.
        state = state.copyWith(busy: false);
        analytics.track(Ev.readingCaptureFailed, {
          P.feature: ReadingFeature.face,
          // Backing out of the picker is a decision, not a fault, and counting it as one would
          // make the face flow look broken next to palm's.
          P.reason: source == 'gallery' ? 'cancelled' : 'shutter_failed',
          P.source: source,
          P.focus: state.focus.name,
        });
        return null;
      }

      final prepared = await prepareReadingImage(raw);
      if (_disposed) return null;

      if (prepared == null) {
        state = state.copyWith(busy: false, error: FaceCopy.imageUnreadable);
        analytics.track(Ev.readingCaptureFailed, {
          P.feature: ReadingFeature.face,
          P.reason: 'unreadable',
          P.source: source,
          P.focus: state.focus.name,
        });
        return null;
      }

      debugPrint('[face] prepared ${prepared.width}x${prepared.height}, '
          '${prepared.sizeInKb}KB');

      // Stashed before the reading is requested so the scan screen can show the face while it
      // waits, and so the results screen has it whatever happens next.
      await ref.read(faceImageStoreProvider).savePending(prepared.bytes);
      if (_disposed) return null;

      state = state.copyWith(busy: false);

      analytics.track(
        source == 'gallery' ? Ev.readingPhotoPicked : Ev.readingPhotoCaptured,
        {
          P.feature: ReadingFeature.face,
          P.focus: state.focus.name,
          P.source: source,
          P.bytes: prepared.bytes.length,
          P.msToCapture: DateTime.now().difference(startedAt).inMilliseconds,
        },
      );

      return FaceScanRequest(image: prepared.bytes, focus: state.focus);
    } catch (error) {
      debugPrint('[face] capture failed: $error');
      if (_disposed) return null;
      state = state.copyWith(busy: false, error: FaceCopy.captureFailed);
      analytics.track(Ev.readingCaptureFailed, {
        P.feature: ReadingFeature.face,
        P.reason: 'exception',
        P.error: error.toString(),
        P.source: source,
        P.focus: state.focus.name,
      });
      return null;
    }
  }
}

final faceCaptureViewModelProvider =
    AutoDisposeNotifierProvider<FaceCaptureViewModel, FaceCaptureState>(
  FaceCaptureViewModel.new,
);
