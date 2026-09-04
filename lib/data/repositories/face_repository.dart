import 'dart:typed_data';

import '../models/face_reading.dart';
import '../models/palm_reading.dart' show PalmFocus;

/// Reads a photograph of a face.
///
/// The implementation sends the image to an Edge Function, which holds the model credentials
/// and discards the photo when the request ends. Nothing here ever sees an API key, and no
/// photograph of anyone's face outlives the request on a server.
abstract interface class FaceRepository {
  /// One reading. [image] is JPEG bytes, already downscaled by the caller.
  Future<FaceReading> read({required Uint8List image, required PalmFocus focus});
}

/// Base for everything that can go wrong. [message] is always safe to show.
///
/// A parallel hierarchy to `PalmException` rather than a shared one. They look alike today, but
/// the two scan screens have to switch on them exhaustively and a shared base would let a new
/// palm-only case silently fall through the face screen's switch.
class FaceException implements Exception {
  const FaceException(this.message);

  final String message;

  @override
  String toString() => 'FaceException: $message';
}

/// The photo did not show a readable face.
///
/// Not a failure: nothing went wrong, the user simply needs to take another photo. The capture
/// screen treats it that way — it sends them back to the viewfinder with a specific reason
/// rather than showing an error state.
class NoFaceDetectedException extends FaceException {
  const NoFaceDetectedException(super.message);
}

/// The day's allowance is used up. Counted separately from palm readings.
class FaceLimitReachedException extends FaceException {
  const FaceLimitReachedException(super.message);
}

/// The model is unreachable, overloaded, or answered with something unusable. Retryable, and
/// nothing is wrong with the photo — so the scan screen offers to try again with the same one.
class FaceUnavailableException extends FaceException {
  const FaceUnavailableException(super.message);
}

/// The subscription lapsed between opening the screen and asking for a reading.
class FaceNotEntitledException extends FaceException {
  const FaceNotEntitledException(super.message);
}

/// The session is gone; the user has to sign in again.
class FaceSignedOutException extends FaceException {
  const FaceSignedOutException(super.message);
}
