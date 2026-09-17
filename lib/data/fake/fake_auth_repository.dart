import '../fast2sms/fast2sms_client.dart';
import '../models/app_user.dart';
import '../repositories/auth_repository.dart';
import 'fake_session.dart';

/// Accepts any 6-digit code, so the onboarding flow is walkable on a checkout with no backend
/// configured at all. Swapped out by `data/providers.dart` as soon as Supabase has keys.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this._session);

  final FakeSession _session;

  @override
  Future<AppUser?> currentUser() async {
    await FakeSession.latency(250);
    return _session.user;
  }

  @override
  Future<void> sendOtp(String phone) => FakeSession.latency(600);

  @override
  Future<void> resendOtp(String phone) => FakeSession.latency(600);

  @override
  Future<AppUser> verifyOtp({required String phone, required String code}) async {
    await FakeSession.latency(600);
    if (code.length != Fast2SmsClient.otpLength || int.tryParse(code) == null) {
      throw const InvalidOtpException();
    }
    final user = AppUser(id: 'local-user', phone: phone);
    _session.user = user;
    return user;
  }

  @override
  Future<AppUser> saveDetails({required String name, required DateTime birthDate}) async {
    await FakeSession.latency();
    final user = _current().copyWith(
      name: name.trim(),
      // Normalised to midnight, matching what a Postgres `date` round-trips as.
      birthDate: DateTime(birthDate.year, birthDate.month, birthDate.day),
    );
    _session.user = user;
    return user;
  }

  @override
  Future<AppUser> saveChatLanguage(String? language) async {
    await FakeSession.latency();
    final trimmed = language?.trim();
    final user = _current().copyWith(
      chatLanguage: trimmed,
      // Null means "back to the configured default", which `copyWith`'s `??` would otherwise
      // read as "leave it alone".
      clearChatLanguage: trimmed == null || trimmed.isEmpty,
    );
    _session.user = user;
    return user;
  }

  @override
  Future<AppUser> saveBirthTime(String? time) async {
    await FakeSession.latency();
    final trimmed = time?.trim();
    // No chart: there is no server here to compute one, and an invented sign is the one thing
    // Profile must never show.
    final user = _current().copyWith(
      birthTime: trimmed,
      clearBirthTime: trimmed == null || trimmed.isEmpty,
    );
    _session.user = user;
    return user;
  }

  @override
  Future<AppUser> saveMarketingOptOut(bool optOut) async {
    await FakeSession.latency();
    final user = _current().copyWith(pushMarketingOptOut: optOut);
    _session.user = user;
    return user;
  }

  AppUser _current() =>
      _session.user ?? const AppUser(id: 'local-user', phone: '');

  @override
  Future<void> signOut() async {
    await FakeSession.latency(200);
    _session.reset();
  }
}
