import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What a caller is told when a function could not be reached or answered with nothing usable.
///
/// Deliberately says nothing about verification. This file is shared by all twelve functions,
/// and the OTP flow's wording used to leak out of it — so a face reading that failed because
/// its function was not deployed told the user that *verification* was unavailable, which sent
/// them looking in entirely the wrong place. `fast2sms_exception.dart` keeps the verification
/// wording, because there it is true.
const _unavailable = 'Astrolok is temporarily unavailable. Please try again in a moment.';

/// A structured failure returned by an Edge Function.
///
/// [code] is the stable machine-readable string the functions emit (`invalid_otp`,
/// `otp_expired`, `throttled`, `unauthorized`, …); [message] is already safe to show.
class EdgeError implements Exception {
  const EdgeError(this.code, this.message);

  /// Null for transport failures that never reached the function.
  final String? code;
  final String message;

  @override
  String toString() => 'EdgeError($code): $message';
}

/// The one call the Supabase repositories make. Injected so the error paths can be tested
/// without a deployed project.
abstract interface class EdgeFunctions {
  Future<Map<String, dynamic>> call(
    String name, {
    Map<String, dynamic>? body,
    String? bearerToken,
    bool delete = false,

    /// Overrides the instance default for this one call.
    ///
    /// Every function here answers well inside 20 seconds except the palm reading, which waits
    /// on a multimodal model and routinely runs past it. A parameter rather than a second
    /// [SupabaseEdgeFunctions] instance in `providers.dart`, which would leave two
    /// similarly-named objects a reader has to tell apart.
    Duration? timeout,
  });
}

class SupabaseEdgeFunctions implements EdgeFunctions {
  SupabaseEdgeFunctions(this._client, {this.timeout = const Duration(seconds: 20)});

  final SupabaseClient _client;
  final Duration timeout;

  @override
  Future<Map<String, dynamic>> call(
    String name, {
    Map<String, dynamic>? body,
    String? bearerToken,
    bool delete = false,
    Duration? timeout,
  }) async {
    final FunctionResponse response;
    try {
      response = await _client.functions
          .invoke(
            name,
            body: body,
            headers: bearerToken == null
                ? null
                : {'Authorization': 'Bearer $bearerToken'},
            method: delete ? HttpMethod.delete : HttpMethod.post,
          )
          .timeout(timeout ?? this.timeout);
    } on SocketException {
      throw const EdgeError(
        null,
        'No internet connection. Check your network and try again.',
      );
    } on TimeoutException {
      throw const EdgeError(null, 'The network is slow right now. Please try again.');
    } on FunctionException catch (e) {
      final decoded = _decodeError(e.details);
      if (decoded != null) throw decoded;
      // A function that is not deployed answers 404 here. That is a developer problem, so it
      // goes to the log while the user sees the same message as any other outage.
      //
      // The log line is the only thing that names the real cause, so it says so loudly: a 404
      // here cost an afternoon of looking for a bug in the app, because the message the user
      // saw talked about verification and slowness and this line was the one place the actual
      // "function is not deployed" ever appeared.
      debugPrint(
        '[supabase] $name returned ${e.status}: ${e.details}'
        '${e.status == 404 ? '  — is this function deployed?' : ''}',
      );
      throw const EdgeError(null, _unavailable);
    } catch (e) {
      debugPrint('[supabase] $name failed: $e');
      throw const EdgeError(null, 'Something went wrong. Please try again.');
    }

    final data = response.data;
    if (data is Map<String, dynamic>) {
      final failure = _decodeError(data);
      if (failure != null) throw failure;
      return data;
    }
    return const {};
  }

  /// Functions report failures as `{"error": {"code": …, "message": …}}`.
  EdgeError? _decodeError(Object? payload) {
    if (payload is! Map) return null;
    final error = payload['error'];
    if (error is! Map) return null;
    return EdgeError(
      error['code'] as String?,
      error['message'] as String? ?? _unavailable,
    );
  }
}
