import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../repositories/app_config_repository.dart';
import 'analytics.dart';
import 'analytics_events.dart';

/// Google Analytics for Firebase — the third sink behind [MultiAnalytics], and a narrow one.
///
/// ## What crosses
///
/// * **Screens**, from `Screen Viewed`. A Flutter app is one Activity and one view controller, so
///   the SDK's automatic screen tracking sees a single screen for the whole session.
/// * **Identity** on sign-in and sign-out, mirrored onto Crashlytics as well, so a crash report
///   names the account it happened to.
/// * **The four conversions Facebook gets**, mapped to GA4's recommended events: `sign_up`,
///   `begin_checkout`, and `purchase` for both success paths.
/// * `backend_mode` as a user property, so fake-tier traffic can be filtered out.
///
/// Everything else the SDK collects on its own: first open, sessions, engagement, app updates.
///
/// ## Why not everything
///
/// Mixpanel already answers product questions and takes all ~120 events. Mirrored here they would
/// be renamed to fit GA4's limits, capped at 500 distinct names, and would duplicate reports that
/// already exist. What Firebase adds is Google's side — Ads conversion import, audiences,
/// crash-free users — and that needs exactly the list above.
class FirebaseAnalyticsSink implements Analytics {
  FirebaseAnalyticsSink({
    FirebaseAnalytics? analytics,
    FirebaseCrashlytics? crashlytics,
    SharedPreferencesAsync? preferences,
  })  : _analyticsOverride = analytics,
        _crashlyticsOverride = crashlytics,
        _preferences = preferences ?? SharedPreferencesAsync();

  final FirebaseAnalytics? _analyticsOverride;
  final FirebaseCrashlytics? _crashlyticsOverride;
  final SharedPreferencesAsync _preferences;

  // Resolved per call rather than in the constructor, so a test can build the sink without a
  // Firebase app. Boot only installs this sink once `firebaseInitialised` is true.
  FirebaseAnalytics get _ga => _analyticsOverride ?? FirebaseAnalytics.instance;
  FirebaseCrashlytics get _crashlytics => _crashlyticsOverride ?? FirebaseCrashlytics.instance;

  /// The one purchase this install reports to Google, remembered across launches.
  ///
  /// Its own key rather than Facebook's, so the two sinks cannot spend each other's conversion.
  /// See `FacebookAnalytics._logPurchase` for why this has to be a flag on disk, written after the
  /// send — every reason there applies here unchanged.
  static const _purchaseReportedKey = 'astrolok.ga_purchase_reported.v1';

  bool _started = false;
  double _trialAmount = 0;
  double _planAmount = 0;
  String _currency = 'INR';

  /// Held for the duration of a [_logPurchase], because the disk flag is written after the send and
  /// two successes in one process could otherwise both read it unset.
  bool _reporting = false;

  String? _identifiedId;

  /// True once [start] has supplied the prices the conversions are valued at.
  ///
  /// Screens and identity do not wait for it; `begin_checkout` and `purchase` do, because a
  /// conversion reported at zero teaches Google Ads that a payer is worth nothing.
  bool get isActive => _started;

  /// Supplies the amounts from `app_config`.
  ///
  /// Unlike `FacebookAnalytics.start`, callable more than once: boot starts this from the disk cache
  /// and `analyticsBootstrapProvider` again from the fetched config, and a price corrected on the
  /// server should win. Nothing else happens here, so a repeat has no side effects.
  void start({
    required double trialAmount,
    required double planAmount,
    required String currency,
  }) {
    _trialAmount = trialAmount;
    _planAmount = planAmount;
    if (currency.trim().isNotEmpty) _currency = currency.trim().toUpperCase();
    _started = true;
  }

  /// Forwards the allowlisted events; drops the rest.
  ///
  /// Never awaits and never throws: this sits inside button handlers and payment callbacks.
  @override
  void track(String event, [Map<String, Object?> properties = const {}]) {
    switch (event) {
      case Ev.screenViewed:
        final screen = properties[P.screen];
        if (screen is! String || screen.isEmpty) return;
        _send('screen_view', () => _ga.logScreenView(screenName: screen, screenClass: screen));

      // Phone OTP is the only way in, so the method is a constant.
      case Ev.signupCompleted:
        _send('sign_up', () => _ga.logSignUp(signUpMethod: 'phone_otp'));

      case Ev.subscribeTapped:
        if (!_started) return;
        _send(
          'begin_checkout',
          () => _ga.logBeginCheckout(
            value: _amountFor(properties[P.offerType]),
            currency: _currency,
          ),
        );

      // `Payment Completed` carries failures and pendings under the same name; only a success is
      // a sale.
      case Ev.paymentCompleted:
        if (!_started || properties[P.outcome] != 'success') return;
        unawaited(_logPurchase(properties));

      // The webhook landed after the paywall gave up — real money, and the one success path that
      // never passes through `Payment Completed`.
      case Ev.paymentConfirmedLate:
        if (!_started) return;
        unawaited(_logPurchase(properties));
    }
  }

