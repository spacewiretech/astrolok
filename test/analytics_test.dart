import 'package:astrolok/data/analytics/analytics.dart';
import 'package:astrolok/data/analytics/analytics_events.dart';
import 'package:astrolok/data/analytics/mixpanel_analytics.dart';
import 'package:astrolok/data/models/app_user.dart';
import 'package:astrolok/data/providers.dart';
import 'package:astrolok/data/repositories/app_config_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The parts of analytics that can be checked without a platform channel.
///
/// Mixpanel's Dart side is a thin wrapper over a method channel, so most of this file is about
/// the two things that are genuinely ours: the queue that holds events until the token arrives,
/// and the mapping from an [AppUser] onto a People profile.

AppUser _user({
  String id = 'u1',
  String name = 'Ayush',
  PaymentType paymentType = PaymentType.trial,
  DateTime? birthDate,
  bool entitled = true,
}) {
  return AppUser(
    id: id,
    phone: '9931145610',
    name: name,
    birthDate: birthDate,
    paymentType: paymentType,
    entitled: entitled,
  );
}

void main() {
  group('NoopAnalytics', () {
    test('every call is safe, which is what makes the integration optional', () {
      // The app runs on this with no token, on a first launch offline, in the web build and in
      // every other test in this directory. If any of these threw, analytics would stop being
      // an optional subsystem and start being a way to crash the app.
      const analytics = NoopAnalytics();

      expect(() {
        analytics.track(Ev.appLaunched);
        analytics.track(Ev.otpVerified, {P.attemptsUsed: 2});
        analytics.timeEvent(Ev.paymentCompleted);
        analytics.identify(_user());
        analytics.registerSuper({P.env: 'production'});
        analytics.trackCharge(249);
        analytics.reset();
        analytics.flush();
      }, returnsNormally);
    });
  });

  group('the pre-token queue', () {
    test('events recorded before the token arrives are held, not dropped', () {
      final analytics = MixpanelAnalytics(verbose: false);

      analytics.track(Ev.appLaunched, {P.isFirstLaunch: true});
      analytics.track(Ev.sessionStarted);
      analytics.track(Ev.screenViewed, {P.screen: 'Splash'});

      // These three are the denominator of every acquisition funnel, and on a first launch they
      // all happen before the config fetch that carries the token has returned. Dropping them
      // would bias exactly the cohort the funnels are about.
      expect(analytics.debugQueueLength, 3);
    });

    test('the queue stops growing rather than growing without bound', () {
      final analytics = MixpanelAnalytics(verbose: false);

      for (var i = 0; i < MixpanelAnalytics.debugMaxQueued + 50; i++) {
        analytics.track(Ev.screenViewed, {P.screen: 'Home'});
      }

      // Reached only when the token never arrives at all — an offline first launch — and by then
      // the events are worth less than the memory they occupy.
      expect(analytics.debugQueueLength, MixpanelAnalytics.debugMaxQueued);
    });

    test('null properties are stripped before an event is queued', () {
      final analytics = MixpanelAnalytics(verbose: false);

      analytics.track(Ev.readingFailed, {
        P.feature: 'palm',
        P.focus: null,
        P.message: null,
      });

      // Mixpanel stores an explicit null as a real value, so a null would become a column in
      // every breakdown of this event.
      final queued = analytics.debugQueuedProperties.single;
      expect(queued.keys, ['feature']);
    });

    test('ambient context is captured when the event happens, not when it is sent', () {
      final analytics = MixpanelAnalytics(verbose: false);
      var screen = 'Splash';
      analytics.context = () => {P.screen: screen};

      analytics.track(Ev.elementTapped, {P.elementId: 'continue'});
      screen = 'Home';
      analytics.track(Ev.elementTapped, {P.elementId: 'palm_card'});

      // A queued event has to carry the screen the user was actually on. Resolving the context
      // at send time would stamp both of these with whichever screen they had reached by the
      // time the token turned up.
      expect(
        analytics.debugQueuedProperties.map((p) => p[P.screen]),
        ['Splash', 'Home'],
      );
    });
  });

  group('the People profile', () {
    test('carries the account, and the phone in a form support can dial', () {
      final profile = MixpanelAnalytics.peoplePropertiesFor(
        _user(paymentType: PaymentType.active, birthDate: DateTime(1998, 4, 12)),
      );

      expect(profile[r'$name'], 'Ayush');
      // Support finds an account from an incoming call, and the number is already the login
      // identifier rather than something collected for analytics.
      expect(profile[r'$phone'], '+919931145610');
      expect(profile[P.paymentType], 'active');
      expect(profile[P.entitled], true);
    });

    test('records the birth year but never the birth date', () {
      final profile = MixpanelAnalytics.peoplePropertiesFor(
        _user(birthDate: DateTime(1998, 4, 12)),
      );

      expect(profile[P.hasBirthDate], true);
      expect(profile[P.birthYear], 1998);
      // The year answers the age question; the full date is a stronger identifier that answers
      // nothing more.
      expect(profile.values, isNot(contains('1998-04-12')));
    });

    test('an account with no birth date says so rather than omitting the question', () {
      final profile = MixpanelAnalytics.peoplePropertiesFor(_user());

      // The onboarding gate routes on this, so "has not given one" is a real answer and has to
      // be distinguishable from a profile written before the field existed.
      expect(profile[P.hasBirthDate], false);
      expect(profile.containsKey(P.birthYear), isFalse);
    });
  });

  group('slugify', () {
    test('turns a label into a stable id', () {
      expect(slugify('Retry Payment'), 'retry_payment');
      expect(slugify('Log out'), 'log_out');
    });

    test('a price or a countdown in the label does not mint a new id per render', () {
      // Without stripping the digits, `Subscribe · ₹249/month` and `Start trial · ₹3` become
      // unrelated columns in every breakdown. The raw label still travels in P.label.
      expect(slugify('Try Now · ₹3'), slugify('Try Now · ₹249'));
      expect(slugify('Resend in 30s'), slugify('Resend in 8s'));
    });

    test('a label with nothing to slug yields null rather than an empty id', () {
      expect(slugify(null), isNull);
      expect(slugify('₹249'), isNull);
    });
  });

  _bootstrapTests();

  group('trackedTap', () {
    test('a disabled control cannot report a tap it never received', () {
      // Returns null so the button stays disabled. Wrapping a null handler in a closure would
      // make every disabled button look tappable to the framework.
      expect(trackedTap(null, id: 'subscribe'), isNull);
    });

    test('the wrapped handler still runs', () {
      installAnalytics(const NoopAnalytics());
      var tapped = false;

      trackedTap(() => tapped = true, id: 'subscribe', label: 'Try Now')!();

      expect(tapped, isTrue);
    });
  });
}

