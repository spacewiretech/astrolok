import 'dart:typed_data';

import '../models/palm_reading.dart';

/// Reads a photograph of a palm.
///
/// The implementation sends the image to an Edge Function, which holds the model credentials
/// and discards the photo when the request ends. Nothing here ever sees an API key.
abstract interface class PalmRepository {
  /// One reading. [image] is JPEG bytes, already downscaled by the caller.
  Future<PalmReading> read({required Uint8List image, required PalmFocus focus});
}

/// Base for everything that can go wrong. [message] is always safe to show.
class PalmException implements Exception {
  const PalmException(this.message);

  final String message;

  @override
  String toString() => 'PalmException: $message';
}

/// The photo did not show a readable palm.
///
/// Not a failure: nothing went wrong, the user simply needs to take another photo. The capture
/// screen treats it that way — it sends them back to the viewfinder with a specific reason
/// rather than showing an error state.
class NoPalmDetectedException extends PalmException {
  const NoPalmDetectedException(super.message);
}

/// The day's allowance is used up. Known before the camera is even opened.
class PalmLimitReachedException extends PalmException {
  const PalmLimitReachedException(super.message);
}

/// The model is unreachable, overloaded, or answered with something unusable. Retryable, and
/// nothing is wrong with the photo — so the scan screen offers to try again with the same one.
class PalmUnavailableException extends PalmException {
  const PalmUnavailableException(super.message);
}

/// The subscription lapsed between opening the screen and asking for a reading.
class PalmNotEntitledException extends PalmException {
  const PalmNotEntitledException(super.message);
}

/// The session is gone; the user has to sign in again.
class PalmSignedOutException extends PalmException {
  const PalmSignedOutException(super.message);
}