  Future<void> _logPurchase(Map<String, Object?> properties) async {
    if (_reporting) return;
    _reporting = true;

    try {
      try {
        if (await _preferences.getBool(_purchaseReportedKey) ?? false) {
          debugPrint('[firebase-analytics] purchase already reported, not sending a second');
          return;
        }
      } catch (error) {
        // A failed read must not become a silent double-report: give up on the conversion rather
        // than on the guard.
        debugPrint('[firebase-analytics] could not read the purchase guard, skipping: $error');
        return;
      }

      try {
        await _ga.logPurchase(
          value: _amountFor(properties[P.offerType]),
          currency: _currency,
          // Ties the purchase to the checkout attempt that produced it, which is also what GA4
          // de-duplicates purchases on.
          transactionId: properties[P.paymentAttemptId]?.toString(),
        );
      } catch (error) {
        // Returns without setting the flag, so the conversion stays reportable next time.
        debugPrint('[firebase-analytics] could not report the purchase, leaving it reportable: '
            '$error');
        return;
      }

      try {
        await _preferences.setBool(_purchaseReportedKey, true);
      } catch (error) {
        debugPrint('[firebase-analytics] reported the purchase but could not persist the guard: '
            '$error');
      }
    } finally {
      _reporting = false;
    }
  }

  /// Anything other than an explicit `plan` is priced as the trial. Under-reporting costs a few
  /// rupees of attributed revenue; over-reporting teaches an optimiser to buy the wrong people.
  double _amountFor(Object? offerType) => offerType == 'plan' ? _planAmount : _trialAmount;

  /// Binds Analytics and Crashlytics to the account id — never the phone number or the name.
  ///
  /// The entitlement gate re-identifies on every resume, so a repeat of the same id is a no-op.
  @override
  void identify(AppUser user) {
    if (_identifiedId == user.id) return;
    _identifiedId = user.id;
    _send('setUserId', () => _ga.setUserId(id: user.id));
    _send('setUserIdentifier', () => _crashlytics.setUserIdentifier(user.id));
  }

  /// Sign-out. Leaves [_purchaseReportedKey] alone — the guard belongs to the device.
  @override
  void reset() {
    _identifiedId = null;
    _send('setUserId', () => _ga.setUserId(id: null));
    // Crashlytics has no "clear"; an empty identifier is how a user is forgotten there.
    _send('setUserIdentifier', () => _crashlytics.setUserIdentifier(''));
  }

  /// Forwards [P.backendMode] as a user property and ignores the rest.
  ///
  /// GA4 has no super properties, and the few user properties it allows are too scarce to spend on
  /// context the SDK already records. Backend mode is the exception: without it, a developer on the
  /// fake tier shows up in Google's reports as a paying user.
  @override
  void registerSuper(Map<String, Object?> properties) {
    if (!properties.containsKey(P.backendMode)) return;
    final mode = properties[P.backendMode]?.toString();
    _send('setUserProperty', () => _ga.setUserProperty(name: P.backendMode, value: mode));
  }

  /// Mixpanel's stopwatch has no GA4 equivalent worth having.
  @override
  void timeEvent(String event) {}

  /// Revenue reaches Google through the de-duplicated purchase path only. A second, unguarded route
  /// to a purchase is how a conversion gets counted twice.
  @override
  void trackCharge(double amount, [Map<String, Object?> properties = const {}]) {}

  /// The SDK batches and uploads on its own schedule, including when the app backgrounds.
  @override
  void flush() {}

  /// Fires [call] without awaiting it, and absorbs a failure whether it arrives synchronously or on
  /// the returned future — an unawaited error would otherwise surface as an unhandled async error,
  /// which Crashlytics would then report as a crash in the analytics code.
  void _send(String what, Future<void> Function() call) {
    try {
      unawaited(call().catchError((Object error) {
        debugPrint('[firebase-analytics] $what failed: $error');
      }));
    } catch (error) {
      debugPrint('[firebase-analytics] $what failed: $error');
    }
  }
}

/// Starts [sink] from a resolved `app_config` map.
///
/// The same keys `startFacebook` reads, so the two sinks can never value one purchase differently.
/// Called by the boot sequence from the disk cache and by `analyticsBootstrapProvider` from the
/// fetched config.
void startFirebaseAnalytics(FirebaseAnalyticsSink sink, Map<String, String> config) => sink.start(
      trialAmount: config.configDouble('trial_price_amount'),
      planAmount: config.configDouble('plan_price_amount'),
      currency: config.configString('currency_code'),
    );
