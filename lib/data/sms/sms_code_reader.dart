import 'package:flutter/foundation.dart';
import 'package:smart_auth/smart_auth.dart';

/// A code read out of the OTP SMS, and how it was read.
@immutable
class SmsCode {
  const SmsCode(this.code, this.method);

  final String code;

  /// `sms_consent` or `sms_retriever` — the `entry_method` the verify events report.
  final String method;
}

/// Reads the OTP out of the incoming SMS so the user does not have to.
///
/// Android only. Two modes, because they need different things from the SMS:
///
///  * **User Consent** works with any OTP message. Android asks the user once, and one tap hands
///    the message over.
///  * **Retriever** needs no tap at all, but only fires for a message that ends with this app's
///    11-character signing hash. The Fast2SMS template decides the text, so this mode stays off
///    until the template carries the hash — see `sms_retriever_enabled` in `app_config`.
///
/// Never the only way in: typing and the keyboard's own suggestion keep working whatever happens
/// here, so every failure comes back as "no code" rather than as an exception.
abstract interface class SmsCodeReader {
  /// False where there is nothing to listen with: iOS, the web, a fake backend that sends no SMS.
  bool get available;

  /// Starts listening, and completes with the code — or with null when the user declined, the
  /// listener timed out, or the message held no code.
  ///
  /// Start this **before** the SMS is sent. Both APIs only see messages that arrive after listening
  /// begins, and a fast SMS can reach the phone before the OTP sheet reaches the screen.
  ///
  /// A later call replaces this one, and a replaced or cancelled call may never complete, so a
  /// caller must not wait on it for anything but the code.
  Future<SmsCode?> waitForCode({required bool retriever});

  /// Stops listening.
  Future<void> cancel();
}

/// The real reader, over `smart_auth`.
class SmartAuthSmsCodeReader implements SmsCodeReader {
  const SmartAuthSmsCodeReader({required this.length});

  /// Digits in a code, so a phone number or a date in the same message is never taken for one.
  final int length;

  static const consentMethod = 'sms_consent';
  static const retrieverMethod = 'sms_retriever';

  @override
  bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<SmsCode?> waitForCode({required bool retriever}) async {
    if (!available) return null;

    try {
      final auth = SmartAuth.instance;
      final result = retriever
          ? await auth.getSmsWithRetrieverApi()
          : await auth.getSmsWithUserConsentApi();

      final code = codeFrom(result.data?.sms, length);
      if (code == null) return null;
      return SmsCode(code, retriever ? retrieverMethod : consentMethod);
    } catch (error) {
      // smart_auth reports its own failures — a declined sheet, a timeout — as results, so this is
      // only a channel that is not there at all. Either way the user types the code, as before.
      debugPrint('[sms] could not read the code: $error');
      return null;
    }
  }

  @override
  Future<void> cancel() async {
    if (!available) return;

    try {
      await SmartAuth.instance.removeUserConsentApiListener();
      await SmartAuth.instance.removeSmsRetrieverApiListener();
    } catch (error) {
      debugPrint('[sms] could not stop listening: $error');
    }
  }

  /// The first run of exactly [length] digits in [sms], or null.
  ///
  /// Not smart_auth's default matcher, which takes the first 4 to 8 digits anywhere — the start of
  /// a helpline number, say. The word boundaries also keep the Retriever hash at the end of the
  /// message out of it, because its digits sit against letters.
  @visibleForTesting
  static String? codeFrom(String? sms, int length) {
    if (sms == null) return null;
    return RegExp('\\b\\d{$length}\\b').firstMatch(sms)?.group(0);
  }
}

/// Never finds a code. Stands in wherever there is no SMS to read.
class NoopSmsCodeReader implements SmsCodeReader {
  const NoopSmsCodeReader();

  @override
  bool get available => false;

  @override
  Future<SmsCode?> waitForCode({required bool retriever}) async => null;

  @override
  Future<void> cancel() async {}
}
