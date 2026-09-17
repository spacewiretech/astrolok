import 'package:astrolok/data/models/app_user.dart';
import 'package:astrolok/features/splash/splash_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SplashDestination at({
    bool signedIn = true,
    bool entitled = false,
    bool hasLanguage = false,
    bool hasName = false,
    bool hasBirthDate = false,
  }) =>
      destinationForSession(
        signedIn: signedIn,
        entitled: entitled,
        hasLanguage: hasLanguage,
        hasName: hasName,
        hasBirthDate: hasBirthDate,
      );

  group('destinationForSession', () {
    test('a signed-out user starts at onboarding', () {
      expect(at(signedIn: false), SplashDestination.onboarding);
    });

    test('a new account is asked for its language first', () {
      expect(at(), SplashDestination.language);
    });

    test('the paywall needs only a language — no name, no birth date', () {
      // Deliberate: the name and date come after payment, so nothing else stands between a new
      // account and the paywall.
      expect(at(hasLanguage: true), SplashDestination.subscribe);
    });

    test('an unentitled user with a complete profile lands on the paywall', () {
      expect(
        at(hasLanguage: true, hasName: true, hasBirthDate: true),
        SplashDestination.subscribe,
      );
    });

    test('a paid account without a name or birth date is asked for them', () {
      expect(at(entitled: true, hasLanguage: true), SplashDestination.birth);
      expect(
        at(entitled: true, hasLanguage: true, hasName: true),
        SplashDestination.birth,
      );
      expect(
        at(entitled: true, hasLanguage: true, hasBirthDate: true),
        SplashDestination.birth,
      );
    });

    test('a complete, entitled user goes home', () {
      expect(
        at(entitled: true, hasLanguage: true, hasName: true, hasBirthDate: true),
        SplashDestination.home,
      );
    });

    test('a subscriber who never picked a language is not stopped to pick one', () {
      // Most existing accounts have no language saved and follow the configured default. The
      // picker is for new signups; a subscriber opening the app must go straight in.
      expect(
        at(entitled: true, hasName: true, hasBirthDate: true),
        SplashDestination.home,
      );
      expect(at(entitled: true), SplashDestination.birth);
    });
  });

  group('destinationForUser', () {
    test('a returning subscriber skips every collection step', () {
      final user = AppUser(
        id: 'u1',
        phone: '9876543210',
        name: 'Asha',
        birthDate: DateTime(1994, 2, 28),
        paymentType: PaymentType.active,
        currentPeriodEnd: DateTime.now().add(const Duration(days: 20)),
        entitled: true,
      );
      expect(destinationForUser(user), SplashDestination.home);
    });

    test('a saved language is what moves a new account on to the paywall', () {
      const user = AppUser(id: 'u1', phone: '9876543210');
      expect(destinationForUser(user), SplashDestination.language);
      expect(
        destinationForUser(user.copyWith(chatLanguage: 'Tamil')),
        SplashDestination.subscribe,
      );
    });

    test('a null user is signed out', () {
      expect(destinationForUser(null), SplashDestination.onboarding);
    });
  });

  group('destinationAfterPayment', () {
    test('a first checkout goes on to the name and birth date', () {
      // The user held straight after checkout still reads as unentitled — the paywall does not
      // refresh it — which is exactly why this ignores entitlement.
      const user = AppUser(id: 'u1', phone: '9876543210', chatLanguage: 'Hindi');
      expect(destinationAfterPayment(user), SplashDestination.birth);
    });

    test('an account that already has both goes home', () {
      final user = AppUser(
        id: 'u1',
        phone: '9876543210',
        name: 'Asha',
        birthDate: DateTime(1994, 2, 28),
      );
      expect(destinationAfterPayment(user), SplashDestination.home);
    });

    test('either one missing still asks', () {
      const named = AppUser(id: 'u1', phone: '9876543210', name: 'Asha');
      expect(destinationAfterPayment(named), SplashDestination.birth);
      expect(destinationAfterPayment(null), SplashDestination.birth);
    });
  });
}
