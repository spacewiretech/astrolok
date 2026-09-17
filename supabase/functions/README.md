# supabase/functions

## Purpose

The Edge Functions — the whole backend API. Every third-party credential lives here, so none of
them ship inside the app. Deployed with `supabase functions deploy`.

## The functions

Each is a folder holding one `index.ts`. They are indexed here rather than each carrying its
own README, so the auth column can be compared at a glance.

**"Auth" means the function's own check.** Every one is `verify_jwt = false` in `config.toml` —
they are invoked with the anon key, before any session exists — so each validates for itself.

| Function | Endpoint | Auth | Notes |
|---|---|---|---|
| `send-otp` | POST `{mobile}` | none | per-mobile quota; dev-OTP and review-account short circuits |
| `resend-otp` | POST `{mobile}` | none | same quota and short circuits |
| `verify-otp` | POST `{mobile, otp}` | none | **mints the session token**; upserts `users`, inserts `user_sessions` |
| `me` | GET → user + entitlement; DELETE → account deletion | bearer | the relaunch session restore. Only `DELETE` is branched; any other method reads |
| `update-profile` | POST `{name?, dob?, birth_time?, birth_place?, language?, push_marketing_opt_out?}` | bearer | the post-OTP steps, the chat language, and Profile → "Offers & reminders" |
| `push-token` | POST `{token, platform, app_build?, notifications_authorized?}` | bearer | upserts `push_tokens` on the FCM token, bound to the caller's session so sign-out removes it by cascade. The two optional fields let the sender skip old builds and devices that cannot show a push |
| `palm-reading` | POST `{image, mime_type, focus}` | bearer + entitled | Gemini palm read, quota-anchored row |
| `face-reading` | POST `{image, mime_type, focus}` | bearer + entitled | the face mirror |
| `astro-chat` | POST `{message, thread_id?}` | bearer + entitled | one metered, chart-aware chat turn. Also returns `language`, `saved_language` (only when the message switched it) and `ask_rating` |
| `chat-history` | POST, multiplexed by body key | bearer | thread list, one transcript, user facts, and `delete_thread`/`rename`/`forget`/`rate` (`{thread_id, rating: 1-5 \| null}`, once per account). No model call |
| `subscription-start` | POST | bearer | creates the Cashfree mandate, returns the session payload |
| `subscription-status` | POST/GET | bearer | reads the latest subscription, optionally re-syncs, returns entitlement. No method check |
| `subscription-cancel` | POST | bearer | cancels the mandate, returns refreshed entitlement |
| `cashfree-webhook` | POST from Cashfree | **HMAC signature** | verifies `x-webhook-signature` over the raw body, dedupes, drives `syncSubscription` |
| `subscription-reconcile` | POST from `pg_cron` | **shared secret** | `app_config.reconcile_secret`, compared with `constantTimeEquals`; sweeps abandoned/drifted/stale subscriptions |
| `place-search` | POST `{action: autocomplete \| details, …, session_token}` | bearer + entitled | Google Places (New) + Time Zone API with the key server-side; metered per user per hour (`place_search_per_hour`) |
| `kundali` | POST `{action: status \| report \| request, …}` | bearer + entitled (trial OK) | casts the chart at request time; `report` answers **409 `not_ready` until `unlock_at`** — the lock lives in `kundaliPayload`, the only serializer |
| `kundali-worker` | POST from `pg_cron` (every 5 min) | **shared secret** (`x-cron-secret`) | answers 202, then writes due readings with Gemini after the response; retries with backoff |
| `notification-dispatch` | POST from `pg_cron` (every 5 min); `{action: dry_run \| send_test}` for an operator | **shared secret** (`x-cron-secret`) | finds each enabled campaign's candidates, enqueues, sends through FCM HTTP v1. Nothing is sent while `notifications_enabled` is false |
| `cancellation-feedback` | POST `{reason, comment?, source?, notification_id?}` | bearer, **no entitlement check** | why a mandate was cancelled; one answer per subscription |

## Subfolders

- `_shared/` — everything more than one function needs: credentials, the billing state machine,
  the model prompts, the astronomy. Not deployed on its own.
- `tests/` — `deno test`, 368 tests over the pure logic.
- One folder per function in the table above.

## Notes

- **The user id never comes from the request body.** Every authed function resolves the caller
  from the bearer token via `userIdForBearer`, so no request can name an account but its own.
- `cashfree-webhook` and the cron-driven functions (`subscription-reconcile`, `kundali-worker`,
  `notification-dispatch`) cannot use a bearer token — Cashfree cannot send an `apikey` header, and
  pg_cron has no session. Hence HMAC and the shared `reconcile_secret` respectively.
- Adding a function means adding it to `config.toml` too, or it deploys with JWT verification on
  and rejects the anon key the app calls with.
- Gemini, Fast2SMS and Cashfree are reached **only** from here. The client sends no amount and
  no plan id — everything billable is resolved server-side from `app_config`.
- Pushes are sent by `_shared/notify.ts` with the service-account JSON in the private
  `fcm_service_account_key` row. The two billing campaigns (`mid_cancel`, `billing_issue`) are
  raised inline from `subscription_sync.ts` the moment Cashfree reports them; the rest by
  `notification-dispatch`. Every campaign ships switched off — see `MIXPANEL_TRACKING_PLAN.md` §9.2.
- **Deploy order for the kundali and notification work:** both `20260917…` migrations first —
  `entitlement.ts` selects columns they add, so a function deployed before them fails every user
  lookup.
- See [../README.md](../README.md) for the security model, setup and the money table.
