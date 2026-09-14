import 'dart:async';

import 'package:astrolok/data/analytics/analytics.dart';
import 'package:astrolok/data/analytics/analytics_events.dart';
import 'package:astrolok/data/firebase/firebase_boot.dart';
import 'package:astrolok/data/firebase/push_messaging.dart';
import 'package:astrolok/data/models/app_user.dart';
import 'package:astrolok/data/repositories/push_repository.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Push: when the prompt is shown, when a token is registered, and what a tap reports.
///
/// Firebase is stood in by a [PushPlatform] fake, so what is under test is exactly the decisions
/// this app makes — which is where every way this can go wrong lives.

AppUser _user({String id = 'u1'}) => AppUser(
      id: id,
      phone: '9931145610',
      name: 'Ayush',
      paymentType: PaymentType.trial,
      entitled: true,
    );

class _FakePushPlatform implements PushPlatform {
  _FakePushPlatform({this.name = 'android'});

  @override
  final String name;

  AuthorizationStatus status = AuthorizationStatus.notDetermined;
  AuthorizationStatus answer = AuthorizationStatus.authorized;
  int requests = 0;

  String? currentToken = 'token-1';
  RemoteMessage? launchMessage;

  final refreshes = StreamController<String>.broadcast();
  final foreground = StreamController<RemoteMessage>.broadcast();
  final opened = StreamController<RemoteMessage>.broadcast();

  @override
  Future<AuthorizationStatus> currentPermission() async => status;

  @override
  Future<AuthorizationStatus> requestPermission() async {
    requests++;
    status = answer;
    return answer;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<RemoteMessage> get foregroundMessages => foreground.stream;

  @override
  Stream<RemoteMessage> get openedMessages => opened.stream;

  @override
  Future<RemoteMessage?> initialMessage() async => launchMessage;
}

class _RecordingPushRepository implements PushRepository {
  final registrations = <({String token, String platform})>[];
  bool accept = true;

  @override
  Future<bool> register({required String token, required String platform}) async {
    registrations.add((token: token, platform: platform));
    return accept;
  }
}

class _RecordingAnalytics implements Analytics {
  final events = <({String name, Map<String, Object?> properties})>[];

  List<Map<String, Object?>> named(String name) =>
      [for (final event in events) if (event.name == name) event.properties];

  @override
  void track(String event, [Map<String, Object?> properties = const {}]) =>
      events.add((name: event, properties: properties));

  @override
  void timeEvent(String event) {}

  @override
  void identify(AppUser user) {}

  @override
  void reset() {}

  @override
  void registerSuper(Map<String, Object?> properties) {}

  @override
  void trackCharge(double amount, [Map<String, Object?> properties = const {}]) {}

  @override
  void flush() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePushPlatform platform;
  late _RecordingPushRepository backend;
  late _RecordingAnalytics recorded;
  final instances = <PushMessaging>[];

  PushMessaging push({_FakePushPlatform? on}) {
    final instance = PushMessaging(platform: on ?? platform, preferences: SharedPreferencesAsync());
    instances.add(instance);
    return instance;
  }

