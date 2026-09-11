import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics_events.dart';
import '../../data/entitlement.dart';
import '../../data/models/app_user.dart';
import '../../data/providers.dart';

/// Where the app should land once the splash has resolved the stored session.
enum SplashDestination { onboarding, name, birth, subscribe, home }

/// Where onboarding resumes for a user in this state.
///
/// Every step that ends holding a fresh [AppUser] routes through here, so the splash, the OTP
/// step, the name step and the birth step cannot disagree about where the same user belongs.
/// Routing by step order instead is what sends a returning subscriber back to the paywall they
/// already paid at.
SplashDestination destinationForSession({
  required bool signedIn,
  required bool hasName,
  required bool hasBirthDate,
  required bool entitled,
}) {
  if (!signedIn) return SplashDestination.onboarding;
  if (!hasName) return SplashDestination.name;
  // Asked before the paywall, because the birth date is what the app is selling readings on —
  // collecting it after payment would mean charging someone before knowing whether they will
  // hand it over.
  if (!hasBirthDate) return SplashDestination.birth;
  // Entitlement is computed by the server from payment_type plus the trial and period dates —
  // a trial that has lapsed lands here exactly like an account that never paid.
  if (!entitled) return SplashDestination.subscribe;
  return SplashDestination.home;
}

/// [destinationForSession] for a resolved [user].
SplashDestination destinationForUser(AppUser? user) => destinationForSession(
      signedIn: user != null,
      hasName: user?.hasName ?? false,
      hasBirthDate: user?.hasBirthDate ?? false,
      entitled: user?.entitled ?? false,
    );

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
    P.hasName: user?.hasName ?? false,
    P.hasBirthDate: user?.hasBirthDate ?? false,
    P.paymentType: user?.paymentType.name,
    P.ms: DateTime.now().difference(startedAt).inMilliseconds,
  });

  return destination;
});
