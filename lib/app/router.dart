import 'analytics_observer.dart';
import 'package:go_router/go_router.dart';

import '../data/models/face_reading.dart';
import '../data/models/palm_reading.dart';
import '../features/birth/birth_view.dart';
import '../features/cancellation/cancellation_reason_view.dart';
import '../features/chat/chat_view.dart';
import '../features/face/face_capture_view.dart';
import '../features/face/face_capture_viewmodel.dart';
import '../features/face/face_part_view.dart';
import '../features/face/face_reading_view.dart';
import '../features/face/face_scan_view.dart';
import '../features/home/home_view.dart';
import '../features/kundali/kundali_form_view.dart';
import '../features/kundali/kundali_gate_view.dart';
import '../features/kundali/kundali_report_view.dart';
import '../features/kundali/kundali_waiting_view.dart';
import '../features/language/language_view.dart';
import '../features/palm/palm_capture_view.dart';
import '../features/palm/palm_capture_viewmodel.dart';
import '../features/palm/palm_line_view.dart';
import '../features/palm/palm_reading_view.dart';
import '../features/palm/palm_scan_view.dart';
import '../features/onboarding/onboarding_state.dart';
import '../features/onboarding/onboarding_view.dart';
import '../features/payment_status/payment_outcome.dart';
import '../features/profile/downloads_view.dart';
import '../features/profile/memory_view.dart';
import '../features/profile/profile_view.dart';
import '../features/referral/referral_view.dart';
import '../features/payment_status/payment_status_view.dart';
import '../features/splash/splash_view.dart';
import '../features/splash/splash_viewmodel.dart';
import '../features/subscription/subscription_view.dart';
import 'entitlement_gate.dart';

abstract final class Routes {
  static const splash = '/';

  /// The phone and OTP steps share one screen — a sliding hero over a bottom sheet whose
  /// contents change — so they share one route and carry the step in a query parameter.
  /// Use [onboardingAt] to build one.
  static const onboarding = '/onboarding';

  /// Which language Astro answers in. After OTP, before the paywall.
  static const language = '/language';

  static const subscribe = '/subscribe';

  /// Name and date of birth, on one screen, after payment.
  static const birth = '/birth';

  /// `:outcome` is a [PaymentOutcome] slug. Use [paymentStatusFor] to build one.
  static const paymentStatus = '/payment-status/:outcome';

  static const home = '/home';

  /// The palm flow. Three steps and a per-line detail, hierarchical so that popping from a
  /// line lands on its reading and popping from a reading lands on Home.
  static const palmCapture = '/palm';
  static const palmScan = '/palm/scan';

  /// `:id` is a reading id. Use [palmReadingFor].
  static const palmReading = '/palm/reading/:id';

  /// `:line` is a [PalmLineKind] name. Use [palmLineFor].
  static const palmLine = '/palm/reading/:id/line/:line';

  /// The face flow, shaped exactly like the palm one so that popping from a feature lands on
  /// its reading and popping from a reading lands on Home.
  static const faceCapture = '/face';
  static const faceScan = '/face/scan';

  /// `:id` is a reading id. Use [faceReadingFor].
  static const faceReading = '/face/reading/:id';

  /// `:part` is a [FacePartKind] name. Use [facePartFor].
  static const facePart = '/face/reading/:id/part/:part';

  /// The conversations with Astro. One route for all of them: which is on screen lives in
  /// `selectedThreadProvider`, not here, because a conversation that has not been sent yet has no
  /// id to put in a URL — and replacing the route once the server supplied one would remount the
  /// screen with the first reply still in flight. See `ChatViewModel` for the whole argument.
  ///
  /// An opening question is handed over in `extra`, the way the scan screens take their prepared
  /// image; it always starts a new conversation.
  static const chat = '/chat';

  /// The account. Nested so that popping from Downloads lands on the profile.
  static const profile = '/profile';
  static const downloads = '/profile/downloads';
  static const memory = '/profile/memory';

