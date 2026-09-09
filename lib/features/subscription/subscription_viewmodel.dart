import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/models/app_user.dart';
import '../../data/models/subscription_offer.dart';
import '../../data/models/upi_app.dart';
import '../../data/providers.dart';
import '../../data/repositories/subscription_repository.dart';
import '../payment_status/payment_outcome.dart';

/// What the paywall is currently doing. Only [idle] accepts another tap.
enum SubscriptionPhase {
  idle,

  /// Asking the server for a mandate, then waiting on the UPI app.
  opening,

  /// Control is back and we are asking the server whether the money actually moved.
  confirming,
}

@immutable
class SubscriptionState {
  const SubscriptionState({
    this.offer,
    this.user,
    this.upiApps = const [],
    this.selectedAppId,
    this.loading = true,
    this.phase = SubscriptionPhase.idle,
    this.error,
  });

  final SubscriptionOffer? offer;

  /// Decides which offer to show: the trial, or the plain monthly price for someone whose
  /// trial has already been used.
  final AppUser? user;

  /// UPI apps installed on this device. Empty is normal — an iPhone with none, or a discovery
  /// call that failed — and means the paywall falls back to Cashfree's own checkout screen.
  final List<UpiApp> upiApps;

  final String? selectedAppId;

  final bool loading;
  final SubscriptionPhase phase;
  final String? error;

  bool get busy => phase != SubscriptionPhase.idle;
  bool get canSubscribe => !loading && offer != null && !busy;

  /// The app the button will launch, or null when there is nothing to launch and the Cashfree
  /// checkout screen has to stand in.
  UpiApp? get selectedApp {
    for (final app in upiApps) {
      if (app.id == selectedAppId) return app;
    }
    return null;
  }

  /// A returning subscriber — lapsed, cancelled, or a trial already spent — is not offered the
  /// trial price again. Only an account that has never authorised a mandate sees it.
  ///
  /// Read from the user the server sent rather than derived here. `subscription-start` makes this
  /// same call from the same field to decide what to authorise, so the price on the button, the
  /// UPI Autopay consent line and the amount actually charged cannot disagree — which they did,
  /// silently, for every returning subscriber.
  ///
  /// True with no user at all: a paywall that cannot say defaults to advertising the cheaper
  /// offer, and the server refuses to honour it if the account is not owed one.
  bool get trialAvailable => user?.isTrialAvailable ?? true;

  SubscriptionState copyWith({
    SubscriptionOffer? offer,
    AppUser? user,
    List<UpiApp>? upiApps,
    String? selectedAppId,
    bool? loading,
    SubscriptionPhase? phase,
    String? error,
    bool clearError = false,
  }) {
    return SubscriptionState(
      offer: offer ?? this.offer,
      user: user ?? this.user,
      upiApps: upiApps ?? this.upiApps,
      selectedAppId: selectedAppId ?? this.selectedAppId,
      loading: loading ?? this.loading,
      phase: phase ?? this.phase,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Backoff for the post-checkout poll: quick at first, because most mandates confirm within a
/// couple of seconds, then spaced out to about half a minute in total.
///
/// A provider so tests can collapse it — otherwise every test of the confirm path would have to
/// sit through the real half minute.
final subscriptionPollDelaysProvider = Provider<List<Duration>>((ref) => const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 4),
      Duration(seconds: 5),
      Duration(seconds: 5),
      Duration(seconds: 5),
      Duration(seconds: 5),
    ]);

class SubscriptionViewModel extends Notifier<SubscriptionState> {
  /// Ties every event in one purchase together — the tap, the mandate, the UPI launch, the poll
  /// and the outcome. Without it a user who tries three times is one indistinguishable smear.
  String? _attemptId;
  int _attempts = 0;
  DateTime? _attemptStartedAt;

  /// Which offer this attempt was launched on, captured at the tap.
  ///
  /// Not re-read at the end. By then the entitlement poll has replaced `state.user` with the
  /// post-purchase one, whose trial is no longer on the table — so re-deriving it reported every
  /// ₹3 trial conversion as a ₹499 plan purchase, and that value is what Facebook bids on.
  String? _offerType;

  Analytics get _analytics => ref.read(analyticsProvider);

  @override
  SubscriptionState build() {
    _load();
    return const SubscriptionState();
  }

  /// The identifying properties of the attempt in flight, on every event it produces.
  Map<String, Object?> _attemptProperties() => {
        P.paymentAttemptId: _attemptId,
        P.attemptNumber: _attempts,
      };

