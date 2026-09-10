# ios

## Purpose

The iOS build: the Xcode project, CocoaPods, `Info.plist` and the per-environment Facebook
values.

## Files

- `Runner/Info.plist` — the interesting one. Holds `NSCameraUsageDescription`,
  `NSPhotoLibraryUsageDescription`, `NSUserTrackingUsageDescription` (the ATT prompt copy),
  the **SKAdNetwork identifiers**, `LSApplicationQueriesSchemes` for the UPI apps, and the
  URL schemes Cashfree hands control back on.
- `Runner/AppDelegate.swift`, `Runner/SceneDelegate.swift`, `Runner/Runner-Bridging-Header.h` —
  the app shell. No custom platform channels.
- `Runner/Base.lproj/` — `LaunchScreen.storyboard`, `Main.storyboard`.
- `Flutter/Debug.xcconfig`, `Flutter/Release.xcconfig`, `Flutter/AppFrameworkInfo.plist` —
  build config.
- `Flutter/Facebook.xcconfig.example` — **committed template**; copy to `Facebook.xcconfig`
  (gitignored) and fill in `FACEBOOK_APP_ID` and `FACEBOOK_CLIENT_TOKEN`.
- `Podfile`, `Podfile.lock` — CocoaPods.
- `Runner.xcodeproj/`, `Runner.xcworkspace/` — the Xcode project. **Open the `.xcworkspace`,
  not the `.xcodeproj`.**
- `RunnerTests/RunnerTests.swift` — the default template test.

## Notes

- **SKAdNetwork matters more than the ATT prompt.** Most users decline tracking, and Apple's
  install-attribution channel is the only one left when they do — without those identifiers the
  campaign is flying blind.
- The ATT prompt is deliberately **not** shown at launch; see
  [../lib/data/analytics/att_consent.dart](../lib/data/analytics/att_consent.dart) for when it
  is asked and why.
- Neither Facebook value is a secret — both ship in every installed app; they are gitignored
  because they are per-environment. The Facebook app secret is a server-side Conversions API
  credential and belongs nowhere in this repo.
- `remove_alpha_ios: true` and a navy `background_color_ios` in `pubspec.yaml` stop the flattened
  icon showing a white ring.
- `Runner/Assets.xcassets/**` is generated (22 app-icon sizes plus the launch image, which
  carries Flutter's own README). Not indexed.
