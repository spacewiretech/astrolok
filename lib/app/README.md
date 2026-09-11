# lib/app

## Purpose

The phone app's shell: the root widget, the route table, environment values, bundled asset
paths, the paid-content gate, and the analytics navigation observer.

## Files

- `app.dart` — Declares: `AstrolokApp` (a `ConsumerWidget` building `MaterialApp.router` from
  `appRouter` + `buildAppTheme()`; it watches `analyticsBootstrapProvider` purely to keep it
  alive).
- `router.dart` — Declares: `Routes` (every path constant, plus the builders `onboardingAt`,
  `paymentStatusFor`, `palmReadingFor`, `palmLineFor`, `faceReadingFor`, `facePartFor`),
  `SplashDestinationRoute` extension, `appRouter`.
- `entitlement_gate.dart` — Declares: `EntitlementGate`.
- `analytics_observer.dart` — Declares: `screenNameFor()`, `AnalyticsNavigatorObserver`,
  `analyticsObserver`, and the private route→name tables `_screenNames` / `_modalNames`.
- `assets.dart` — every bundled asset path in one place. Declares: `Img`, `Brand`, `PalmIcon`,
  `FaceIcon`, `ChatIcon`, `Svg`.
- `env.dart` — values read from `assets/env/app.env` at startup. Declares: `Env` (`load`,
  `hasSupabase`, `isConfigured`, `configurationSummary`, and the key getters).

## Subfolders

- `theme/` — colours, geometry and the type scale, read off the Figma renders.

## Notes

- **`EntitlementGate` re-checks on mount, on resume, and on a timer armed for the entitlement
  expiry.** A one-day trial will routinely run out while the app is open in someone's pocket,
  and a cold-start check alone would miss it. It always re-asks the server; the timer is capped
  at a 6-hour horizon.
- **Gating is per-route.** `appRouter` has no global redirect — paid routes are individually
  wrapped, and `/birth`, `/subscribe` and `/payment-status/:outcome` are deliberately ungated.
- `Env.load()` tolerates a missing file: the getters fall back to empty strings, `isConfigured`
  goes false, and the app runs on the fake tier. That is what makes a fresh checkout walkable.
- `assets.dart` lists paths that **do not all exist yet** — every `Svg.*` entry is still to be
  exported. That is safe because they load through `SafeImage`/`SafeSvg`, which fall back to a
  Material icon. See [../widgets/](../widgets/).
- `analytics_observer.dart` keys its tables by route **pattern**, not resolved path, because
  that is what go_router puts in `RouteSettings.name`. It also tracks time-on-screen and feeds
  a `screensViewed` count into `AnalyticsSession`.
- `ProviderScope` is **not** created here — see [../boot/](../boot/).
