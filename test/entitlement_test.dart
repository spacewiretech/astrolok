import 'package:astrolok/app/theme/app_theme.dart';
import 'package:astrolok/data/entitlement.dart';
import 'package:astrolok/data/language.dart';
import 'package:astrolok/data/models/app_user.dart';
import 'package:astrolok/data/providers.dart';
import 'package:astrolok/data/repositories/app_config_repository.dart';
import 'package:astrolok/data/repositories/auth_repository.dart';
import 'package:astrolok/features/profile/profile_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppUser user({
    required PaymentType type,
    DateTime? trialEndsAt,
    DateTime? currentPeriodEnd,
    bool entitled = false,
    bool? trialAvailable,
  }) {
    return AppUser(
      id: 'u1',
      phone: '9876543210',
      paymentType: type,
      trialEndsAt: trialEndsAt,
      currentPeriodEnd: currentPeriodEnd,
      entitled: entitled,
      trialAvailable: trialAvailable,
    );
  }

  final now = DateTime(2026, 9, 3, 12);

  group('recomputeOffline', () {
    test('a trial that ended more than the grace ago is not entitled', () {
      final lapsed = user(
        type: PaymentType.trial,
        trialEndsAt: now.subtract(const Duration(hours: 3)),
        entitled: true,
      );
      expect(lapsed.recomputeOffline(now).entitled, isFalse);
    });

    test('a trial inside the two-hour offline grace is still entitled', () {
      final justOver = user(
        type: PaymentType.trial,
        trialEndsAt: now.subtract(const Duration(minutes: 90)),
        entitled: true,
      );
      expect(justOver.recomputeOffline(now).entitled, isTrue);
    });

    test('a new account with no trial date is never entitled', () {
      // This is the state every signup is in before the mandate is authorised, and it is what
      // puts them on the paywall.
      expect(user(type: PaymentType.none, entitled: true).recomputeOffline(now).entitled,
          isFalse);
      // The pre-`none` spelling of the same account. Rows written before the backfill still
      // arrive this way, and must keep landing on the paywall.
      expect(user(type: PaymentType.trial, entitled: true).recomputeOffline(now).entitled,
          isFalse);
    });

    test('none ignores the dates entirely', () {
      // Not merely "null dates grant nothing". An account that never authorised a mandate is not
      // entitled even if a stale cache carries dates from somewhere, because `none` is the
      // strongest statement the row can make and the server agrees.
      final withDates = user(
        type: PaymentType.none,
        trialEndsAt: now.add(const Duration(days: 1)),
        currentPeriodEnd: now.add(const Duration(days: 30)),
        entitled: true,
      );
      expect(withDates.recomputeOffline(now).entitled, isFalse);
      expect(withDates.entitlementExpiresAt, isNull);
    });

    test('an active mandate that has not billed yet is entitled', () {
      // The window between authorisation and the first debit leaves current_period_end null.
      expect(user(type: PaymentType.active, entitled: true).recomputeOffline(now).entitled,
          isTrue);
    });

    test('a cancelled mandate gets no grace past its paid period', () {
      final cancelled = user(
        type: PaymentType.cancelled,
        currentPeriodEnd: now.subtract(const Duration(minutes: 1)),
        entitled: true,
      );
      expect(cancelled.recomputeOffline(now).entitled, isFalse);
    });

    test('a cancelled mandate inside its paid period is still entitled', () {
      final cancelled = user(
        type: PaymentType.cancelled,
        currentPeriodEnd: now.add(const Duration(days: 10)),
      );
      expect(cancelled.recomputeOffline(now).entitled, isTrue);
    });

    test('expired is never entitled, whatever the dates say', () {
      final expired = user(
        type: PaymentType.expired,
        currentPeriodEnd: now.add(const Duration(days: 30)),
        entitled: true,
      );
      expect(expired.recomputeOffline(now).entitled, isFalse);
    });
  });

  group('fromServer', () {
    test('parses the entitlement payload', () {
      final parsed = AppUser.fromServer({
        'user_id': 'abc',
        'mobile_no': '9876543210',
        'name': 'Asha',
        'dob': '1994-02-28',
        'payment_type': 'active',
        'current_period_end': '2026-10-03T00:00:00Z',
        'entitled': true,
        'billing_state': 'on_hold',
      });

      expect(parsed, isNotNull);
      expect(parsed!.name, 'Asha');
      expect(parsed.birthDate, DateTime(1994, 2, 28));
      expect(parsed.paymentType, PaymentType.active);
      expect(parsed.entitled, isTrue);
      // A warning, not a gate — an on-hold mandate must not revoke access.
      expect(parsed.billingState, BillingState.onHold);
    });

    test('returns null rather than throwing on a payload it does not recognise', () {
      expect(AppUser.fromServer({'oops': true}), isNull);
      expect(AppUser.fromServer('not a map'), isNull);
      expect(AppUser.fromServer(null), isNull);
    });

    test('an unknown payment_type falls back to trial, which grants nothing', () {
      final parsed = AppUser.fromServer({
        'user_id': 'abc',
        'payment_type': 'something_new',
      });
      expect(parsed!.paymentType, PaymentType.trial);
      expect(parsed.recomputeOffline(now).entitled, isFalse);
    });

    test('parses none, and the trial_available flag beside it', () {
      final parsed = AppUser.fromServer({
        'user_id': 'abc',
        'payment_type': 'none',
        'entitled': false,
        'trial_available': true,
      });
      expect(parsed!.paymentType, PaymentType.none);
      expect(parsed.isTrialAvailable, isTrue);
      expect(parsed.hasEverSubscribed, isFalse);
    });
  });

  group('trial availability', () {
    test('a fresh account is owed the trial', () {
      expect(user(type: PaymentType.none).hasEverSubscribed, isFalse);
      expect(user(type: PaymentType.none).isTrialAvailable, isTrue);
    });

    test('every other state has already spent it', () {
      for (final type in [
        PaymentType.trial,
        PaymentType.active,
        PaymentType.expired,
        PaymentType.cancelled,
      ]) {
        expect(user(type: type).hasEverSubscribed, isTrue, reason: type.name);
        expect(user(type: type).isTrialAvailable, isFalse, reason: type.name);
      }
    });

    test('the server has the last word, in both directions', () {
      // What the client would have concluded on its own is irrelevant once the server has
      // answered — `subscription-start` authorises from the same field, so a disagreement here
      // is a paywall advertising one price and a mandate charging another.
      expect(user(type: PaymentType.none, trialAvailable: false).isTrialAvailable, isFalse);
      expect(user(type: PaymentType.cancelled, trialAvailable: true).isTrialAvailable, isTrue);
    });

    test('a payload without the field falls back to the dates', () {
      // A response from a server that predates `trial_available`, or the fake repository. The
      // fallback has to land where the old client-side rule did.
      final spent = AppUser.fromServer({
        'user_id': 'abc',
        'payment_type': 'cancelled',
        'trial_ends_at': '2026-09-01T00:00:00Z',
      });
      expect(spent!.trialAvailable, isNull);
      expect(spent.isTrialAvailable, isFalse);
    });
  });

  group('birth date', () {
    test('round-trips through the wire format', () {
      final date = DateTime(2001, 7, 4);
      expect(AppUser.formatBirthDate(date), '2001-07-04');
      expect(AppUser.parseBirthDate('2001-07-04'), date);
    });

    test('rejects a date that does not exist instead of rolling it forward', () {
      // DateTime(2023, 2, 31) silently becomes 3 March, which would store the wrong birthday.
      expect(AppUser.parseBirthDate('2023-02-31'), isNull);
      expect(AppUser.parseBirthDate('2023-13-01'), isNull);
    });

    test('accepts 29 February in a leap year', () {
      expect(AppUser.parseBirthDate('2024-02-29'), DateTime(2024, 2, 29));
    });

    test('rejects malformed input', () {
      expect(AppUser.parseBirthDate(''), isNull);
      expect(AppUser.parseBirthDate('yesterday'), isNull);
      expect(AppUser.parseBirthDate('2001-07'), isNull);
      expect(AppUser.parseBirthDate(42), isNull);
    });

    test('hasBirthDate drives the onboarding gate', () {
      expect(user(type: PaymentType.trial).hasBirthDate, isFalse);
      expect(
        AppUser(id: 'u1', phone: '9876543210', birthDate: DateTime(1990, 1, 1)).hasBirthDate,
        isTrue,
      );
    });
  });

  _pickerTests();
}