/// Records how it was called, so the bootstrap's cache-bypass rule can be asserted.
class _RecordingConfig implements AppConfigRepository {
  _RecordingConfig(this._cached, this._server);

  /// What the disk cache holds — the value the six-hour TTL keeps serving.
  final Map<String, String> _cached;

  /// What the server would answer if actually asked.
  final Map<String, String> _server;

  final List<bool> calls = [];

  @override
  Future<Map<String, String>> load({bool force = false}) async {
    calls.add(force);
    return force ? _server : _cached;
  }
}

Future<void> _runBootstrap(_RecordingConfig config) async {
  final container = ProviderContainer(overrides: [
    appConfigRepositoryProvider.overrideWithValue(config),
  ]);
  addTearDown(container.dispose);
  await container.read(analyticsBootstrapProvider.future);
}

void _bootstrapTests() {
  group('the bootstrap and a cache that predates a config row', () {
    test('a cache with no mixpanel_token is bypassed once', () async {
      // The failure this exists to prevent. `mixpanel_token` was added to app_config after these
      // installs had already cached; a fresh cache is served without asking the server, so every
      // one of them ran blind for the whole six-hour TTL with the events piling up unsent.
      final config = _RecordingConfig(
        {'env': 'production'},
        {'env': 'production', mixpanelTokenKey: 'tok'},
      );

      await _runBootstrap(config);

      expect(config.calls, [false, true], reason: 'cached read, then a forced one');
    });

    test('a token that is present but blank is left alone', () async {
      // Clearing the cell is the documented off switch. Re-fetching to rediscover that on every
      // launch would make turning analytics off cost a request per launch.
      final config = _RecordingConfig(
        {'env': 'production', mixpanelTokenKey: ''},
        {'env': 'production', mixpanelTokenKey: ''},
      );

      await _runBootstrap(config);

      expect(config.calls, [false], reason: 'no forced re-fetch');
    });

    test('a cached token is used without a second call', () async {
      final config = _RecordingConfig(
        {'env': 'production', mixpanelTokenKey: 'tok'},
        {'env': 'production', mixpanelTokenKey: 'tok'},
      );

      await _runBootstrap(config);

      expect(config.calls, [false]);
    });
  });
}
