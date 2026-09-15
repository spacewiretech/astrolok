import 'package:astrolok/data/analytics/analytics_events.dart';
import 'package:astrolok/data/analytics/firebase_analytics_sink.dart';
import 'package:astrolok/data/models/app_user.dart';
import 'package:astrolok/data/repositories/app_config_repository.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// What crosses to Google Analytics, and — mostly — what does not.
///
/// The SDK is stood in by recording fakes, so what is under test is exactly which calls this app
/// decides to make. The purchase cases mirror `facebook_analytics_test.dart` on purpose: the two
/// sinks guard one conversion with the same rules, and should fail the same tests if either drifts.

AppUser _user({String id = 'u1'}) => AppUser(
      id: id,
      phone: '9931145610',
      name: 'Ayush',
      paymentType: PaymentType.trial,
      entitled: true,
    );

typedef _Call = ({String method, Map<String, Object?> args});

class _RecordingFirebaseAnalytics extends Fake implements FirebaseAnalytics {
  final calls = <_Call>[];

  /// Makes every call fail on its future, the way a platform channel error arrives.
  bool failSends = false;

  /// Makes every call throw before returning a future, the way `FirebaseAnalytics.instance` does
  /// with no Firebase app.
  bool throwSynchronously = false;

  Future<void> _call(String method, Map<String, Object?> args) {
    if (throwSynchronously) throw StateError('No Firebase App has been created');
    return _record(method, args);
  }

  Future<void> _record(String method, Map<String, Object?> args) async {
    calls.add((method: method, args: args));
    if (failSends) throw Exception('analytics unavailable');
  }

  @override
  Future<void> logScreenView({
    String? screenClass,
    String? screenName,
    Map<String, Object>? parameters,
    AnalyticsCallOptions? callOptions,
  }) =>
      _call('logScreenView', {'screenName': screenName, 'screenClass': screenClass});

  @override
  Future<void> logSignUp({required String signUpMethod, Map<String, Object>? parameters}) =>
      _call('logSignUp', {'signUpMethod': signUpMethod});

  @override
  Future<void> logBeginCheckout({
    double? value,
    String? currency,
    List<AnalyticsEventItem>? items,
    String? coupon,
    Map<String, Object>? parameters,
    AnalyticsCallOptions? callOptions,
  }) =>
      _call('logBeginCheckout', {'value': value, 'currency': currency});

  @override
  Future<void> logPurchase({
    String? currency,
    String? coupon,
    double? value,
    List<AnalyticsEventItem>? items,
    double? tax,
    double? shipping,
    String? transactionId,
    String? affiliation,
    Map<String, Object>? parameters,
    AnalyticsCallOptions? callOptions,
  }) =>
      _call('logPurchase', {'value': value, 'currency': currency, 'transactionId': transactionId});

  @override
  Future<void> setUserId({String? id, AnalyticsCallOptions? callOptions}) =>
      _call('setUserId', {'id': id});

  @override
  Future<void> setUserProperty({
    required String name,
    required String? value,
    AnalyticsCallOptions? callOptions,
  }) =>
      _call('setUserProperty', {'name': name, 'value': value});
}

class _RecordingCrashlytics extends Fake implements FirebaseCrashlytics {
  final identifiers = <String>[];

  @override
  Future<void> setUserIdentifier(String identifier) async => identifiers.add(identifier);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingFirebaseAnalytics ga;
  late _RecordingCrashlytics crashlytics;

  /// A sink with the amounts `app_config` would have supplied, unless [started] is false.
  FirebaseAnalyticsSink sink({bool started = true}) {
    final sink = FirebaseAnalyticsSink(
      analytics: ga,
      crashlytics: crashlytics,
      preferences: SharedPreferencesAsync(),
    );
    if (started) sink.start(trialAmount: 3, planAmount: 499, currency: 'inr');
    return sink;
  }

  List<_Call> named(String method) => ga.calls.where((call) => call.method == method).toList();

