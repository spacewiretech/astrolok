import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analytics/analytics.dart';
import '../analytics/analytics_events.dart';
import '../models/app_user.dart';
import '../repositories/push_repository.dart';
import 'firebase_boot.dart';
import 'push_payload.dart';

/// Runs when a data message arrives while the app is not in the foreground.
///
/// Deliberately does nothing but log. A notification message is displayed by the OS without Dart
/// being involved at all; a data message wakes a fresh background isolate with no Firebase app, no
/// Supabase and no analytics, and nothing in this app yet needs to act on one there. Keeping the
/// handler empty keeps that isolate's life to a few milliseconds.
///
/// Top-level and marked as an entry point because the engine looks it up by name from native code,
/// and tree-shaking would otherwise remove a function nothing in Dart calls.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[push] background message ${message.messageId}');
}

/// What [PushMessaging] needs from Firebase Messaging, and nothing more.
///
/// A port rather than the plugin itself, for the same reason `ReadingCamera` is one: the plugin's
/// streams are static getters on a class that cannot be built without a Firebase app, so a test
/// has no way to stand one in. [FirebasePushPlatform] is the only real implementation.
abstract interface class PushPlatform {
  /// `android` or `ios` — the value `push-token` stores.
  String get name;

  Future<AuthorizationStatus> currentPermission();

  /// Shows the system prompt where the OS still allows one, and returns the answer.
  Future<AuthorizationStatus> requestPermission();

  /// This install's FCM token, or null when it cannot be had yet.
  Future<String?> token();

  Stream<String> get tokenRefreshes;

  /// Messages that arrive while the app is on screen. The OS shows nothing for these.
  Stream<RemoteMessage> get foregroundMessages;

  /// Notification taps that brought an already-running app forward.
  Stream<RemoteMessage> get openedMessages;

  /// The notification tap that started this process, if one did.
  Future<RemoteMessage?> initialMessage();
}

class FirebasePushPlatform implements PushPlatform {
  const FirebasePushPlatform();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  String get name => Platform.isIOS ? 'ios' : 'android';

  @override
  Future<AuthorizationStatus> currentPermission() async =>
      (await _messaging.getNotificationSettings()).authorizationStatus;

  @override
  Future<AuthorizationStatus> requestPermission() async =>
      (await _messaging.requestPermission()).authorizationStatus;

  @override
  Future<String?> token() async {
    // On iOS the FCM token is derived from the APNs one, and asking before APNs has answered
    // throws `apns-token-not-set`. That answer can lag a first launch by seconds, so this reports
    // "not yet" and the next resolve asks again.
    if (Platform.isIOS && await _messaging.getAPNSToken() == null) return null;
    return _messaging.getToken();
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<RemoteMessage> get foregroundMessages => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get openedMessages => FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<RemoteMessage?> initialMessage() => _messaging.getInitialMessage();
}

/// Push notifications: the permission prompt, the device token, and what happens on a tap.
///
/// ## What this does not do
///
/// Show anything. A message that arrives while the app is on screen is logged and dropped — there
/// is no in-app banner and no local-notification plugin behind this. Backgrounded, the OS displays
/// notification messages itself. A tap is reported and published on [opened] for routing to pick
/// up, but no route listens yet, because no push is sent yet: the payload contract belongs to
/// whichever sender is built first.
///
/// ## Registration
///
/// The token is stored server-side against the signed-in **session**, not just the account, so
/// sign-out needs nothing from here: `me` DELETE drops the session and the row goes with it. That
/// is why registration hangs off [onUserResolved] — the entitlement hook that fires wherever a
/// signed-in user is known — and off a token refresh, and nowhere else.
///
/// ## Why the prompt is not at launch
///
/// For the same reason ATT is not: a system dialog on the first frame, before the app has shown
/// anything worth being notified about, is the lowest-opt-in placement there is. Home asks, after
/// the ATT prompt has settled, so the two dialogs never contend.
class PushMessaging {
  PushMessaging({
    PushPlatform? platform,
    SharedPreferencesAsync? preferences,
    Future<int?> Function()? appBuild,
  })  : _platform = platform ?? const FirebasePushPlatform(),
        _preferencesOverride = preferences,
        _appBuild = appBuild ?? _installedBuild;

  final PushPlatform _platform;
  final SharedPreferencesAsync? _preferencesOverride;
  final Future<int?> Function() _appBuild;

