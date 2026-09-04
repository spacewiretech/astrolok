import 'package:flutter/foundation.dart';

import '../../data/camera/reading_camera.dart';
import '../../data/models/palm_reading.dart' show PalmFocus;

/// What the capture screen is doing.
@immutable
class FaceCaptureState {
  const FaceCaptureState({
    this.focus = PalmFocus.love,
    this.cameraReady = false,
    this.cameraFailure,
    this.busy = false,
    this.error,
    this.limitReached,
  });

  /// The design opens on Love & Relationships, and it is the most asked-for reading.
  final PalmFocus focus;

  final bool cameraReady;

  /// Why the viewfinder is not live, when it is not. Null while it is.
  final CameraFailure? cameraFailure;

  /// A capture is being taken and prepared. Covers the moment between the shutter and the
  /// scan screen, which is short but long enough to double-tap through.
  final bool busy;

  final String? error;

  /// The day's allowance is gone. Set when the server refuses a reading with `limit_reached`,
  /// so a second attempt is blocked here rather than spending another round trip to be told
  /// the same thing.
  final String? limitReached;

  /// The gallery stays open when the allowance is gone for the same reason the camera closes:
  /// neither can produce a reading, and a button that cannot work should not be tappable.
  bool get canCapture => cameraReady && !busy && limitReached == null;

  bool get canPickFromGallery => !busy && limitReached == null;

  /// True once the camera has answered either way, so the screen knows to stop waiting.
  bool get cameraSettled => cameraReady || cameraFailure != null;

  FaceCaptureState copyWith({
    PalmFocus? focus,
    bool? cameraReady,
    CameraFailure? cameraFailure,
    bool? busy,
    String? error,
    String? limitReached,
    bool clearError = false,
    bool clearFailure = false,
  }) {
    return FaceCaptureState(
      focus: focus ?? this.focus,
      cameraReady: cameraReady ?? this.cameraReady,
      cameraFailure: clearFailure ? null : (cameraFailure ?? this.cameraFailure),
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      limitReached: limitReached ?? this.limitReached,
    );
  }
}
