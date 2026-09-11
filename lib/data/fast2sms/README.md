# lib/data/fast2sms

## Purpose

The middle rung of the backend ladder: real SMS OTP called **directly from the device**. Used
only when there is a Fast2SMS key but no Supabase project.

## Files

- `fast2sms_client.dart` — the HTTP calls. Declares: `VerifyResult` (enum: `verified`,
  `wrongCode`, `expiredOrUsed`), `Fast2SmsClient`.
- `fast2sms_auth_repository.dart` — adapts the client to the app's auth port. Declares:
  `Fast2SmsAuthRepository`.
- `fast2sms_exception.dart` — Declares: `Fast2SmsException`, which carries two messages on
  purpose: `userMessage` is safe to show on screen, `developerDetail` is not.

## Notes

- **This tier ships the API key inside the app and stores nothing.** It exists so OTP can be
  exercised without standing up Supabase; it is not the production path. On the Supabase tier
  the same provider sends OTP through `send-otp` / `verify-otp` and the key stays server-side.
- Auth is the only capability with all three rungs. Palm, face, chat, subscription and checkout
  are Supabase-or-fake — there is no direct-to-Gemini rung, since that would ship that key too.
- Selected in [../providers.dart](../providers.dart) by `Env.isConfigured` when
  `Env.hasSupabase` is false.
