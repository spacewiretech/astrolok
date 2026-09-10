# lib/data/analytics

## Purpose

The analytics abstraction and its two real sinks (Mixpanel, Facebook), plus the ambient
properties attached to every event and the iOS tracking-consent prompt.

## Files

- `analytics.dart` — the interface and the plumbing. Declares: `Analytics` (`track`,
  `timeEvent`, `identify`, `reset`, `registerSuper`, `trackCharge`, `flush`), `NoopAnalytics`,
  `MultiAnalytics` (fan-out; one throwing sink must not cost the others their event),
  `analyticsSink<T>()`, `installAnalytics()`, `trackedTap()`, `slugify()`.
- `analytics_events.dart` — the whole vocabulary, as constants rather than string literals at
  call sites. Declares: `Ev` (event names), `P` (property keys), `ExitType`, `NavType`,
  `BackendMode`, `ReadingFeature`.
- `analytics_context.dart` — **install-lifetime** properties: install id, app version, days
  since install, device info. Gathered once and registered as super properties. Declares:
  `AnalyticsContext` (`collect()`).
- `analytics_session.dart` — **run-lifetime** properties: session id, app lifecycle, the
  30-minute idle timeout, and the round trip out to a UPI app. Declares: `AnalyticsSession`
  (`contextProperties()`, `attach()`, `dispose()`).
- `mixpanel_analytics.dart` — the primary sink, with a queue in front of it. Declares:
  `MixpanelAnalytics` (`start(token)`).
- `facebook_analytics.dart` — ad-attribution sink; receives ~4 conversion events of the ~60 the
  app fires, and holds a persisted guard so one purchase is never reported twice. Declares:
  `FacebookAnalytics` (`start(...)`).
- `att_consent.dart` — asks iOS for the advertising identifier, once per install, deliberately
  not at launch. Declares: `AttConsent`, `ensureTrackingConsent()`.

## Notes

- **The Mixpanel token is not compiled in.** It is a row in `app_config`, so tracking can be
  turned off server-side without a release. That is why `MixpanelAnalytics` queues: events fire
  before the token has been fetched. A checkout with no token runs on `NoopAnalytics`.
- Both sinks are wrapped in a `MultiAnalytics` in [../../boot/mobile_boot_io.dart](../../boot/mobile_boot_io.dart);
  reach a specific one with `analyticsSink<T>()` rather than an `is` test, since the installed
  sink may be the no-op or the fan-out.
- Screen names and time-on-screen come from
  [../../app/analytics_observer.dart](../../app/analytics_observer.dart), which feeds its
  `screensViewed` count into `AnalyticsSession.attach()`.
- `backendMode` (in [../providers.dart](../providers.dart)) stamps every event, so fake-tier
  traffic does not pollute production funnels.
- Server-side events the client can never observe (renewals, holds, chargebacks) are sent by
  `supabase/functions/_shared/mixpanel.ts` instead.
