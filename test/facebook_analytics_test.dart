import 'package:astrolok/data/analytics/analytics_events.dart';
import 'package:astrolok/data/analytics/facebook_analytics.dart';
import 'package:astrolok/data/models/app_user.dart';
import 'package:astrolok/data/repositories/app_config_repository.dart';
import 'package:facebook_app_events/facebook_app_events.dart' show channelName;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// What crosses to Facebook, and — mostly — what does not.
///
/// The Dart side of the Facebook SDK is a thin wrapper over a method channel, so the channel is
/// recorded rather than mocked away: the interesting behaviour is entirely in which calls this
/// app decides to make, and that is exactly what shows up there.

AppUser _user({String id = 'u1'}) => AppUser(
      id: id,
      phone: '9931145610',
      name: 'Ayush',
      paymentType: PaymentType.trial,
      entitled: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  /// Makes the channel throw the way a native SDK that never initialised does.
  ///
  /// The state 1.0.2+5 shipped in: `AutoInitEnabled=false`, so the plugin had no `AppEventsLogger`
  /// to log through and every call failed. Recorded before it throws, so a test can still see what
  /// was attempted.
  late bool failSends;

  /// A sink already started with the amounts `app_config` would have supplied.
  Future<FacebookAnalytics> started({
    String appId = '1234567890',
    bool enabled = true,
  }) async {
    final facebook = FacebookAnalytics(preferences: SharedPreferencesAsync());
    await facebook.start(
      appId: appId,
      enabled: enabled,
      trialAmount: 3,
      planAmount: 499,
      currency: 'INR',
    );
    calls.clear();
    return facebook;
  }

  List<MethodCall> callsNamed(String name) =>
      calls.where((call) => call.method == name).toList();

  setUp(() {
    calls = [];
    failSends = false;
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), (call) async {
      calls.add(call);
      if (failSends) {
        throw PlatformException(
          code: 'error',
          message: 'The SDK has not been initialized, make sure to call '
              'FacebookSdk.sdkInitialize() first.',
        );
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), null);
  });

  group('the off switch', () {
    test('a blank app id leaves the sink dormant', () async {
      final facebook = await started(appId: '');

      facebook.track(Ev.paymentCompleted, {P.outcome: 'success'});
      facebook.identify(_user());
      facebook.flush();
      await Future<void>.delayed(Duration.zero);

      // The state of any checkout not pointed at a Facebook app, and of every test in this
      // directory. If it reported anything here, the integration would stop being optional.
      expect(facebook.isActive, isFalse);
      expect(calls, isEmpty);
    });

    test('facebook_events_enabled = false silences a fully configured app', () async {
      final facebook = await started(enabled: false);

      facebook.track(Ev.paymentCompleted, {P.outcome: 'success'});
      await Future<void>.delayed(Duration.zero);

      // The point of the flag: reporting can be stopped from `app_config` without clearing the
      // credentials and without shipping a release.
      expect(calls, isEmpty);
    });

    test('startFacebook reads the keys app_config actually ships with', () async {
      final facebook = FacebookAnalytics(preferences: SharedPreferencesAsync());

      // defaultAppConfig carries a blank facebook_app_id on purpose, so the shipped defaults
      // alone must never bring the sink up.
      await startFacebook(facebook, defaultAppConfig);
      expect(facebook.isActive, isFalse);

      await startFacebook(facebook, {...defaultAppConfig, facebookAppIdKey: '1234567890'});
      expect(facebook.isActive, isTrue);
    });
  });

  group('the allowlist', () {
    test('the ~60 events Facebook has no use for are dropped', () async {
      final facebook = await started();

      facebook.track(Ev.screenViewed, {P.screen: 'Home'});
      facebook.track(Ev.elementTapped, {P.elementId: 'retry_payment'});
      facebook.track(Ev.appLaunched);
      facebook.track(Ev.homeViewed);
      facebook.track(Ev.paywallViewed);
      await Future<void>.delayed(Duration.zero);

      // Forwarding these would dilute the standard events the optimiser trains on, and put a
      // network call behind every tap in the app.
      expect(calls, isEmpty);
    });

    test('the four conversions cross', () async {
      final facebook = await started();

      facebook.track(Ev.signupCompleted, {P.destination: 'subscription'});
      facebook.track(Ev.subscribeTapped, {P.offerType: 'trial'});
      await Future<void>.delayed(Duration.zero);

      expect(callsNamed('logEvent'), hasLength(2));
    });
  });

  group('purchases', () {
    test('a failed payment is not a sale', () async {
      final facebook = await started();

      // `Payment Completed` carries failures and pendings through the same event name, so this
      // guard is the only thing standing between a declined UPI mandate and a reported purchase.
      facebook.track(Ev.paymentCompleted, {P.outcome: 'failed'});
      facebook.track(Ev.paymentCompleted, {P.outcome: 'pending'});
      await Future<void>.delayed(Duration.zero);

      expect(callsNamed('logPurchase'), isEmpty);
    });

    test('a successful payment is reported once, with the trial amount', () async {
      final facebook = await started();

      facebook.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await Future<void>.delayed(Duration.zero);

      final purchase = callsNamed('logPurchase').single;
      expect(purchase.arguments['amount'], 3.0);
      expect(purchase.arguments['currency'], 'INR');

      // Both, deliberately: Purchase carries the value Facebook bids against, StartTrial is the
      // subscription signal its own guidance asks for.
      expect(callsNamed('logEvent'), hasLength(1));
    });

    test('a direct plan purchase is reported at the plan amount', () async {
      final facebook = await started();

      facebook.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'plan'});
      await Future<void>.delayed(Duration.zero);

      expect(callsNamed('logPurchase').single.arguments['amount'], 499.0);
    });

    test('an unknown offer type is priced as the trial rather than the plan', () async {
      final facebook = await started();

      facebook.track(Ev.paymentCompleted, {P.outcome: 'success'});
      await Future<void>.delayed(Duration.zero);

      // Under-reporting costs a few rupees of attributed revenue. Over-reporting teaches the
      // optimiser to buy the wrong people, which is far more expensive to undo.
      expect(callsNamed('logPurchase').single.arguments['amount'], 3.0);
    });

    test('a second success on the same device does not double-count', () async {
      final facebook = await started();

      // The real sequence this guards: a payment the paywall never detected, then a retry the
      // server answers with `alreadyEntitled` — a success that charged nothing.
      facebook.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await Future<void>.delayed(Duration.zero);
      facebook.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await Future<void>.delayed(Duration.zero);

      expect(callsNamed('logPurchase'), hasLength(1));
    });

    test('the late confirmation reports the purchase the paywall gave up on', () async {
      final facebook = await started();

      // The only success path that never passes through `Payment Completed`. Without it these
      // conversions are lost silently — the money arrives, Facebook never hears about it.
      facebook.track(Ev.paymentConfirmedLate, {P.offerType: 'trial'});
      await Future<void>.delayed(Duration.zero);

      expect(callsNamed('logPurchase'), hasLength(1));
    });

    test('the guard survives a restart, because the flag is on disk', () async {
      final first = await started();
      first.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await Future<void>.delayed(Duration.zero);
      expect(callsNamed('logPurchase'), hasLength(1));

      // A fresh instance is what a relaunch looks like, and the app is routinely killed during
      // the UPI hand-off — so an in-memory guard would miss exactly the case it exists for.
      calls.clear();
      final second = await started();
      second.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await Future<void>.delayed(Duration.zero);

      expect(callsNamed('logPurchase'), isEmpty);
    });

    test('a send that throws leaves the conversion reportable', () async {
      final facebook = await started();
      failSends = true;

      facebook.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await Future<void>.delayed(Duration.zero);
      expect(callsNamed('logPurchase'), hasLength(1));

      // The bug this ordering exists for. With the flag written first, a build whose native SDK
      // never came up spent every payer's one conversion on a send that could not land — and no
      // later attempt, on any version, could ever report it again.
      calls.clear();
      failSends = false;
      facebook.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await Future<void>.delayed(Duration.zero);

      expect(callsNamed('logPurchase'), hasLength(1));
    });

    test('a device holding the burned v1 flag can report once more', () async {
      // What every paying device looks like after 1.0.2+5: the old key set, against an SDK that
      // was switched off and received nothing.
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData(
        {'astrolok.fb_purchase_reported': true},
      );
      final facebook = await started();

      facebook.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await Future<void>.delayed(Duration.zero);

      expect(callsNamed('logPurchase'), hasLength(1));
    });
  });

  group('reconciling a late mandate', () {
    /// The sequence a real UPI payer produces: tap subscribe, then the webhook misses the
    /// paywall's poll window and the attempt ends as pending.
    Future<FacebookAnalytics> pendingCheckout() async {
      final facebook = await started();
      facebook.track(Ev.subscribeTapped, {P.offerType: 'trial'});
      facebook.track(Ev.paymentCompleted, {P.outcome: 'pending'});
      await Future<void>.delayed(Duration.zero);
      calls.clear();
      return facebook;
    }

    test('the resume check reports what the poll never saw', () async {
      final facebook = await pendingCheckout();

      await facebook.reconcilePurchase(entitled: true);

      // Previously lost entirely unless the user watched the status screen to completion: the
      // server booked the subscription and Facebook was never told.
      expect(callsNamed('logPurchase').single.arguments['amount'], 3.0);
    });

    test('an existing subscriber is not reported as a fresh sale', () async {
      // No checkout on this install — the case that would otherwise fire on first resume after an
      // update for every long-standing subscriber in the base.
      final facebook = await started();

      await facebook.reconcilePurchase(entitled: true);

      expect(calls, isEmpty);
    });

    test('a user who has not paid is not reported', () async {
      final facebook = await pendingCheckout();

      // Entitlement is the server's answer, and it is the only thing that makes this a sale.
      await facebook.reconcilePurchase(entitled: false);

      expect(calls, isEmpty);
    });

    test('the plan amount survives the round trip through disk', () async {
      final facebook = await started();
      facebook.track(Ev.subscribeTapped, {P.offerType: 'plan'});
      await Future<void>.delayed(Duration.zero);
      calls.clear();

      await facebook.reconcilePurchase(entitled: true);

      // Read from what was bought, not from where the subscription has since got to.
      expect(callsNamed('logPurchase').single.arguments['amount'], 499.0);
    });

    test('reconciling twice reports one purchase', () async {
      final facebook = await pendingCheckout();

      await facebook.reconcilePurchase(entitled: true);
      await facebook.reconcilePurchase(entitled: true);

      // Every resume calls this, so it runs far more often than any other purchase path.
      expect(callsNamed('logPurchase'), hasLength(1));
    });

    test('a paywall success already reported is not reconciled again', () async {
      final facebook = await started();
      facebook.track(Ev.subscribeTapped, {P.offerType: 'trial'});
      facebook.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await Future<void>.delayed(Duration.zero);
      expect(callsNamed('logPurchase'), hasLength(1));

      calls.clear();
      await facebook.reconcilePurchase(entitled: true);

      expect(callsNamed('logPurchase'), isEmpty);
    });

    test('a concurrent paywall success and resume report one purchase', () async {
      final facebook = await started();
      facebook.track(Ev.subscribeTapped, {P.offerType: 'trial'});
      await Future<void>.delayed(Duration.zero);
      calls.clear();

      // Both read the flag before either writes it, now that the write follows the send.
      facebook.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await facebook.reconcilePurchase(entitled: true);
      await Future<void>.delayed(Duration.zero);

      expect(callsNamed('logPurchase'), hasLength(1));
    });
  });

  group('identity', () {
    test('sign-out clears the identity but not the purchase guard', () async {
      final facebook = await started();
      facebook.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await Future<void>.delayed(Duration.zero);

      facebook.reset();
      await Future<void>.delayed(Duration.zero);
      expect(callsNamed('clearUserData'), hasLength(1));

      calls.clear();
      facebook.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await Future<void>.delayed(Duration.zero);

      // Signing out is not a reason to be allowed to report a second purchase.
      expect(callsNamed('logPurchase'), isEmpty);
    });

    test('trackCharge is not a second route to a purchase', () async {
      final facebook = await started();

      facebook.trackCharge(249);
      await Future<void>.delayed(Duration.zero);

      // Revenue reaches Facebook through the de-duplicated path only. An unguarded second route
      // to logPurchase is how a conversion gets counted twice.
      expect(calls, isEmpty);
    });
  });
}