  setUp(() {
    platform = _FakePushPlatform();
    backend = _RecordingPushRepository();
    recorded = _RecordingAnalytics();
    firebaseInitialised = true;
    installAnalytics(recorded);
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() async {
    for (final instance in instances) {
      await instance.dispose();
    }
    instances.clear();
    firebaseInitialised = false;
    installAnalytics(const NoopAnalytics());
  });

  test('nothing happens while Firebase is down', () async {
    firebaseInitialised = false;
    final messaging = push();

    await messaging.start();
    await messaging.ensurePermission();
    await messaging.attachBackend(backend);
    await messaging.onUserResolved(_user());

    // The state of every test in this directory and of any build whose Firebase init failed. If
    // this reached the plugin, the integration would stop being optional.
    expect(platform.requests, 0);
    expect(backend.registrations, isEmpty);
    expect(recorded.events, isEmpty);
  });

  group('registration', () {
    test('a resolved user registers the token once, however often they resolve', () async {
      final messaging = push();
      await messaging.attachBackend(backend);

      // The entitlement gate re-resolves on every resume.
      await messaging.onUserResolved(_user());
      await messaging.onUserResolved(_user());
      await messaging.onUserResolved(_user());

      expect(backend.registrations, [(token: 'token-1', platform: 'android')]);
    });

    test('nothing is registered before a user is known', () async {
      final messaging = push();
      await messaging.attachBackend(backend);

      // No session means nothing for the server to bind the token to.
      expect(backend.registrations, isEmpty);
    });

    test('a refreshed token is registered again', () async {
      final messaging = push();
      await messaging.start();
      await messaging.attachBackend(backend);
      await messaging.onUserResolved(_user());

      platform.currentToken = 'token-2';
      platform.refreshes.add('token-2');
      await pumpEventQueue();

      // The old token is dead on FCM's side; a device that kept only it would never be reached.
      expect(backend.registrations.map((r) => r.token), ['token-1', 'token-2']);
    });

    test('a second account on the same device registers again', () async {
      final messaging = push();
      await messaging.attachBackend(backend);

      await messaging.onUserResolved(_user(id: 'u1'));
      await messaging.onUserResolved(_user(id: 'u2'));

      // Same token, new session: the upsert moves the row, so the signed-out account stops being
      // notifiable on a phone it no longer holds.
      expect(backend.registrations, hasLength(2));
    });

    test('a refused registration is retried on the next resolve', () async {
      final messaging = push();
      await messaging.attachBackend(backend);

      backend.accept = false;
      await messaging.onUserResolved(_user());
      backend.accept = true;
      await messaging.onUserResolved(_user());
      await messaging.onUserResolved(_user());

      // Remembering a registration the backend never accepted would leave the device unreachable
      // until the next cold start.
      expect(backend.registrations, hasLength(2));
    });

    test('no token yet — iOS before APNs answers — is a quiet no-op', () async {
      platform.currentToken = null;
      final messaging = push();
      await messaging.attachBackend(backend);

      await messaging.onUserResolved(_user());

      expect(backend.registrations, isEmpty);
    });

    test('a backend attached while a sync is in flight still gets the registration', () async {
      final messaging = push();

      // The launch order that can really happen: the splash resolves a user while the bootstrap
      // provider is still attaching the Supabase repository.
      final resolving = messaging.onUserResolved(_user());
      await messaging.attachBackend(backend);
      await resolving;
      await pumpEventQueue();

      expect(backend.registrations, hasLength(1));
    });

    test('the platform name is what the backend stores', () async {
      final ios = _FakePushPlatform(name: 'ios');
      final messaging = push(on: ios);
      await messaging.attachBackend(backend);

      await messaging.onUserResolved(_user());

      expect(backend.registrations.single.platform, 'ios');
    });
  });

  group('the permission prompt', () {
    test('an undetermined status prompts, and the answer is reported', () async {
      final messaging = push();

      await messaging.ensurePermission();

      expect(platform.requests, 1);
      expect(recorded.named(Ev.pushPermissionResolved).single, {
        P.status: 'authorized',
        P.granted: true,
        P.prompted: true,
      });
    });

    test('a second call in the same process neither prompts nor reports again', () async {
      final messaging = push();

      await messaging.ensurePermission();
      await messaging.ensurePermission();

      // Home rebuilds; a queued second dialog is the thing the in-process guard prevents.
      expect(platform.requests, 1);
      expect(recorded.named(Ev.pushPermissionResolved), hasLength(1));
    });

    test('a standing grant is reported as not prompted', () async {
      platform.status = AuthorizationStatus.authorized;

      await push().ensurePermission();

      // So the opt-in rate is measured over the users who were actually asked.
      expect(platform.requests, 0);
      expect(recorded.named(Ev.pushPermissionResolved).single[P.prompted], isFalse);
    });

    test('Android asks once per install, then respects the answer', () async {
      // Android reports `denied` both before the prompt has ever been shown and after a refusal.
      platform.status = AuthorizationStatus.denied;
      platform.answer = AuthorizationStatus.denied;

      await push().ensurePermission();
      expect(platform.requests, 1);

      // A relaunch: a fresh instance over the same preferences store.
      await push().ensurePermission();

      // Asking on every launch is how an app gets its prompt blocked by the OS for good.
      expect(platform.requests, 1);
      expect(recorded.named(Ev.pushPermissionResolved).last[P.prompted], isFalse);
    });

    test('on iOS a refusal is final and never re-prompted', () async {
      final ios = _FakePushPlatform(name: 'ios')..status = AuthorizationStatus.denied;

      await push(on: ios).ensurePermission();

      expect(ios.requests, 0);
      expect(recorded.named(Ev.pushPermissionResolved).single[P.granted], isFalse);
    });

    test('provisional counts as granted', () async {
      platform.answer = AuthorizationStatus.provisional;

      await push().ensurePermission();

      expect(recorded.named(Ev.pushPermissionResolved).single[P.granted], isTrue);
    });

    test('a grant retries a registration that earlier found no token', () async {
      platform.currentToken = null;
      final messaging = push();
      await messaging.attachBackend(backend);
      await messaging.onUserResolved(_user());
      expect(backend.registrations, isEmpty);

      // On iOS the APNs token tends to arrive around the prompt.
      platform.currentToken = 'token-1';
      await messaging.ensurePermission();

      expect(backend.registrations, hasLength(1));
    });
  });

  group('taps', () {
    test('a tap on a running app is reported and published', () async {
      final messaging = push();
      await messaging.start();
      final published = <RemoteMessage>[];
      messaging.opened.listen(published.add);

      platform.opened.add(const RemoteMessage(messageId: 'm1'));
      await pumpEventQueue();

      expect(recorded.named(Ev.pushOpened).single, {P.source: 'background', P.messageId: 'm1'});
      expect(published.single.messageId, 'm1');
    });

    test('the tap that launched the app is reported and handed out once', () async {
      platform.launchMessage = const RemoteMessage(messageId: 'launch-1');
      final messaging = push();

      await messaging.start();

      expect(recorded.named(Ev.pushOpened).single, {P.source: 'launch', P.messageId: 'launch-1'});

      // Kept because nothing is listening to the broadcast stream yet when a launch tap arrives.
      expect(messaging.takeInitialMessage()?.messageId, 'launch-1');
      expect(messaging.takeInitialMessage(), isNull);
    });

    test('a foreground message is not reported as an open', () async {
      final messaging = push();
      await messaging.start();

      platform.foreground.add(const RemoteMessage(messageId: 'fg-1'));
      await pumpEventQueue();

      // Nothing was shown, so nothing was opened.
      expect(recorded.named(Ev.pushOpened), isEmpty);
    });
  });
}
