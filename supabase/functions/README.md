# supabase/functions

## Purpose

The Edge Functions — the whole backend API. Every third-party credential lives here, so none of
them ship inside the app. Deployed with `supabase functions deploy`.

## The 14 functions

Each is a folder holding one `index.ts`. They are indexed here rather than each carrying its
own README, so the auth column can be compared at a glance.

**"Auth" means the function's own check.** All 14 are `verify_jwt = false` in `config.toml` —
they are invoked with the anon key, before any session exists — so each validates for itself.

| Function | Endpoint | Auth | Notes |
|---|---|---|---|
| `send-otp` | POST `{mobile}` | none | per-mobile quota; dev-OTP and review-account short circuits |
| `resend-otp` | POST `{mobile}` | none | same quota and short circuits |
| `verify-otp` | POST `{mobile, otp}` | none | **mints the session token**; upserts `users`, inserts `user_sessions` |
| `me` | GET → user + entitlement; DELETE → account deletion | bearer | the relaunch session restore. Only `DELETE` is branched; any other method reads |
| `update-profile` | POST `{name?, dob?, birth_time?, birth_place?}` | bearer | the post-OTP steps |
| `palm-reading` | POST `{image, mime_type, focus}` | bearer + entitled | Gemini palm read, quota-anchored row |
| `face-reading` | POST `{image, mime_type, focus}` | bearer + entitled | the face mirror |
| `astro-chat` | POST `{message, thread_id?}` | bearer + entitled | one metered, chart-aware chat turn |
| `chat-history` | POST, multiplexed by body key | bearer | thread list, one transcript, user facts, and `delete_thread`/`rename`/`forget`. No model call |
| `subscription-start` | POST | bearer | creates the Cashfree mandate, returns the session payload |
| `subscription-status` | POST/GET | bearer | reads the latest subscription, optionally re-syncs, returns entitlement. No method check |
| `subscription-cancel` | POST | bearer | cancels the mandate, returns refreshed entitlement |
| `cashfree-webhook` | POST from Cashfree | **HMAC signature** | verifies `x-webhook-signature` over the raw body, dedupes, drives `syncSubscription` |
| `subscription-reconcile` | POST from `pg_cron` | **shared secret** | `app_config.reconcile_secret`, compared with `constantTimeEquals`; sweeps abandoned/drifted/stale subscriptions |

## Subfolders

- `_shared/` — everything more than one function needs: credentials, the billing state machine,
  the model prompts, the astronomy. Not deployed on its own.
- `tests/` — `deno test`, 182 tests over the pure logic.
- One folder per function in the table above.

## Notes

- **The user id never comes from the request body.** Every authed function resolves the caller
  from the bearer token via `userIdForBearer`, so no request can name an account but its own.
- `cashfree-webhook` and `subscription-reconcile` are the two that cannot use a bearer token —
  Cashfree cannot send an `apikey` header, and pg_cron has no session. Hence HMAC and a shared
  secret respectively.
- Adding a function means adding it to `config.toml` too, or it deploys with JWT verification on
  and rejects the anon key the app calls with.
- Gemini, Fast2SMS and Cashfree are reached **only** from here. The client sends no amount and
  no plan id — everything billable is resolved server-side from `app_config`.
- See [../README.md](../README.md) for the security model, setup and the money table.