  /// Invite friends. Nested under the profile like the two above, so popping lands there.
  ///
  /// Note this is *not* the referral link's path — that is `/r/<CODE>` on the website, and it
  /// deliberately never becomes a route in this app. An incoming link is read as data by
  /// `attribution_service.dart` and the splash still decides where the user goes; routing
  /// straight to a screen would walk them past the session gate.
  static const invite = '/profile/invite';

  /// The kundali. `/kundali` decides between the form, the wait and the reveal — it is what the Home
  /// card falls back to and what a push opens. The other three are the screens themselves.
  static const kundali = '/kundali';
  static const kundaliNew = '/kundali/new';
  static const kundaliWaiting = '/kundali/waiting';
  static const kundaliReport = '/kundali/report';

  /// Why a subscription was cancelled. Opened by the `mid_cancel` push.
  static const leaving = '/leaving';

  /// The form, with `?edit=1` when it re-casts an existing kundali.
  static String kundaliForm({bool edit = false}) => edit ? '$kundaliNew?edit=1' : kundaliNew;

  static String onboardingAt(OnboardingStep step) => '$onboarding?step=${step.name}';

  static String paymentStatusFor(PaymentOutcome outcome) =>
      '/payment-status/${outcome.slug}';

  static String palmReadingFor(String id) => '/palm/reading/$id';

  static String palmLineFor(String id, PalmLineKind line) =>
      '/palm/reading/$id/line/${line.name}';

  static String faceReadingFor(String id) => '/face/reading/$id';

  static String facePartFor(String id, FacePartKind part) =>
      '/face/reading/$id/part/${part.name}';
}

/// The route each resolved destination maps to.
///
/// Lives here so the splash and every onboarding step route identically for the same user.
extension SplashDestinationRoute on SplashDestination {
  String get route => switch (this) {
        SplashDestination.onboarding => Routes.onboarding,
        SplashDestination.language => Routes.language,
        SplashDestination.subscribe => Routes.subscribe,
        SplashDestination.birth => Routes.birth,
        SplashDestination.home => Routes.home,
      };
}