  /// This install's build number, which the sender compares with `notif_min_app_build`.
  static Future<int?> _installedBuild() async {
    try {
      return int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
    } catch (_) {
      return null;
    }
  }

  late final SharedPreferencesAsync _preferences =
      _preferencesOverride ?? SharedPreferencesAsync();

  /// Whether this install has ever shown the notification prompt.
  ///
  /// Needed on Android only, where the plugin cannot tell "never asked" from "said no": before
  /// Android 13's prompt has been shown it reports `denied`. Without this flag the app would either
  /// never ask on Android or ask on every launch, and the OS permanently blocks an app that asks
  /// too often.
  static const _askedKey = 'astrolok.push_permission_asked';

  final _opened = StreamController<RemoteMessage>.broadcast();
  final _received = StreamController<RemoteMessage>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];

  bool _started = false;
  bool _asked = false;

  PushRepository _backend = const NoopPushRepository();
  String? _userId;

  /// `userId|token` for the last registration the backend accepted.
  ///
  /// In memory, because the entitlement gate re-resolves the user on every resume: this is what
  /// makes those repeats cost a token read rather than a request each. A fresh process registers
  /// once more, which the backend's upsert absorbs.
  String? _registered;

  bool _syncing = false;
  bool _resync = false;

  RemoteMessage? _initial;

  /// Every notification tap, as it happens. The routing hook.
  ///
  /// Broadcast, so a tap nobody is listening for is dropped rather than buffered — which is why the
  /// one that launched the app is also kept for [takeInitialMessage].
  Stream<RemoteMessage> get opened => _opened.stream;

  /// Pushes that arrived while the app was on screen. The OS shows nothing for these, so the app's
  /// in-app banner listens here instead.
  Stream<RemoteMessage> get received => _received.stream;

  /// The notification that started this process, handed out once.
  RemoteMessage? takeInitialMessage() {
    final message = _initial;
    _initial = null;
    return message;
  }

  /// Starts listening. Called once by boot, after analytics, so a launch from a notification is
  /// reported to a real sink. Never prompts.
  Future<void> start() async {
    if (_started || !firebaseInitialised) return;
    _started = true;

    try {
      _subscriptions.addAll([
        _platform.foregroundMessages.listen(_onReceived),
        _platform.openedMessages.listen((message) => _onOpened(message, source: 'background')),
        _platform.tokenRefreshes.listen((_) {
          // The old token is dead on FCM's side; forget that it was registered so the new one is.
          _registered = null;
          unawaited(_sync());
        }),
      ]);

      final initial = await _platform.initialMessage();
      if (initial != null) {
        _initial = initial;
        _onOpened(initial, source: 'launch');
      }
    } catch (error) {
      debugPrint('[push] could not start: $error');
    }
  }

  /// Asks for notification permission if it has not been settled, and reports the answer.
  ///
  /// The shape of `AttConsent.ensure`: guarded in-process so a rebuild cannot queue a second
  /// dialog, never throws, and never blocks anything — a caller that awaited this would be waiting
  /// on a user reading a dialog.
  Future<void> ensurePermission() async {
    if (_asked || !firebaseInitialised) return;
    await _resolvePermission(source: 'home');
  }

  /// Whether the system prompt could still be shown — iOS has not asked yet, or Android has never
  /// been asked on this install. False without Firebase, and once the answer is settled either way.
  ///
  /// The primer asks this first, so it never explains a dialog that is not coming.
  Future<bool> canPrompt() async {
    if (!firebaseInitialised) return false;
    try {
      final current = await _platform.currentPermission();
      return current == AuthorizationStatus.notDetermined ||
          (_platform.name == 'android' && current == AuthorizationStatus.denied && !await _hasAsked());
    } catch (_) {
      return false;
    }
  }

  /// True when notifications are allowed right now.
  Future<bool> isAuthorized() async {
    if (!firebaseInitialised) return false;
    try {
      return _isGranted(await _platform.currentPermission());
    } catch (_) {
      return false;
    }
  }

  /// The system prompt, asked because the user tapped something that wants it — the primer's
  /// Allow, or "Notify me when ready". Returns whether notifications are now allowed.
  ///
  /// Unlike [ensurePermission] it asks even if Home already resolved the question this session: a
  /// tap is a request, and an already-settled answer is simply returned rather than re-prompted.
  Future<bool> requestFromPrimer({required String source}) async {
    if (!firebaseInitialised) return false;
    return _resolvePermission(source: source);
  }

