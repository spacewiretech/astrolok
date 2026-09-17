import 'package:astrolok/data/analytics/analytics.dart';
import 'package:astrolok/data/analytics/analytics_events.dart';
import 'package:astrolok/data/entitlement.dart';
import 'package:astrolok/data/models/app_user.dart';
import 'package:astrolok/data/providers.dart';
import 'package:astrolok/data/repositories/auth_repository.dart';
import 'package:astrolok/features/language/language_viewmodel.dart';
import 'package:astrolok/features/splash/splash_viewmodel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Auth auth;
  late _RecordingAnalytics analytics;
  late ProviderContainer container;

  setUp(() {
    auth = _Auth(const AppUser(id: 'u1', phone: '9876543210'));
    analytics = _RecordingAnalytics();
    container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      analyticsProvider.overrideWithValue(analytics),
    ]);
    addTearDown(container.dispose);
  });

  LanguageViewModel model() {
    // Held open for the test: the provider is autoDispose, and nothing else is listening.
    container.listen(languageViewModelProvider, (_, _) {});
    return container.read(languageViewModelProvider.notifier);
  }

  test('a choice saves, installs the fresh user and moves on to the paywall', () async {
    final next = await model().choose('Tamil');

    expect(auth.saved, 'Tamil');
    expect(container.read(entitlementProvider)?.chatLanguage, 'Tamil');
    expect(next, SplashDestination.subscribe);

    final state = container.read(languageViewModelProvider);
    expect(state.busy, isFalse);
    expect(state.selected, 'Tamil');
    expect(state.error, isNull);
  });

  test('signup completes here, once, after the choice is recorded', () async {
    await model().choose('Hinglish');

    expect(analytics.events, [Ev.languageSelected, Ev.signupCompleted]);
  });

  test('a failed save stays put, clears the check and says so', () async {
    auth.fail = true;

    final next = await model().choose('Kannada');

    expect(next, isNull);
    final state = container.read(languageViewModelProvider);
    expect(state.busy, isFalse);
    expect(state.selected, isNull);
    expect(state.error, isNotNull);
    // Not a signup: nothing was saved, and the screen will be shown again.
    expect(analytics.events, [Ev.languageSelected, Ev.languageSaveFailed]);
  });

  test('a second tap while the first is saving is ignored', () async {
    final vm = model();
    final first = vm.choose('English');
    final second = await vm.choose('Hindi');

    expect(second, isNull);
    expect(await first, SplashDestination.subscribe);
    expect(auth.saved, 'English');
  });
}

/// Stands in for `update-profile`, which answers with the whole user.
class _Auth implements AuthRepository {
  _Auth(this._user);

  AppUser _user;
  String? saved;
  bool fail = false;

  @override
  Future<AppUser> saveChatLanguage(String? language) async {
    await Future<void>.delayed(Duration.zero);
    if (fail) throw const OtpSendException('Could not save your language. Please try again.');
    saved = language;
    _user = _user.copyWith(chatLanguage: language);
    return _user;
  }

  @override
  Future<AppUser?> currentUser() async => _user;

  // The language screen never reaches the rest.
  @override
  Future<void> sendOtp(String phone) => throw UnimplementedError();

  @override
  Future<void> resendOtp(String phone) => throw UnimplementedError();

  @override
  Future<AppUser> verifyOtp({required String phone, required String code}) =>
      throw UnimplementedError();

  @override
  Future<AppUser> saveDetails({required String name, required DateTime birthDate}) =>
      throw UnimplementedError();

  @override
  Future<AppUser> saveBirthTime(String? time) => throw UnimplementedError();

  @override
  Future<AppUser> saveMarketingOptOut(bool optOut) => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();
}

class _RecordingAnalytics implements Analytics {
  final List<String> events = [];

  @override
  void track(String event, [Map<String, Object?> properties = const {}]) => events.add(event);

  @override
  void identify(AppUser user) {}

  @override
  void flush() {}

  @override
  void timeEvent(String event) {}

  @override
  void reset() {}

  @override
  void registerSuper(Map<String, Object?> properties) {}

  @override
  void trackCharge(double amount, [Map<String, Object?> properties = const {}]) {}
}