  Future<void> _load() async {
    final startedAt = DateTime.now();
    try {
      final repository = ref.read(subscriptionRepositoryProvider);
      // Fetched together: the offer decides the price on screen, the user decides whether the
      // trial is still on the table, and the app list decides which UPI app the button opens.
      final results = await Future.wait<Object?>([
        repository.offer(),
        ref.read(authRepositoryProvider).currentUser(),
        ref.read(cashfreeCheckoutProvider).installedApps(),
        ref.read(upiAppPreferenceProvider).read(),
      ]);

      final apps = results[2] as List<UpiApp>;
      final remembered = results[3] as String?;

      final offer = results[0] as SubscriptionOffer;
      final selected = _resolveSelection(apps, remembered);

      state = state.copyWith(
        offer: offer,
        user: results[1] as AppUser?,
        upiApps: apps,
        selectedAppId: selected,
        loading: false,
      );

      _analytics.track(Ev.paywallOfferLoaded, {
        P.trialPrice: offer.trialPrice,
        P.planPrice: offer.planPrice,
        P.trialDays: offer.trialDays,
        // Whether this user is being shown the ₹3 trial or the plain monthly price. The two
        // convert nothing like each other, so a single paywall conversion rate is meaningless
        // without it.
        P.trialAvailable: state.trialAvailable,
        // Zero here is the interesting case: it means the Cashfree checkout screen stands in for
        // the one-tap intent, which is a materially worse flow.
        P.upiAppCount: apps.length,
        P.ms: DateTime.now().difference(startedAt).inMilliseconds,
      });

      _analytics.track(Ev.upiAppPreselected, {
        P.appId: selected,
        P.source: selected == null
            ? 'none'
            : (remembered != null && selected == remembered ? 'remembered' : 'first'),
      });

      // On every event from here on, so a breakdown by UPI app does not need a join back to
      // this one. Which app a user pays with predicts whether the mandate succeeds.
      if (selected != null) _analytics.registerSuper({'preferred_upi_app': selected});
    } catch (error) {
      debugPrint('[subscription] could not load the offer: $error');
      state = state.copyWith(
        loading: false,
        error: 'Could not load the plan. Please check your connection and try again.',
      );
      _analytics.track(Ev.paywallOfferLoadFailed, {
        P.error: error.toString(),
        P.ms: DateTime.now().difference(startedAt).inMilliseconds,
      });
    }
  }

  /// The remembered app, but only while it is still installed.
  ///
  /// Without the containment check, uninstalling the app you last paid with would leave the
  /// button pointing at an id the SDK can no longer launch — a dead button with no explanation.
  static String? _resolveSelection(List<UpiApp> apps, String? remembered) {
    if (apps.isEmpty) return null;
    if (remembered != null && apps.any((app) => app.id == remembered)) return remembered;
    return apps.first.id;
  }

  void selectApp(String appId) {
    if (!state.upiApps.any((app) => app.id == appId)) return;

    _analytics.track(Ev.upiAppChanged, {
      P.fromAppId: state.selectedAppId,
      P.toAppId: appId,
      P.positionInList: state.upiApps.indexWhere((app) => app.id == appId),
      P.availableCount: state.upiApps.length,
    });

    state = state.copyWith(selectedAppId: appId, clearError: true);
    _analytics.registerSuper({'preferred_upi_app': appId});
    // Fire and forget: the choice is already applied on screen, and a failed write costs one
    // tap on "Change" next time.
    ref.read(upiAppPreferenceProvider).save(appId);
  }

