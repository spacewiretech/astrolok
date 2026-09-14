# lib/data/firebase

## Purpose

Firebase start-up, and push notifications. Crashlytics is wired into the error handlers in
[../../boot/mobile_boot_io.dart](../../boot/mobile_boot_io.dart), and the Analytics sink lives in
[../analytics/](../analytics/); this folder is what both of them depend on being up.

## Files

- `firebase_boot.dart` — Declares: `firebaseInitialised`, `startFirebase()`. Initialises from
  `lib/firebase_options.dart` on Android and iOS only, turns Crashlytics collection off in debug,
  and registers the background message handler. Never throws.
- `push_messaging.dart` — Declares: `firebaseMessagingBackgroundHandler`, `PushPlatform` (the port
  over Firebase Messaging), `FirebasePushPlatform`, `PushMessaging` (`start`, `ensurePermission`,
  `attachBackend`, `onUserResolved`, `opened`, `takeInitialMessage`), and the `pushMessaging`
  singleton.

## Notes

- **`lib/firebase_options.dart` is hand-written** from `android/app/google-services.json` and
  `ios/Runner/GoogleService-Info.plist` — there is no FlutterFire CLI in this toolchain. Change a
  value in all three places or in none. Every platform other than Android and iOS throws.
- **Everything gates on `firebaseInitialised`**, the twin of `supabaseInitialised`. It is what
  makes a failed init non-fatal, and what keeps `flutter test` free of Firebase.
- **There is no notification UI.** A message that arrives in the foreground is logged and
  dropped; in the background the OS shows notification messages itself. Taps are reported as
  `Push Opened` and published on `PushMessaging.opened`, plus `takeInitialMessage()` for a cold
  start — that is the routing hook — but no route listens yet, because nothing sends a push yet.
- **Tokens are registered against the session**, through the `push-token` Edge Function, from the
  entitlement hook and on token refresh. Sign-out needs nothing from the app: `me` DELETE drops the
  session and the `push_tokens` row cascades with it. See
  `supabase/migrations/20260914000001_push_tokens.sql`.
- **The prompt is asked from Home, after ATT**, never at launch. Android reports `denied` both
  before its prompt has been shown and after a refusal, so a disk flag
  (`astrolok.push_permission_asked`) limits it to one ask per install.
- Setup outside the repo that is easy to miss: iOS needs the Push Notifications capability on the
  App ID and an APNs auth key uploaded to the Firebase console, or no token ever arrives.
- No Android notification small icon is set, so FCM falls back to the launcher icon, which renders
  as a white square in the status bar. A monochrome `ic_notification` is still to do.
