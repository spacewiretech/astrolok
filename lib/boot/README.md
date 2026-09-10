# lib/boot

## Purpose

The compile-time split between the phone app and the web build, and the phone app's real
startup sequence.

## Files

- `mobile_boot.dart` — a conditional export on `dart.library.io`: the stub for web, the real
  one otherwise. No logic of its own.
- `mobile_boot_io.dart` — startup. Declares: `bootMobileApp()`, plus private `_startAnalytics()`
  and `_reportUncaughtErrors()`. Loads `Env`, optionally calls `Supabase.initialize`, brings
  analytics up, then `runApp`.
- `mobile_boot_stub.dart` — a no-op `bootMobileApp()` for web. Never called; it exists so the
  web build has a symbol to resolve without pulling in the `dart:io` half.

## Notes

- **The split is required, not an optimisation.** The app tree reaches `dart:io` in seven
  places (`edge_functions.dart`, `fast2sms_client.dart`, `reading_camera.dart`,
  `reading_speech.dart`, `reading_image_store.dart`, and both reading viewmodels), and dart2js
  rejects the import before tree-shaking can drop it — so a runtime `if (kIsWeb)` would not
  compile.
- **`ProviderScope` is created here, not in `app.dart`**, with one override:
  `analyticsProvider.overrideWithValue(analytics)`, so the global holder (`installAnalytics`)
  and Riverpod can never disagree about the sink.
- Supabase init failure is caught and logged, not fatal — the providers fall back to the
  Fast2SMS or fake tier and the app stays walkable.
- Analytics starts twice on purpose: here from the disk-cached `app_config`, then again via
  `analyticsBootstrapProvider` for a first launch where no cache existed. Events fired in
  between are buffered by `MixpanelAnalytics`.