  /// Runs the whole purchase and reports how it ended.
  ///
  /// The SDK's success callback is deliberately not treated as proof — it says the UPI app
  /// handed control back, not that money moved. Only `subscription-status`, which reconciles
  /// against Cashfree, can answer that — so every path ends by polling it.
  ///
  /// Three outcomes, not two. The poll running out after the SDK reported success is not a
  /// failure: the money may well have moved and the webhook simply has not landed yet. That
  /// case is [PaymentOutcome.pending], and it gets a screen that keeps asking.
  /// Null means the tap was ignored — a second press while the first is still in flight. That
  /// is not an outcome, and reporting it as one would throw up a failure screen over a payment
  /// that is still running.
  Future<PaymentOutcome?> subscribe() async {
    if (state.busy || state.loading) {
      // Counted rather than dropped: a run of these means the button looks tappable while it is
      // working, which is a bug the success rate alone would never show.
      _analytics.track(Ev.subscribeTapIgnored, {
        P.reason: state.loading ? 'loading' : 'busy',
        P.attemptNumber: _attempts,
      });
      return null;
    }

    _attempts += 1;
    _attemptId = 'pa_${DateTime.now().microsecondsSinceEpoch}_$_attempts';
    _attemptStartedAt = DateTime.now();
    _offerType = state.trialAvailable ? 'trial' : 'plan';

    // The SDK's own stopwatch, not a Dart one: the app is backgrounded for the whole UPI
    // hand-off, and a duration measured across that in Dart would be wrong.
    _analytics.timeEvent(Ev.paymentCompleted);

    final offer = state.offer;
    _analytics.track(Ev.subscribeTapped, {
      ..._attemptProperties(),
      P.appId: state.selectedAppId,
      P.offerType: _offerType,
      // The label, not a number — see [_finish] on why the client books no revenue.
      P.amount: state.trialAvailable ? offer?.trialPrice : offer?.planPrice,
      // `intent` opens the UPI app directly; `checkout` falls back to Cashfree's screen. The
      // second converts far worse, and without this they are one number.
      P.flow: state.selectedApp != null ? 'intent' : 'checkout',
    });

    state = state.copyWith(phase: SubscriptionPhase.opening, clearError: true);
    final repository = ref.read(subscriptionRepositoryProvider);

    try {
      _analytics.track(Ev.mandateStartRequested, _attemptProperties());
      final start = await repository.start();
      // The server declined to open a second mandate because this account is already inside a
      // trial or a paid month. Nothing was charged; just let them through.
      if (start.alreadyEntitled) {
        state = state.copyWith(phase: SubscriptionPhase.idle);
        _analytics.track(Ev.mandateAlreadyEntitled, _attemptProperties());
        return _finish(PaymentOutcome.success, verified: false, pollAttempts: 0);
      }

      _analytics.track(Ev.mandateStartSucceeded, {
        ..._attemptProperties(),
        P.subscriptionId: start.subscriptionId,
        P.environment: start.environment,
      });

      final checkout = ref.read(cashfreeCheckoutProvider);
      final app = state.selectedApp;

      _analytics.track(Ev.upiIntentLaunched, {
        ..._attemptProperties(),
        P.appId: app?.id,
        P.appName: app?.displayName,
        P.flow: app != null ? 'intent' : 'checkout',
        P.subscriptionId: start.subscriptionId,
      });

      // With an app chosen this launches it straight into the mandate — no Cashfree screen.
      // Without one, Cashfree's own checkout stands in, because it is the only route to the
      // "enter a UPI ID" collect flow that a device with no UPI app needs.
      final result = app != null
          ? await checkout.openWithApp(
              subscriptionId: start.subscriptionId,
              sessionId: start.sessionId,
              environment: start.environment,
              upiAppId: app.id,
            )
          : await checkout.open(
              subscriptionId: start.subscriptionId,
              sessionId: start.sessionId,
              environment: start.environment,
            );

      state = state.copyWith(phase: SubscriptionPhase.confirming);

      final maxAttempts = result.verified ? 8 : 3;
      _analytics.track(Ev.entitlementPollStarted, {
        ..._attemptProperties(),
        P.maxAttempts: maxAttempts,
        // The SDK saying the UPI app handed control back. Explicitly not proof of payment, which
        // is why the poll below exists — but it does predict the outcome, so it is worth having
        // on every event that follows.
        P.sdkVerified: result.verified,
      });

      // Polled even when the SDK reported failure, and that matters more in the intent flow
      // than it did with the checkout screen: approving in Google Pay and then swiping back
      // instead of waiting for the redirect is ordinary user behaviour, and it surfaces here as
      // a failure on a mandate that actually succeeded. Fewer attempts, because the common case
      // really is a cancellation and nobody wants to watch a spinner for it.
      final entitled = await _pollForEntitlement(maxAttempts);

      state = state.copyWith(phase: SubscriptionPhase.idle);
      if (entitled) {
        return _finish(
          PaymentOutcome.success,
          verified: result.verified,
          pollAttempts: maxAttempts,
        );
      }

      // The SDK said the UPI app handed control back, so a debit is plausible and the poll
      // simply ran out first. That is not a failure, and telling the user it was is how a
      // paying customer gets asked to pay twice.
      if (result.verified) {
        return _finish(
          PaymentOutcome.pending,
          verified: true,
          pollAttempts: maxAttempts,
          reason: 'poll_exhausted',
        );
      }

      state = state.copyWith(
        error: result.message ?? 'The payment was not completed. Please try again.',
      );
      return _finish(
        PaymentOutcome.failed,
        verified: false,
        pollAttempts: maxAttempts,
        reason: result.message ?? 'sdk_reported_failure',
      );
    } on SubscriptionException catch (e) {
      // Distinguishable in the log from an SDK failure: this one never reached Cashfree's
      // checkout at all, so no UPI app was ever going to open.
      debugPrint('[subscription] server refused to start the mandate: ${e.message}');
      state = state.copyWith(phase: SubscriptionPhase.idle, error: e.message);
      _analytics.track(Ev.mandateStartRefused, {
        ..._attemptProperties(),
        P.message: e.message,
      });
      return _finish(
        PaymentOutcome.failed,
        verified: false,
        pollAttempts: 0,
        reason: 'mandate_refused',
      );
    } catch (error) {
      debugPrint('[subscription] purchase failed: $error');
      state = state.copyWith(
        phase: SubscriptionPhase.idle,
        error: 'Could not complete the purchase. Please try again.',
      );
      return _finish(
        PaymentOutcome.failed,
        verified: false,
        pollAttempts: 0,
        reason: 'unknown',
        error: error.toString(),
      );
    }
  }

