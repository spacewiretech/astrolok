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
  the build. Declares: `AppConfigRepository` (`load({force})`), `defaultAppConfig`, and the
  `AppConfigValues` extension on `Map<String, String>` (`configString`, `configInt`,
  `configFlag`, `configLink`).

## Notes

- **The exception families are the contract.** Each reading flow maps a server failure onto one
  of five cases, and the capture/scan screens switch on exactly those — so a new failure mode
  means a new subclass here first.
- `defaultAppConfig` holds the fallbacks (₹3/₹249 pricing, the privacy/terms/help URLs). The
  Mixpanel token is *deliberately absent* from it: no row means no token means no tracking.
- Views never call these directly; ViewModels reach them through
  [../providers.dart](../providers.dart).
- Note `auth_repository.dart`'s header comment is stale — it says the Supabase implementation
  "will wrap `supabase.auth.signInWithOtp`", but Supabase Auth is off and
  [../supabase/supabase_auth_repository.dart](../supabase/supabase_auth_repository.dart) calls
  the Edge Functions instead.