  setUp(() {
    ga = _RecordingFirebaseAnalytics();
    crashlytics = _RecordingCrashlytics();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  group('the allowlist', () {
    test('the events Google has no use for are dropped', () async {
      final firebase = sink();

      firebase.track(Ev.elementTapped, {P.elementId: 'retry_payment'});
      firebase.track(Ev.appLaunched);
      firebase.track(Ev.homeViewed);
      firebase.track(Ev.paywallViewed);
      firebase.track(Ev.screenExited, {P.screen: 'Home'});
      await pumpEventQueue();

      // Mixpanel already has these. Mirrored here they would only duplicate reports under GA4's
      // naming limits and its cap on distinct event names.
      expect(ga.calls, isEmpty);
    });

    test('a screen view carries the screen name', () async {
      sink().track(Ev.screenViewed, {P.screen: 'Palm Reading', P.navType: NavType.push});
      await pumpEventQueue();

      // The SDK's own screen tracking sees one Activity for the whole app.
      expect(named('logScreenView').single.args['screenName'], 'Palm Reading');
    });

    test('a screen view with no name is dropped rather than reported blank', () async {
      final firebase = sink();

      firebase.track(Ev.screenViewed, {P.screen: null});
      firebase.track(Ev.screenViewed, {P.screen: ''});
      await pumpEventQueue();

      expect(ga.calls, isEmpty);
    });

    test('screens and sign-up do not wait for prices; checkout and purchase do', () async {
      final firebase = sink(started: false);

      firebase.track(Ev.screenViewed, {P.screen: 'Home'});
      firebase.track(Ev.signupCompleted);
      firebase.track(Ev.subscribeTapped, {P.offerType: 'trial'});
      firebase.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await pumpEventQueue();

      // A conversion valued at zero teaches Google Ads that a payer is worth nothing.
      expect(ga.calls.map((call) => call.method), ['logScreenView', 'logSignUp']);
      expect(firebase.isActive, isFalse);
    });

    test('sign-up names the one way in', () async {
      sink().track(Ev.signupCompleted, {P.destination: 'subscription'});
      await pumpEventQueue();

      expect(named('logSignUp').single.args['signUpMethod'], 'phone_otp');
    });

    test('begin_checkout is valued at the offer, in the configured currency', () async {
      sink().track(Ev.subscribeTapped, {P.offerType: 'plan'});
      await pumpEventQueue();

      final checkout = named('logBeginCheckout').single;
      expect(checkout.args['value'], 499.0);
      expect(checkout.args['currency'], 'INR');
    });

    test("a plan checkout is valued at the account's own price when it carries one", () async {
      // New signups are split between ₹499 and ₹299, and `app_config` only knows ₹499.
      sink().track(Ev.subscribeTapped, {P.offerType: 'plan', P.planAmount: 299.0});
      await pumpEventQueue();

      expect(named('logBeginCheckout').single.args['value'], 299.0);
    });
  });

  group('purchases', () {
    test('a failed or pending payment is not a sale', () async {
      final firebase = sink();

      firebase.track(Ev.paymentCompleted, {P.outcome: 'failed'});
      firebase.track(Ev.paymentCompleted, {P.outcome: 'pending'});
      await pumpEventQueue();

      expect(named('logPurchase'), isEmpty);
    });

    test('a successful payment is reported with the attempt id as its transaction', () async {
      sink().track(Ev.paymentCompleted, {
        P.outcome: 'success',
        P.offerType: 'trial',
        P.paymentAttemptId: 'attempt-7',
      });
      await pumpEventQueue();

      final purchase = named('logPurchase').single;
      expect(purchase.args['value'], 3.0);
      expect(purchase.args['currency'], 'INR');
      expect(purchase.args['transactionId'], 'attempt-7');
    });

    test('an unknown offer type is priced as the trial rather than the plan', () async {
      sink().track(Ev.paymentCompleted, {P.outcome: 'success'});
      await pumpEventQueue();

      expect(named('logPurchase').single.args['value'], 3.0);
    });

    test('a second success on the same device does not double-count', () async {
      final firebase = sink();

      // A payment the paywall never detected, then a retry the server answers with
      // `alreadyEntitled` — a success that charged nothing.
      firebase.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await pumpEventQueue();
      firebase.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await pumpEventQueue();

      expect(named('logPurchase'), hasLength(1));
    });

    test('two successes in one tick report one purchase', () async {
      final firebase = sink();

      // Both would read the disk flag unset before either writes it.
      firebase.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      firebase.track(Ev.paymentConfirmedLate, {P.offerType: 'trial'});
      await pumpEventQueue();

      expect(named('logPurchase'), hasLength(1));
    });

    test('the late confirmation reports the purchase the paywall gave up on', () async {
      sink().track(Ev.paymentConfirmedLate, {P.offerType: 'trial'});
      await pumpEventQueue();

      expect(named('logPurchase'), hasLength(1));
    });

    test('the guard survives a restart, because the flag is on disk', () async {
      sink().track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await pumpEventQueue();
      expect(named('logPurchase'), hasLength(1));

      // A fresh instance is what a relaunch looks like, and the app is routinely killed during the
      // UPI hand-off.
      sink().track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await pumpEventQueue();

      expect(named('logPurchase'), hasLength(1));
    });

    test("Facebook's guard does not spend Google's conversion", () async {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData(
        {'astrolok.fb_purchase_reported.v2': true},
      );

      sink().track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await pumpEventQueue();

      expect(named('logPurchase'), hasLength(1));
    });

    test('a send that fails leaves the conversion reportable', () async {
      final firebase = sink();
      ga.failSends = true;

      firebase.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await pumpEventQueue();
      expect(named('logPurchase'), hasLength(1));

      // With the flag written before the send, a failure would spend the one conversion on nothing.
      ga.failSends = false;
      firebase.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await pumpEventQueue();

      expect(named('logPurchase'), hasLength(2));
    });

    test('trackCharge is not a second route to a purchase', () async {
      sink().trackCharge(249);
      await pumpEventQueue();

      expect(ga.calls, isEmpty);
    });
  });

  group('prices', () {
    test('a later start re-values the next conversion', () async {
      final firebase = sink();

      // Boot starts from the disk cache; the bootstrap provider starts again from the server, and a
      // corrected price must win rather than be ignored like a second Facebook start.
      firebase.start(trialAmount: 3, planAmount: 249, currency: 'INR');
      firebase.track(Ev.subscribeTapped, {P.offerType: 'plan'});
      await pumpEventQueue();

      expect(named('logBeginCheckout').single.args['value'], 249.0);
    });

    test('startFirebaseAnalytics reads the keys Facebook reads', () async {
      final firebase = sink(started: false);

      startFirebaseAnalytics(firebase, {
        ...defaultAppConfig,
        'trial_price_amount': '5',
        'plan_price_amount': '299',
        'currency_code': 'usd',
      });
      firebase.track(Ev.subscribeTapped, {P.offerType: 'plan'});
      await pumpEventQueue();

      expect(firebase.isActive, isTrue);
      final checkout = named('logBeginCheckout').single;
      expect(checkout.args['value'], 299.0);
      expect(checkout.args['currency'], 'USD');
    });
  });

  group('identity', () {
    test('identify binds Analytics and Crashlytics to the account id, once', () async {
      final firebase = sink();

      // The entitlement gate re-identifies on every resume.
      firebase.identify(_user());
      firebase.identify(_user());
      await pumpEventQueue();

      expect(named('setUserId').single.args['id'], 'u1');
      expect(crashlytics.identifiers, ['u1']);
    });

    test('a different account is identified again', () async {
      final firebase = sink();

      firebase.identify(_user(id: 'u1'));
      firebase.identify(_user(id: 'u2'));
      await pumpEventQueue();

      expect(named('setUserId').map((call) => call.args['id']), ['u1', 'u2']);
    });

    test('sign-out forgets the user but not the purchase guard', () async {
      final firebase = sink();
      firebase.identify(_user());
      firebase.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      await pumpEventQueue();

      firebase.reset();
      await pumpEventQueue();
      expect(named('setUserId').last.args['id'], isNull);
      expect(crashlytics.identifiers.last, '');

      firebase.track(Ev.paymentCompleted, {P.outcome: 'success', P.offerType: 'trial'});
      firebase.identify(_user());
      await pumpEventQueue();

      // Signing out is not a reason to be allowed a second purchase — but signing back in is a
      // reason to be identified again.
      expect(named('logPurchase'), hasLength(1));
      expect(named('setUserId').last.args['id'], 'u1');
    });

    test('backend_mode is the only super property that crosses', () async {
      final firebase = sink();

      firebase.registerSuper({P.env: 'production', P.backendMode: BackendMode.fake});
      firebase.registerSuper({P.env: 'production'});
      await pumpEventQueue();

      final property = named('setUserProperty').single;
      expect(property.args['name'], 'backend_mode');
      expect(property.args['value'], 'fake');
    });
  });

  group('failures stay inside the sink', () {
    test('an SDK that throws synchronously never reaches the caller', () {
      ga.throwSynchronously = true;
      final firebase = sink();

      // What every call looks like if the sink were ever installed without a Firebase app.
      expect(() => firebase.track(Ev.screenViewed, {P.screen: 'Home'}), returnsNormally);
      expect(() => firebase.track(Ev.signupCompleted), returnsNormally);
      expect(() => firebase.identify(_user()), returnsNormally);
      expect(() => firebase.reset(), returnsNormally);
      expect(() => firebase.registerSuper({P.backendMode: 'fake'}), returnsNormally);
    });

    test('a failed future is absorbed rather than surfacing as an uncaught error', () async {
      ga.failSends = true;
      final firebase = sink();

      // An escaped async error would fail this test — and in the app, would be reported by
      // Crashlytics as a crash in the analytics code.
      firebase.track(Ev.screenViewed, {P.screen: 'Home'});
      firebase.track(Ev.subscribeTapped, {P.offerType: 'trial'});
      firebase.identify(_user());
      await pumpEventQueue();

      expect(ga.calls, hasLength(3));
    });
  });
}
