# test

## Purpose

The Flutter test suite — 23 files, a mix of pure unit tests and `testWidgets` layout tests.
Run with `flutter test` (the root README quotes 246 tests, 52 of them the website).

## Files

**Onboarding and account**
- `widget_test.dart` — `OnboardingState`: Indian mobile validation, code invalidation when the
  number changes, the wall-clock resend countdown.
- `onboarding_gate_test.dart` — `destinationForSession` routing: signed-out → onboarding, name
  step, birth date, paywall.
- `field_focus_test.dart` — autofocus and focus rings across the `AnimatedSwitcher`-swapped
  onboarding sheets.
- `birth_test.dart` — `BirthState` date math: days-in-month, leap years, 29 Feb before a year is
  chosen.

**Money**
- `entitlement_test.dart` — `AppUser.recomputeOffline`: client-side trial / grace / `none` rules.
- `offer_test.dart` — `defaultAppConfig`: ₹3/₹249 pricing, empty marketing claims, `configInt`
  fallbacks.
- `layout_test.dart` — paywall and birth screen at 393×852 and on a tall phone.

**Readings**
- `palm_layout_test.dart`, `face_layout_test.dart` — capture screen layout, the no-camera
  message, focus picker options.
- `palm_camera_test.dart` — `palmCameraProvider` lifecycle (ready / unavailable / capture); the
  autoDispose spin-forever bug.
- `palm_error_test.dart` — every failure mode of the reading endpoint and its mapping to app
  outcomes (`no_palm`, `limit_reached`, long timeout).
- `palm_progress_test.dart` — scan progress curve invariants: monotonic, never reaches 1 before
  the reading completes.
- `palm_reading_parse_test.dart`, `face_reading_parse_test.dart` — `fromServer` ordering,
  unknown and duplicate keys, degrade-never-throw.
- `capture_viewfinder_test.dart` — viewfinder geometry (sensor aspect ratio, cover vs fit); the
  on-device stretched-preview bug.
- `reading_pdf_test.dart` — PDF export for both readings, **including that the fonts are
  actually bundled**.

**Chat and home**
- `chat_layout_test.dart` — opening screen and transcript on small and tall phones.
- `chat_parse_test.dart` — `AstroMessage.fromServer` plus conversation caching.
- `promo_carousel_test.dart` — auto-advance, swipe cooldown, reduce-motion, single-slide, card
  width.

**Cross-cutting**
- `analytics_test.dart` — `NoopAnalytics` and `MultiAnalytics`; a throwing sink must not cost
  the others their event.
- `facebook_analytics_test.dart` — the off switches (blank app id, `facebook_events_enabled =
  false`) and the event allowlist.
- `asset_fallback_test.dart` — missing image/SVG fallbacks, so screens lay out correctly before
  the artwork exists.
- `website_test.dart` — the marketing site: headline and price, reading names, "Chat with Astro
  not built yet", and **price parity with the paywall defaults**.

## Notes

- Flat by design — one file per concern, no subfolders, no shared helpers directory.
- Several tests exist because of a specific bug that shipped; the file comments say which. Treat
  those as regression guards, not coverage padding.
- Widget tests run without a camera or platform channels, which is why `FakeReadingCamera` and
  `NoopAnalytics` exist in the app tree rather than here.
- `subscriptionPollDelaysProvider` is overridable precisely so the paywall tests do not wait out
  the real poll schedule.
- The backend has its own suite: `supabase/functions/tests/`, run with `deno test`.