  Future<bool> _resolvePermission({required String source}) async {
    _asked = true;

    try {
      final current = await _platform.currentPermission();

      // iOS reports `notDetermined` until it has asked, and every later answer is final. Android
      // reports `denied` for both "never asked" and "said no", so the disk flag decides; the OS
      // itself refuses to show the dialog again once the user has declined it for good.
      final prompt = current == AuthorizationStatus.notDetermined ||
          (_platform.name == 'android' &&
              current == AuthorizationStatus.denied &&
              !await _hasAsked());

      final status = prompt ? await _platform.requestPermission() : current;
      if (prompt) await _rememberAsked();

      final granted = _isGranted(status);

      analytics.track(Ev.pushPermissionResolved, {
        P.status: status.name,
        P.granted: granted,
        P.prompted: prompt,
        P.source: source,
      });

      // On iOS the APNs token often lands around the prompt, so this is a good moment to retry a
      // registration that found no token earlier. A change in the answer re-registers as well, so
      // the sender learns the device can now show a push.
      await _sync();
      return granted;
    } catch (error) {
      debugPrint('[push] could not resolve notification permission: $error');
      return false;
    }
  }

  static bool _isGranted(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized || status == AuthorizationStatus.provisional;

  /// Gives registration somewhere to go. Called by `pushBootstrapProvider`.
  Future<void> attachBackend(PushRepository backend) async {
    _backend = backend;
    _registered = null;
    await _sync();
  }

  /// Registers this device for [user]. Called from the entitlement hook on every resolve.
  Future<void> onUserResolved(AppUser user) async {
    _userId = user.id;
    await _sync();
  }

  /// Registers the current token for the current user, once per pair.
  ///
  /// Overlapping calls are coalesced rather than dropped: a backend attached while a sync is
  /// already in flight must still get its registration, not wait for the next resume.
  Future<void> _sync() async {
    if (_syncing) {
      _resync = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _resync = false;
        await _syncOnce();
      } while (_resync);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncOnce() async {
    final userId = _userId;
    if (!firebaseInitialised || userId == null) return;

    try {
      final token = await _platform.token();
      if (token == null) return;

      final authorized = _isGranted(await _platform.currentPermission());
      final build = await _appBuild();

      // The permission is part of the key: turning notifications on in Settings has to reach the
      // sender on the next resume, or the device stays filtered out as one that cannot show a push.
      final key = '$userId|$token|$authorized|$build';
      if (_registered == key) return;

      if (await _backend.register(
        token: token,
        platform: _platform.name,
        appBuild: build,
        notificationsAuthorized: authorized,
      )) {
        _registered = key;
      }
    } catch (error) {
      debugPrint('[push] could not register this device: $error');
    }
  }

  void _onOpened(RemoteMessage message, {required String source}) {
    final payload = PushPayload.fromData(message.data);
    analytics.track(Ev.pushOpened, {
      P.source: source,
      P.messageId: message.messageId,
      P.campaign: ?payload.campaign,
      P.notificationId: ?payload.notificationId,
      P.route: ?payload.route,
    });
    _opened.add(message);
  }

  void _onReceived(RemoteMessage message) {
    final payload = PushPayload.fromData(message.data);
    analytics.track(Ev.pushReceived, {
      P.messageId: message.messageId,
      P.campaign: ?payload.campaign,
      P.notificationId: ?payload.notificationId,
      P.route: ?payload.route,
    });
    _received.add(message);
  }

  Future<bool> _hasAsked() async {
    try {
      return await _preferences.getBool(_askedKey) ?? false;
    } catch (error) {
      // Answered as "asked" so a broken preferences store cannot turn into a prompt on every
      // launch — the failure the flag exists to prevent.
      debugPrint('[push] could not read the prompt flag: $error');
      return true;
    }
  }

  Future<void> _rememberAsked() async {
    try {
      await _preferences.setBool(_askedKey, true);
    } catch (error) {
      debugPrint('[push] could not persist the prompt flag: $error');
    }
  }

  @visibleForTesting
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _opened.close();
    await _received.close();
  }
}

/// The app-wide instance, a top-level singleton like `attributionService`: boot starts it before
/// any `ProviderScope` exists, and the entitlement hook and Home both reach it without a `ref`.
final pushMessaging = PushMessaging();