/// The store is write-only, so invalidating it is not a refetch — it is a wipe.
///
/// This is the shape of the bug these tests exist for: Profile used to `invalidate` after saving
/// a language, on the assumption that the provider would go and ask the server again. It has no
/// way to. `build` returns null, so the entitlement went null, and the screen read that as a
/// lapsed subscription — "Subscription Ended" on a paid-up account, until a restart.
void _pickerTests() {
  /// A paid-up account, a month into a subscription that runs to the new year.
  AppUser subscriber() => AppUser(
        id: 'u1',
        phone: '9876543210',
        name: 'Asha',
        paymentType: PaymentType.active,
        currentPeriodEnd: DateTime(2027, 1, 4),
        entitled: true,
      );

  ProviderContainer containerWith(AuthRepository auth) {
    final container = ProviderContainer(overrides: [
      appConfigRepositoryProvider.overrideWithValue(
        const _StaticConfig({
          chatLanguagesKey: 'English, Hindi, Tamil',
          chatLanguageDefaultKey: 'English',
        }),
      ),
      authRepositoryProvider.overrideWithValue(auth),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  /// Taps the language row and picks [language] out of the sheet, the way a user does.
  Future<void> pickLanguage(WidgetTester tester, String language) async {
    await tester.tap(find.text('Astro language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(language).last);
    await tester.pumpAndSettle();
  }

  testWidgets('picking a language leaves the plan card alone', (tester) async {
    // 900 tall so the whole list — plan card and menu both — is laid out without scrolling.
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth = _LanguageRepository(subscriber());
    final container = containerWith(auth);
    await container.read(appConfigProvider.future);
    container.read(entitlementProvider.notifier).set(subscriber());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const ProfileView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Premium Active'), findsOneWidget);

    await pickLanguage(tester, 'Hindi');

    expect(auth.saved, 'Hindi');
    // The regression. Before the fix the entitlement was null here, and every one of these
    // assertions failed at once — which is exactly how it looked on screen.
    expect(container.read(entitlementProvider)?.entitled, isTrue);
    expect(find.text('Premium Active'), findsOneWidget);
    expect(find.text('Subscription Ended'), findsNothing);
    expect(find.text('January 4, 2027'), findsOneWidget);
    // The name and the phone come off the same object, so they went with it.
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('+91 9876543210'), findsOneWidget);
  });

  testWidgets('the row shows the language that was just picked', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth = _LanguageRepository(subscriber());
    final container = containerWith(auth);
    await container.read(appConfigProvider.future);
    container.read(entitlementProvider.notifier).set(subscriber());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const ProfileView()),
      ),
    );
    await tester.pumpAndSettle();

    // Never chosen, so it follows `chat_language_default`.
    expect(container.read(languageProvider), 'English');

    await pickLanguage(tester, 'Tamil');

    // The other half of the same bug: a null entitlement re-resolved to the default, so the row
    // snapped back to English the instant it was set to anything else.
    expect(container.read(languageProvider), 'Tamil');
    expect(find.text('Tamil'), findsOneWidget);
  });
}

