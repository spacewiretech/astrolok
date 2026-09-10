# macos

## Purpose

Unmodified `flutter create` scaffolding for a macOS desktop build. **Not a target this project
ships** — Astrolok is a phone app plus a web marketing site.

## Files

- `Runner/` — `AppDelegate.swift`, `MainFlutterWindow.swift`, `Info.plist`, `MainMenu.xib`, and
  the `DebugProfile`/`Release` entitlements.
- `Runner/Configs/` — `AppInfo.xcconfig`, `Debug`, `Release`, `Warnings`.
- `Flutter/` — `Flutter-Debug.xcconfig`, `Flutter-Release.xcconfig`, and the generated
  `GeneratedPluginRegistrant.swift`.
- `Podfile`, `Runner.xcodeproj/`, `Runner.xcworkspace/`, `RunnerTests/RunnerTests.swift`.

## Notes

- Nothing here has been hand-edited. There is no signing config, no bundle-id change, and none
  of the camera / Facebook / UPI setup that [../ios/](../ios/) carries.
- **It would not work if built.** The app depends on `flutter_cashfree_pg_sdk`, `camera` and
  `facebook_app_events`, none of which support macOS, and the whole payment flow assumes a UPI
  app on the same device.
- Safe to delete if desktop is never wanted; kept because removing generated platform folders
  tends to be re-created by tooling.
