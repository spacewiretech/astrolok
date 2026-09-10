# lib/data/supabase

## Purpose

The top rung of the backend ladder and the only production path: every repository implemented
against the Edge Functions, plus the secure store for the session token. **No third-party API
key is present on this tier.**

## Files

- `edge_functions.dart` — the one place a function is invoked. Declares: `EdgeError` (carries
  the server's `code`), `EdgeFunctions` (`call(...)`), `SupabaseEdgeFunctions`.
- `session_store.dart` — holds the opaque token issued by `verify-otp`. Declares:
  `SessionStore`.
- `supabase_auth_repository.dart` — Declares: `SupabaseAuthRepository`.
- `supabase_palm_repository.dart` — Declares: `SupabasePalmRepository`.
- `supabase_face_repository.dart` — Declares: `SupabaseFaceRepository`.
- `supabase_chat_repository.dart` — Declares: `SupabaseChatRepository`.
- `supabase_subscription_repository.dart` — Declares: `SupabaseSubscriptionRepository`.
- `supabase_app_config_repository.dart` — Declares: `SupabaseAppConfigRepository` (disk-cached,
  `readCachedConfig()` static, and it never hangs the splash), `FakeAppConfigRepository`.

## Notes

- **Supabase Auth is off**, so there is no JWT and no `autoRefreshToken`. `verify-otp` mints a
  256-bit opaque token, the server stores only its SHA-256 hash, and the app keeps the raw token
  in the Keychain/Keystore via `SessionStore`. Every authed call sends it as a bearer token.
- Gemini, Fast2SMS and Cashfree are **never** called from the device on this tier — the
  functions hold those credentials. That is the whole point of the rung.
- `EdgeError.code` is what the repositories switch on to raise the right typed exception from
  [../repositories/](../repositories/) (`no_palm`, `limit_reached`, `not_entitled`, …).
- The config cache is read from disk at boot by
  [../../boot/mobile_boot_io.dart](../../boot/mobile_boot_io.dart) so the Mixpanel token is
  available before the first frame; a first launch finds nothing and fetches later.
- Backend contract lives in [../../../supabase/](../../../supabase/) — the roll-up table in
  `supabase/functions/README.md` lists each endpoint and its auth.
