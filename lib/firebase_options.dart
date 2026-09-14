// Hand-written from android/app/google-services.json and ios/Runner/GoogleService-Info.plist,
// because the FlutterFire CLI is not part of this project's toolchain. Keep the three in step: a
// value changed here and not in the native file, or the reverse, points Dart and the native SDKs
// at two different Firebase apps.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// The Firebase apps this build talks to, one per shipping platform.
///
/// Android and iOS only. The web build is the marketing site and never initialises Firebase, and
/// macOS, Windows and Linux are unshipped scaffolding — asking for any of those is a programming
/// error, so it throws rather than quietly configuring one platform against another's app.
///
/// None of these values is a secret. They identify the project, ship inside every installed app,
/// and are restricted to this app's package and bundle id in the Google Cloud console.
abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Firebase is not configured for web: the web build is the marketing site.',
      );
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      final platform => throw UnsupportedError(
          'Firebase is not configured for ${platform.name}: only Android and iOS ship.',
        ),
    };
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBEprnSzkGpDoGk8apfwlsUgogi6dK5wW8',
    appId: '1:125649192472:android:33ccd89eda0f22872d256d',
    messagingSenderId: '125649192472',
    projectId: 'astrolok-21088',
    storageBucket: 'astrolok-21088.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCQ4YH8VlS2NjqmNnV9nvVQqI-WQR17JKw',
    appId: '1:125649192472:ios:5f88f06207f5e20c2d256d',
    messagingSenderId: '125649192472',
    projectId: 'astrolok-21088',
    storageBucket: 'astrolok-21088.firebasestorage.app',
    iosBundleId: 'com.spacewire.astrolok',
  );
}
