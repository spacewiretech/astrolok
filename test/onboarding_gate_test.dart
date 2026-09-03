import 'package:astrolok/data/models/app_user.dart';
import 'package:astrolok/features/splash/splash_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('destinationForSession', () {
    test('a signed-out user starts at onboarding', () {
      expect(
        destinationForSession(
          signedIn: false,
          hasName: false,
          hasBirthDate: false,
          entitled: false,
        ),
        SplashDestination.onboarding,
      );
    });

    test('a signed-in user with no name resumes at the name step', () {
      expect(
        destinationForSession(
          signedIn: true,
          hasName: false,
          hasBirthDate: false,
          entitled: false,
        ),
        SplashDestination.name,
      );
    });

    test('the birth date is asked for before the paywall', () {
      // Deliberate: collecting it after payment would mean charging someone before knowing
      // whether they will hand over the one input every reading needs.
      expect(
        destinationForSession(
          signedIn: true,
          hasName: true,
          hasBirthDate: false,
          entitled: false,
        ),
        SplashDestination.birth,
      );
    });

    test('an unentitled user with a complete profile lands on the paywall', () {
      expect(
        destinationForSession(
          signedIn: true,
          hasName: true,
          hasBirthDate: true,
          entitled: false,
        ),
        SplashDestination.subscribe,
      );
    });

    test('a complete, entitled user goes home', () {
      expect(
        destinationForSession(
          signedIn: true,
          hasName: true,
          hasBirthDate: true,
          entitled: true,
        ),
        SplashDestination.home,
      );
    });

    test('an entitled user who somehow has no birth date is still asked for it', () {
      // Order matters: a returning subscriber from a build that predated this screen has a live
      // subscription and no date, and must be asked rather than dropped into a broken home.
      expect(
        destinationForSession(
          signedIn: true,
          hasName: true,
          hasBirthDate: false,
          entitled: true,
        ),
        SplashDestination.birth,
      );
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

    test('a null user is signed out', () {
      expect(destinationForUser(null), SplashDestination.onboarding);
    });
  });
}