  /// The single exit from [subscribe], so no path can end without reporting how it went.
  ///
  /// One event per attempt with the outcome as a property, rather than three differently-named
  /// events: a funnel wants one step here, and `outcome` is what it breaks down by.
  PaymentOutcome _finish(
    PaymentOutcome outcome, {
    required bool verified,
    required int pollAttempts,
    String? reason,
    String? error,
  }) {
    _analytics.track(Ev.paymentCompleted, {
      ..._attemptProperties(),
      P.outcome: outcome.name,
      P.sdkVerified: verified,
      P.pollAttempts: pollAttempts,
      P.reason: reason,
      P.error: error,
      P.appId: state.selectedAppId,
      // Which offer was taken, matching the property `Subscribe Tapped` already carries — so the
      // two ends of the funnel break down the same way, and a trial that converts worse than a
      // direct plan purchase is visible rather than averaged away.
      //
      // Also the property the Facebook sink reads to decide what a conversion was worth. It maps
      // the offer type to an amount from `app_config`; see `facebook_analytics.dart`.
      //
      // The value captured at the tap, deliberately — see [_offerType]. The poll above has
      // already moved `state.user` past the purchase by the time this runs.
      P.offerType: _offerType,
      P.totalSeconds: _attemptStartedAt == null
          ? null
          : DateTime.now().difference(_attemptStartedAt!).inSeconds,
    });

    // Revenue is deliberately *not* booked here.
    //
    // The only amounts the client has are [SubscriptionOffer]'s display strings — `₹3`, `₹249` —
    // which are paywall copy, not what Cashfree charged. The authoritative number arrives
    // server-side, where `recordPayment` books every debit from Cashfree's own payment record
    // under `Mandate Authorised` and `Subscription Renewed`. Parsing the rupee sign off a label
    // here would produce a second, less accurate revenue series that silently disagrees with the
    // first — and would keep counting a charge the poll only *believed* had happened.
    //
    // Facebook is the one exception, and it does not weaken any of the above. An ad optimiser has
    // to be told a conversion's value at the moment it happens or it cannot bid, so it cannot
    // wait for the webhook the way Mixpanel's revenue series does. It gets its number from
    // `app_config` rather than from a label, it never reaches `trackCharge`, and it stays a
    // separate series in a separate system — so there is still exactly one revenue number in
    // Mixpanel, and it is still the server's.

    return outcome;
  }

  Future<bool> _pollForEntitlement(int attempts) async {
    final delays = ref.read(subscriptionPollDelaysProvider);

    for (var i = 0; i < attempts; i++) {
      await Future.delayed(delays[i.clamp(0, delays.length - 1)]);
      try {
        final user = await ref.read(subscriptionRepositoryProvider).refreshStatus();
        if (user != null) state = state.copyWith(user: user);
        if (user?.entitled ?? false) return true;
      } catch (error) {
        // A dropped poll is not a failed payment. Keep asking — the webhook may still be in
        // flight, and giving up here would tell a paying user they had not paid.
        debugPrint('[subscription] status poll failed: $error');
        _analytics.track(Ev.entitlementPollFailed, {
          ..._attemptProperties(),
          P.attempt: i + 1,
          P.error: error.toString(),
        });
      }
    }
    return false;
  }
}

final subscriptionViewModelProvider =
    NotifierProvider<SubscriptionViewModel, SubscriptionState>(SubscriptionViewModel.new);