/// Answers with a fixed map, the way [analyticsProvider]'s tests do.
class _StaticConfig implements AppConfigRepository {
  const _StaticConfig(this._values);

  final Map<String, String> _values;

  @override
  Future<Map<String, String>> load({bool force = false, Duration? maxAge}) async => _values;

  @override
  Set<String> get remoteKeys => _values.keys.toSet();
}

/// Stands in for `update-profile`, which answers with the whole entitlement rather than just the
/// language — the fact the fix turns on. A repository that returned a bare language would hide
/// the bug rather than pin it.
class _LanguageRepository implements AuthRepository {
  _LanguageRepository(this._user);

  AppUser _user;

  /// What the last save was asked to store.
  String? saved;

  @override
  Future<AppUser> saveChatLanguage(String? language) async {
    saved = language?.trim();
    _user = _user.copyWith(
      chatLanguage: saved,
      clearChatLanguage: saved == null || saved!.isEmpty,
    );
    return _user;
  }

  @override
  Future<AppUser?> currentUser() async => _user;

  // Profile never reaches the rest.
  @override
  Future<void> sendOtp(String phone) => throw UnimplementedError();

  @override
  Future<void> resendOtp(String phone) => throw UnimplementedError();

  @override
  Future<AppUser> verifyOtp({required String phone, required String code}) =>
      throw UnimplementedError();

  @override
  Future<AppUser> saveName(String name) => throw UnimplementedError();

  @override
  Future<AppUser> saveBirthDate(DateTime date) => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();
}
