import 'dart:convert';
import 'dart:typed_data';

import '../models/palm_reading.dart';
import '../repositories/palm_repository.dart';
import 'edge_functions.dart';
import 'session_store.dart';

/// Talks to the `palm-reading` Edge Function. Gemini itself is never called from the device.
///
/// The client sends a photograph and a focus — nothing else. The model, the prompt, the daily
/// allowance and the entitlement check all live server-side, because the anon key ships inside
/// the app and anything the app could assert about its own quota would be assertable by anyone.
class SupabasePalmRepository implements PalmRepository {
  SupabasePalmRepository(this._functions, this._sessions);

  final EdgeFunctions _functions;
  final SessionStore _sessions;

  /// Longer than every other call in the app, because this one waits on a multimodal model.
  ///
  /// Sits just past the function's own 70-second ceiling, so a function that gives up in an
  /// orderly way gets to return its own error message rather than being cut off here and
  /// reported as a generic timeout.
  static const _timeout = Duration(seconds: 75);

  @override
  Future<PalmReading> read({
    required Uint8List image,
    required PalmFocus focus,
  }) async {
    final token = await _sessions.readToken();
    if (token == null) {
      throw const PalmSignedOutException('Please sign in again.');
    }

    final Map<String, dynamic> data;
    try {
      data = await _functions.call(
        'palm-reading',
        bearerToken: token,
        timeout: _timeout,
        body: {
          'image': base64Encode(image),
          'mime_type': 'image/jpeg',
          'focus': focus.wire,
        },
      );
    } on EdgeError catch (e) {
      throw switch (e.code) {
        // Nothing went wrong — the photo simply was not a palm. The message is specific about
        // why ("a bit too dark", "hold steady"), so it is passed through unchanged.
        'no_palm' => NoPalmDetectedException(e.message),
        'limit_reached' => PalmLimitReachedException(e.message),
        'not_entitled' => PalmNotEntitledException(e.message),
        'unauthorized' => const PalmSignedOutException('Please sign in again.'),
        'ai_unavailable' => PalmUnavailableException(e.message),
        // Includes the transport failures, where `code` is null and the message already
        // explains the network rather than the server.
        _ => PalmUnavailableException(e.message),
      };
    }

    final reading = PalmReading.fromServer(data['reading']);
    if (reading == null) {
      // The call succeeded and the body is not a reading. Nothing the user can act on, and
      // retrying is the only sensible offer.
      throw const PalmUnavailableException(
        'That reading came back incomplete. Please try again.',
      );
    }

    return reading;
  }
}