/// Flat routes: the splash resolves the session and redirects, and each onboarding step decides
/// where it goes next, so there is no global redirect to keep in sync.
final appRouter = GoRouter(
  initialLocation: Routes.splash,
  // One observer covers every screen and modal in the table below, which is the whole
  // reason for doing it here rather than in eighteen initStates: a screen added next month
  // is instrumented the moment it is routable.
  observers: [analyticsObserver],
  routes: [
    GoRoute(path: Routes.splash, builder: (context, state) => const SplashView()),

    GoRoute(
      path: Routes.onboarding,
      builder: (context, state) => OnboardingView(
        initialStep: OnboardingStep.parse(state.uri.queryParameters['step']),
      ),
    ),

    // Before the paywall and therefore ungated: the user is not entitled yet, and wrapping this
    // would bounce them to /subscribe before they could choose.
    GoRoute(path: Routes.language, builder: (context, state) => const LanguageView()),

    GoRoute(path: Routes.subscribe, builder: (context, state) => const SubscriptionView()),

    // After the paywall, but still ungated. Straight after checkout the app is holding the user
    // from before the payment — the paywall does not refresh it — so a gate here would read them
    // as unentitled and bounce them to the paywall they just paid at. The screen's save answers
    // with the fresh server user and routes from that, so an unpaid account still ends up on
    // /subscribe, and Home is gated regardless.
    GoRoute(path: Routes.birth, builder: (context, state) => const BirthView()),

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

    // Gated like Home: a reading costs money to produce, and the server refuses one for a
    // lapsed account anyway, so a trial that runs out mid-flow should bounce here rather than
    // at the point of asking.
    GoRoute(
      path: Routes.palmCapture,
      builder: (context, state) => const EntitlementGate(child: PalmCaptureView()),
    ),

    // The prepared image is handed over in `extra` rather than being re-read from disk: it is
    // already in memory, and a scan that started is a scan the user is waiting on.
    GoRoute(
      path: Routes.palmScan,
      builder: (context, state) => EntitlementGate(
        child: PalmScanView(request: state.extra as PalmScanRequest?),
      ),
    ),

    GoRoute(
      path: Routes.palmReading,
      builder: (context, state) => EntitlementGate(
        child: PalmReadingView(readingId: state.pathParameters['id'] ?? ''),
      ),
    ),

    GoRoute(
      path: Routes.palmLine,
      builder: (context, state) => EntitlementGate(
        child: PalmLineView(
          readingId: state.pathParameters['id'] ?? '',
          line: PalmLineKind.values.asNameMap()[state.pathParameters['line']],
        ),
      ),
    ),

    // The face flow, gated for the same reasons as the palm one: a reading costs money to
    // produce, and the server refuses one for a lapsed account anyway.
    GoRoute(
      path: Routes.faceCapture,
      builder: (context, state) => const EntitlementGate(child: FaceCaptureView()),
    ),

    GoRoute(
      path: Routes.faceScan,
      builder: (context, state) => EntitlementGate(
        child: FaceScanView(request: state.extra as FaceScanRequest?),
      ),
    ),

    GoRoute(
      path: Routes.faceReading,
      builder: (context, state) => EntitlementGate(
        child: FaceReadingView(readingId: state.pathParameters['id'] ?? ''),
      ),
    ),

    // Gated like the readings: a turn costs money, and the server refuses one for a lapsed
    // account anyway.
    GoRoute(
      path: Routes.chat,
      // Two kinds of caller, and the cast has to survive both. The in-app "Ask Astro" buttons pass a
      // bare String and mean "send this now"; a drip push passes a [ChatLaunch] and usually means
      // "put it in the composer". `as String?` alone would throw on the second.
      builder: (context, state) {
        final extra = state.extra;
        final launch = switch (extra) {
          ChatLaunch() => extra,
          final String text when text.isNotEmpty =>
            ChatLaunch(question: text, source: 'reading', autoSend: true),
          _ => null,
        };
        return EntitlementGate(child: ChatView(launch: launch));
      },
    ),

    // The account. Gated like Home: everything reachable from here is behind the paywall, and
    // a lapsed user belongs on /subscribe rather than on a page telling them their plan ended.
    GoRoute(
      path: Routes.profile,
      builder: (context, state) => const EntitlementGate(child: ProfileView()),
    ),

    GoRoute(
      path: Routes.downloads,
      builder: (context, state) => const EntitlementGate(child: DownloadsView()),
    ),

    GoRoute(
      path: Routes.memory,
      builder: (context, state) => const EntitlementGate(child: MemoryView()),
    ),

    // Gated like the rest of the account section: an invite screen is reached from the profile,
    // and a lapsed user belongs on /subscribe rather than being invited to recruit others.
    GoRoute(
      path: Routes.invite,
      builder: (context, state) => const EntitlementGate(child: ReferralView()),
    ),

    // The kundali. Gated like the readings: casting one writes a reading that costs money, and the
    // server refuses every action for a lapsed account anyway.
    GoRoute(
      path: Routes.kundali,
      builder: (context, state) => const EntitlementGate(child: KundaliGateView()),
    ),
    GoRoute(
      path: Routes.kundaliNew,
      builder: (context, state) => EntitlementGate(
        child: KundaliFormView(edit: state.uri.queryParameters['edit'] == '1'),
      ),
    ),
    GoRoute(
      path: Routes.kundaliWaiting,
      builder: (context, state) => const EntitlementGate(child: KundaliWaitingView()),
    ),
    GoRoute(
      path: Routes.kundaliReport,
      builder: (context, state) => const EntitlementGate(child: KundaliReportView()),
    ),

    // UNGATED, like /payment-status and for a sharper reason: a trial user who cancels loses access
    // the same minute, and this is the screen that asks them why. Behind EntitlementGate it would
    // bounce exactly the person it exists for to the paywall.
    GoRoute(
      path: Routes.leaving,
      builder: (context, state) => CancellationReasonView(
        notificationId: state.uri.queryParameters['nid'],
      ),
    ),

    GoRoute(
      path: Routes.facePart,
      builder: (context, state) => EntitlementGate(
        child: FacePartView(
          readingId: state.pathParameters['id'] ?? '',
          part: FacePartKind.values.asNameMap()[state.pathParameters['part']],
        ),
      ),
    ),
  ],
);
