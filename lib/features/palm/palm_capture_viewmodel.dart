import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    await _camera.initialize();
    if (_disposed) return;

    state = state.copyWith(
      cameraReady: _camera.isReady,
      cameraFailure: _camera.failure,
      clearFailure: _camera.failure == null,
    );
  }

  void setFocus(PalmFocus focus) {
    state = state.copyWith(focus: focus, clearError: true);
  }

  /// Records that the day's allowance is gone, so the buttons close rather than spending
  /// another round trip to be refused again.
  void setLimitReached(String message) {
    state = state.copyWith(limitReached: message);
  }

  /// Takes a photo, prepares it, and returns what the scan screen needs. Null on failure, with
  /// the reason already in `state.error`.
  Future<PalmScanRequest?> capture() => _prepare(() => _camera.capture());

  /// The gallery path. Also the only way to get a photo on a simulator, which has no camera.
  Future<PalmScanRequest?> pickFromGallery() => _prepare(pickPhotoFromGallery);

  Future<PalmScanRequest?> _prepare(Future<Uint8List?> Function() source) async {
    if (state.busy) return null;
    state = state.copyWith(busy: true, clearError: true);

    try {
      final raw = await source();
      if (raw == null) {
        // Covers a cancelled gallery pick as well as a failed shutter, so it must not read as
        // an error in the cancelled case — hence no message on an empty result from the
        // picker. The camera path sets one below.
        state = state.copyWith(busy: false);
        return null;
      }

      final prepared = await prepareReadingImage(raw);
      if (_disposed) return null;

      if (prepared == null) {
        state = state.copyWith(busy: false, error: PalmCopy.imageUnreadable);
        return null;
      }

      debugPrint('[palm] prepared ${prepared.width}x${prepared.height}, '
          '${prepared.sizeInKb}KB');

      // Stashed before the reading is requested so the scan screen can show the hand while it
      // waits, and so the results screen has it whatever happens next.
      await ref.read(palmImageStoreProvider).savePending(prepared.bytes);
      if (_disposed) return null;

      state = state.copyWith(busy: false);
      return PalmScanRequest(image: prepared.bytes, focus: state.focus);
    } catch (error) {
      debugPrint('[palm] capture failed: $error');
      if (_disposed) return null;
      state = state.copyWith(busy: false, error: PalmCopy.captureFailed);
      return null;
    }
  }
}

final palmCaptureViewModelProvider =
    AutoDisposeNotifierProvider<PalmCaptureViewModel, PalmCaptureState>(
  PalmCaptureViewModel.new,
);
