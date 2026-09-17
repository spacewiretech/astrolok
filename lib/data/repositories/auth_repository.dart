import '../models/app_user.dart';

/// Phone + OTP onboarding. Backed by a fake today; the Supabase implementation will wrap
/// `supabase.auth.signInWithOtp` / `verifyOTP` behind the same three calls.
abstract interface class AuthRepository {
  /// The signed-in user, or null when onboarding has not finished.
  Future<AppUser?> currentUser();

  /// Sends a fresh code. Throws [OtpSendException] when the provider refuses.
  Future<void> sendOtp(String phone);

  /// Redelivers the code from the last [sendOtp] rather than issuing a new one, falling back
  /// to a fresh send once the provider's redelivery window has closed.
  Future<void> resendOtp(String phone);

  /// Returns the user record created (or re-loaded) for [phone].
  ///
  /// Throws [InvalidOtpException] when the code does not match, [OtpExpiredException] when it
  /// has aged out or was already used.
  Future<AppUser> verifyOtp({required String phone, required String code});

  /// Stores the name and date of birth collected together after payment.
  ///
  /// One call rather than one per field, because they are one screen and one Continue: two
  /// requests would leave a half-saved account whenever the second one failed. [birthDate]'s time
  /// component is ignored — the server column is a `date`.
  Future<AppUser> saveDetails({required String name, required DateTime birthDate});

  /// Sets the language Astro replies in, or clears it back to the configured default.
  ///
  /// Server-side rather than a local preference: the prompt is assembled in the Edge Function,
  /// so the choice has to be somewhere the function can read. It following the user onto a new
  /// phone is the part they would notice.
  Future<AppUser> saveChatLanguage(String? language);

  /// Sets the hour of birth as `HH:MM`, or clears it with null.
  ///
  /// Returns the whole user because the server answers with the chart recomputed from it — which
  /// is the point: the sign Profile shows and the sign the chat reads from are one computation.
  Future<AppUser> saveBirthTime(String? time);

  /// Profile → "Offers & reminders". [optOut] true stops marketing pushes; a kundali that is ready
  /// or a failed autopay still arrives.
  Future<AppUser> saveMarketingOptOut(bool optOut);

  Future<void> signOut();
}

/// The code was wrong. The user can retry with the same code still outstanding.
class InvalidOtpException implements Exception {
  const InvalidOtpException([this.message = 'That code is not right. Try again.']);

  final String message;

  @override
  String toString() => message;
}

/// The code aged out or was already used — retrying is pointless, a resend is needed.
class OtpExpiredException implements Exception {
  const OtpExpiredException([
    this.message = 'That code has expired. Tap resend to get a new one.',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// The SMS could not be sent. [message] is already safe to show on screen.
class OtpSendException implements Exception {
  const OtpSendException(this.message);

  final String message;

  @override
  String toString() => message;
}
