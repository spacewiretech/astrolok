# lib/data/repositories

## Purpose

Interfaces and typed exceptions only. **Nothing here knows about Supabase, Fast2SMS or the
fakes** — that is what lets [../providers.dart](../providers.dart) swap an implementation in one
line.

## Files

- `auth_repository.dart` — Declares: `AuthRepository` (`currentUser`, `sendOtp`, `resendOtp`,
  `verifyOtp`, `saveName`, `saveBirthDate`, `signOut`), `InvalidOtpException`,
  `OtpExpiredException`, `OtpSendException`.
- `palm_repository.dart` — Declares: `PalmRepository` (`read({image, focus})`), `PalmException`
  and its five subclasses: `NoPalmDetected…`, `PalmLimitReached…`, `PalmUnavailable…`,
  `PalmNotEntitled…`, `PalmSignedOut…`.
- `face_repository.dart` — the same five-exception shape for faces. Declares: `FaceRepository`
  (`read({image, focus})` — note it takes a `PalmFocus`), `FaceException`, `NoFaceDetected…`,
  `FaceLimitReached…`, `FaceUnavailable…`, `FaceNotEntitled…`, `FaceSignedOut…`.
- `chat_repository.dart` — Declares: `ChatRepository` (`send`, `threads`, `history`,
  `renameThread`, `deleteThread`, `forget`), `ChatReply`, `ChatThreadList`, `ChatSnapshot`,
  `ChatException` + `ChatLimitReached…`, `ChatUnavailable…`, `ChatNotEntitled…`,
  `ChatSignedOut…`, `ChatThreadGone…`.
- `subscription_repository.dart` — Declares: `SubscriptionRepository` (`offer`, `start`,
  `refreshStatus`, `cancel`), `SubscriptionException`.
- `app_config_repository.dart` — runtime config served from the backend rather than baked into
  the build. Declares: `AppConfigRepository` (`load({force})`, `remoteKeys`), `defaultAppConfig`,
  `shippedAppConfig`, and the `AppConfigValues` extension on `Map<String, String>`
  (`configString`, `configInt`, `configFlag`, `configLink`, `configList`).

## Notes

- **The exception families are the contract.** Each reading flow maps a server failure onto one
  of five cases, and the capture/scan screens switch on exactly those — so a new failure mode
  means a new subclass here first.
- **Four layers, and the order matters**: `defaultAppConfig` < `Env` (the `app_config` mirror in
  `assets/env/app.env`) < the disk cache < Supabase. Env sits *below* the cache on purpose — the
  cache holds the last known server state, which is fresher truth than a snapshot taken when the
  build was cut. `shippedAppConfig` is the bottom two layers merged, and is the base every read
  path in `SupabaseAppConfigRepository` merges onto so no two of them can disagree.
- `defaultAppConfig` holds the last-resort fallbacks (₹3/₹249 pricing, the privacy/terms/help
  URLs) for a checkout with no `app.env`. The Mixpanel token is *deliberately absent* from it: no
  row means no token means no tracking.
- `configList` reads a comma-separated row (`chat_languages`) as a list, trimmed and deduped. It
  is the one accessor where **empty is a real answer** rather than something to fall back from:
  blanking that cell is the documented way to hide the language picker, so behaving like
  `configLink` would defeat the off switch. A *missing* key still falls through to the default —
  absence is a cold start, emptiness is a decision.
- `remoteKeys` answers what the backend or its cache actually served, env and compiled defaults
  excluded. It exists for `analyticsBootstrapProvider`, whose one-shot cache-bypass fires on a
  key being *absent*; now that `app.env` ships every key, testing the merged map would mean that
  refresh could never fire again. Any new key whose *arrival* is the event belongs in that check,
  or installed apps ignore the new row until their cache ages out.
- **`remoteKeys` covers a new key; `maxAge` covers a changed value.** They are not the same case
  and the difference has already caused one bug. A language added to an existing `chat_languages`
  row is not a new key, so the absence check never fires and the six-hour TTL hid the edit —
  which made "edit the dashboard, no release" true exactly once per key. `load(maxAge:)` serves
  the cache only while it is younger than the window given, and Home passes one minute, matching
  `loadConfig`'s TTL in the Edge Functions so client and server pick up an edit at the same rate.
- Views never call these directly; ViewModels reach them through
  [../providers.dart](../providers.dart).
- Note `auth_repository.dart`'s header comment is stale — it says the Supabase implementation
  "will wrap `supabase.auth.signInWithOtp`", but Supabase Auth is off and
  [../supabase/supabase_auth_repository.dart](../supabase/supabase_auth_repository.dart) calls
  the Edge Functions instead.
