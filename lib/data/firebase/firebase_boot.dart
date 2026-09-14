import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'push_messaging.dart';

/// Set by boot once `Firebase.initializeApp` has actually returned.
///
/// The Firebase twin of `supabaseInitialised`, for the same reason: boot is allowed to swallow an
/// init failure and carry on, and every `FirebaseSomething.instance` reached after that throws.
/// Everything that touches Firebase checks this first — which is also what keeps `flutter test`,
/// where boot never runs, entirely free of Firebase.
bool firebaseInitialised = false;

/// Brings Firebase up from [DefaultFirebaseOptions], or deliberately leaves it down.
///
/// Android and iOS only; anywhere else `bootMobileApp` could reach — a desktop run of the
/// scaffolding — returns without trying. Never throws: an app that cannot reach its crash reporter
/// is still an app, and a crash on launch caused by the crash reporter would be the worst version
/// of this integration.
Future<void> startFirebase() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    firebaseInitialised = true;
  } catch (error) {
    debugPrint('Firebase init failed, continuing without it: $error');
    return;
  }

  try {
    // Off in debug. A developer's hot-reload exceptions are not crashes anybody shipped, and
    // letting them in would make the crash-free-users number describe the team's laptops. The
    // setting persists on the device, so it is set on every launch to match the build it is.
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
  } catch (error) {
    debugPrint('[crashlytics] could not set collection: $error');
  }

  try {
    // Registered before `runApp` on purpose: Android starts a separate background isolate for a
    // data message that arrives while the app is not running, and the handler has to be known by
    // the time it does.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (error) {
    debugPrint('[push] could not register the background handler: $error');
  }
}
