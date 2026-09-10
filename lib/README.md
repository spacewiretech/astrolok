# lib

## Purpose

All Dart source for both things this repo builds: the Astrolok phone app, and the marketing
site that is the whole of the web build.

## Files

- `main.dart` — Declares: `main()`. Branches on `kIsWeb`: on web it calls
  `configureUrlStrategy()`, runs `AstrolokSiteApp` and **returns**; otherwise it awaits
  `bootMobileApp()`.

## Subfolders

- `app/` — the phone app shell: root widget, routes, `Env`, asset paths, `EntitlementGate`,
  analytics observer. Contains `theme/`.
- `boot/` — the compile-time mobile/web split and the phone app's startup sequence.
- `data/` — the whole data layer: repository interfaces, three implementations, models, and
  `providers.dart`, the single wiring surface.
- `features/` — one folder per screen or flow, roughly
  `<name>_{view,viewmodel,state,copy}.dart`.
- `widgets/` — shared design-system widgets. No feature imports.
- `website/` — the marketing site. Independent of everything above; contains `pages/`.

## Notes

- **Two apps in one binary.** `lib/website/` and the rest share the brand and nothing else — no
  Riverpod, no repositories, no `Env`. Both claim `/`, so their routers cannot be merged.
- **The split has to be at compile time.** Seven files reach `dart:io` and dart2js rejects the
  import before tree-shaking can drop it, so `boot/mobile_boot.dart` is a conditional export
  rather than a runtime `if`. `website/url_strategy.dart` is the second such export.
- Architecture rule: **views never call repositories; viewmodels never call the router.** A
  viewmodel that finishes a step returns a destination and the view routes on it — which is how
  the splash and every onboarding step agree about where a user belongs.
- The backend rung (Supabase → Fast2SMS-direct → fake) is chosen in `data/providers.dart` from
  what `assets/env/app.env` contains. With no such file the app runs entirely on fakes.
- Start reading at `main.dart` → `boot/mobile_boot_io.dart` → `app/router.dart` →
  `features/splash/`, which is the gate every launch passes through.
