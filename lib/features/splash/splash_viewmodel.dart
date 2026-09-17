import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics_events.dart';
import '../../data/entitlement.dart';
import '../../data/models/app_user.dart';
import '../../data/providers.dart';

/// Where the app should land once the splash has resolved the stored session.
enum SplashDestination { onboarding, language, subscribe, birth, home }

/// Where onboarding resumes for a user in this state.
///
/// Every step that ends holding a fresh [AppUser] routes through here, so the splash, the OTP
/// step, the language step and the name-and-birth step cannot disagree about where the same user
/// belongs. Routing by step order instead is what sends a returning subscriber back to the paywall
/// they already paid at.
SplashDestination destinationForSession({
  required bool signedIn,
  required bool entitled,
  required bool hasLanguage,
  required bool hasName,
  required bool hasBirthDate,
}) {
  if (!signedIn) return SplashDestination.onboarding;
  // Entitlement is computed by the server from payment_type plus the trial and period dates —
  // a trial that has lapsed lands here exactly like an account that never paid.
  if (!entitled) {
    // The language is the one thing asked before the paywall: it is what the paywall's promise
    // of readings is going to be written in, and it is one tap. Only for someone who has never
    // chosen — a subscriber who never picked keeps following the configured default and is never
    // stopped to be asked.
    return hasLanguage ? SplashDestination.subscribe : SplashDestination.language;
  }
  // Name and birth date come after payment, so nothing stands between a new account and the
  // paywall but the language. Readings still need the date, so a paid account without it is held
  // here rather than let into Home.
  if (!hasName || !hasBirthDate) return SplashDestination.birth;
  return SplashDestination.home;
}

/// [destinationForSession] for a resolved [user].
SplashDestination destinationForUser(AppUser? user) => destinationForSession(
      signedIn: user != null,
      entitled: user?.entitled ?? false,
      hasLanguage: user?.chatLanguage != null,
      hasName: user?.hasName ?? false,
      hasBirthDate: user?.hasBirthDate ?? false,
    );

/// Where a completed checkout goes: the name-and-birth step when either is missing, else Home.
///
/// Deliberately blind to [AppUser.entitled]. The paywall confirms a payment without refreshing
/// `entitlementProvider`, so the user held there straight after checkout still reads as
/// unentitled, and [destinationForUser] would send them back to the paywall they just paid at.
/// Name and birth date are never set before payment, so the cached user has those right. Anyone
/// whose payment did not really land is caught by the birth step's save, which routes from the
/// fresh server user, or by the gate on Home.
SplashDestination destinationAfterPayment(AppUser? user) =>
    (user?.hasName ?? false) && (user?.hasBirthDate ?? false)
        ? SplashDestination.home
        : SplashDestination.birth;

final splashDestinationProvider = FutureProvider.autoDispose<SplashDestination>((ref) async {
  final startedAt = DateTime.now();
  final user = await ref.watch(authRepositoryProvider).currentUser();
  // Cached-user fallbacks are re-derived from their stored dates by SessionStore, so an offline
  // launch cannot walk in on an entitlement that expired while the device had no signal.
  ref.read(entitlementProvider.notifier).set(user);
  final destination = destinationForUser(user);

  // The first fork in every session, and the only place the whole account state is known at
  // once. `ms` is here because this is the one screen the user waits on before seeing anything:
  // a slow session restore reads to them as a slow app.
  ref.read(analyticsProvider).track(Ev.splashResolved, {
    P.destination: destination.name,
    P.isSignedIn: user != null,
    P.entitled: user?.entitled ?? false,
    P.hasLanguage: user?.chatLanguage != null,
    P.hasName: user?.hasName ?? false,
    P.hasBirthDate: user?.hasBirthDate ?? false,
    P.paymentType: user?.paymentType.name,
    P.ms: DateTime.now().difference(startedAt).inMilliseconds,
  });

  return destination;
});
