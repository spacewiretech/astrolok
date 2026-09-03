import 'package:go_router/go_router.dart';

import '../features/birth/birth_view.dart';
import '../features/home/home_view.dart';
import '../features/onboarding/onboarding_state.dart';
import '../features/onboarding/onboarding_view.dart';
import '../features/payment_status/payment_outcome.dart';
import '../features/payment_status/payment_status_view.dart';
import '../features/splash/splash_view.dart';
import '../features/splash/splash_viewmodel.dart';
import '../features/subscription/subscription_view.dart';
import 'entitlement_gate.dart';

abstract final class Routes {
  static const splash = '/';

  /// The three onboarding steps share one screen — a sliding hero over a bottom sheet whose
  /// contents change — so they share one route and carry the step in a query parameter.
  /// Use [onboardingAt] to build one.
  static const onboarding = '/onboarding';

  static const birth = '/birth';
  static const subscribe = '/subscribe';

  /// `:outcome` is a [PaymentOutcome] slug. Use [paymentStatusFor] to build one.
  static const paymentStatus = '/payment-status/:outcome';

  static const home = '/home';

  static String onboardingAt(OnboardingStep step) => '$onboarding?step=${step.name}';

  static String paymentStatusFor(PaymentOutcome outcome) =>
      '/payment-status/${outcome.slug}';
}

/// The route each resolved destination maps to.
///
/// Lives here so the splash and every onboarding step route identically for the same user.
extension SplashDestinationRoute on SplashDestination {
  String get route => switch (this) {
        SplashDestination.onboarding => Routes.onboarding,
        SplashDestination.name => Routes.onboardingAt(OnboardingStep.name),
        SplashDestination.birth => Routes.birth,
        SplashDestination.subscribe => Routes.subscribe,
        SplashDestination.home => Routes.home,
      };
}

/// Flat routes: the splash resolves the session and redirects, and each onboarding step decides
/// where it goes next, so there is no global redirect to keep in sync.
final appRouter = GoRouter(
  initialLocation: Routes.splash,
  routes: [
    GoRoute(path: Routes.splash, builder: (context, state) => const SplashView()),

    GoRoute(
      path: Routes.onboarding,
      builder: (context, state) => OnboardingView(
        initialStep: OnboardingStep.parse(state.uri.queryParameters['step']),
      ),
    ),

    // Before the paywall and therefore ungated: the user is not entitled yet, and wrapping this
    // would bounce them to /subscribe before they could give the date the readings need.
    GoRoute(path: Routes.birth, builder: (context, state) => const BirthView()),

    GoRoute(path: Routes.subscribe, builder: (context, state) => const SubscriptionView()),

    // Ungated: a failed or pending payment is precisely the case where the user is not
    // entitled, so wrapping this in EntitlementGate would bounce them straight back to the
    // paywall they just came from and they would never see the outcome.
    GoRoute(
      path: Routes.paymentStatus,
      builder: (context, state) => PaymentStatusView(
        outcome: PaymentOutcome.parse(state.pathParameters['outcome']),
      ),
    ),

    // Everything past the paywall is wrapped, so a trial that runs out mid-session bounces the
    // user back to /subscribe instead of being noticed only at the next cold start.
    GoRoute(
      path: Routes.home,
      builder: (context, state) => const EntitlementGate(child: HomeView()),
    ),
  ],
);
