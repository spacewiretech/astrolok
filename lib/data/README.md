# lib/data

## Purpose

The whole data layer: repository interfaces, three interchangeable implementations of them, the
domain models, and the single Riverpod binding surface the features reach all of it through.

## Files

- `providers.dart` — **the one place the app is wired together.** Declares every provider the
  features use: `sessionStoreProvider`, `analyticsProvider`, `analyticsBootstrapProvider`,
  `backendMode`, `appConfigRepositoryProvider`, `appConfigProvider`, `authRepositoryProvider`,
  `subscriptionRepositoryProvider`, `cashfreeCheckoutProvider`, `upiAppPreferenceProvider`,
  `promoVideoProvider`, `palmRepositoryProvider`, `faceRepositoryProvider`,
  `chatRepositoryProvider`, the per-feature
  camera/image/reading stores, `chatThreadStoreProvider`, `readingSpeechProvider`,
  `fakeSessionProvider`.
- `entitlement.dart` — the last entitlement answer the server gave, readable by routing.
  Declares: `EntitlementNotifier`, `entitlementProvider`.

## Subfolders

- `repositories/` — **interfaces and typed exceptions only.** Nothing here knows a backend.
- `supabase/` — the real implementations, over Edge Functions. The only production path.
- `fast2sms/` — direct-SMS OTP fallback; ships the key in the app.
- `fake/` — in-memory tier, so a fresh checkout is walkable.
- `models/` — plain domain types; `fromServer` degrades rather than throwing.
- `analytics/` — the `Analytics` port, the Mixpanel and Facebook sinks, ATT consent.
- `camera/` — the camera port and capture downscale/crop.
- `cashfree/` — the UPI checkout SDK wrapper.
- `local/` — on-device caches for readings, threads and photos.
- `media/` — the paywall promo player, opened during onboarding rather than at the paywall.
- `pdf/` — reading → shareable PDF, composed on a background isolate.
- `tts/` — on-device text-to-speech for reading a result aloud.

## Notes

- **The three-rung ladder is chosen in `providers.dart`**, by `Env.hasSupabase` /
  `Env.isConfigured`: Supabase → Fast2SMS-direct → fake. Only *auth* has all three rungs;
  palm, face, chat, subscription and checkout are Supabase-or-fake, because a direct rung would
  mean shipping the Gemini or Cashfree key.
- **No view or viewmodel imports a concrete repository** — swapping an implementation is a
  one-line edit on the right-hand side of a provider here.
- `backendMode` stamps the active rung onto every analytics event, so fake-tier traffic never
  pollutes production funnels.
- A few providers live outside this file on purpose: `entitlementProvider` (next door),
  the palm/face rejection and limit providers (in their capture *views*), `selectedThreadProvider`
  and `subscriptionPollDelaysProvider` (in their viewmodels).
- **Entitlement is derived, never stored** — the server computes it from `payment_type` plus
  the trial/period dates, so a stalled webhook expires an account by the clock rather than
  leaving it entitled forever. `entitlement.dart` only caches the last answer.
