import 'package:flutter/foundation.dart';

import '../../data/camera/reading_camera.dart';
import '../../data/models/palm_reading.dart';

/// What the capture screen is doing.
@immutable
class PalmCaptureState {
  const PalmCaptureState({
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

  /// The day's allowance is gone. Known before the camera is opened, so the screen can say so
  /// up front rather than after a photo has been taken.
  final String? limitReached;

  bool get canCapture => cameraReady && !busy && limitReached == null;

  /// True once the camera has answered either way, so the screen knows to stop waiting.
  bool get cameraSettled => cameraReady || cameraFailure != null;

  PalmCaptureState copyWith({
    PalmFocus? focus,
    bool? cameraReady,
    CameraFailure? cameraFailure,
    bool? busy,
    String? error,
    String? limitReached,
    bool clearError = false,
    bool clearFailure = false,
  }) {
    return PalmCaptureState(
      focus: focus ?? this.focus,
      cameraReady: cameraReady ?? this.cameraReady,
      cameraFailure: clearFailure ? null : (cameraFailure ?? this.cameraFailure),
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      limitReached: limitReached ?? this.limitReached,
    );
  }
}
