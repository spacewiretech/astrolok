# Astrolok backend

Supabase Postgres + Edge Functions. Fast2SMS issues the OTP, Cashfree runs a UPI Autopay
mandate, and the functions hold every credential so none of them ship inside the app.

## Security model

Supabase Auth is **off** (`config.toml` → `[auth] enabled = false`). There is no `auth.uid()`,
so RLS cannot be written against a Supabase session. Instead:

- `verify-otp` mints a 256-bit opaque token, stores only its SHA-256 hash in `user_sessions`,
  and returns the raw token once. The app keeps it in the Keychain/Keystore.
- Every authed function resolves the caller from that bearer token. **The user id never comes
  from the request body**, so no request can name an account other than its own.
- Every table holding user data has **RLS enabled with zero policies** — the anon key that
  ships inside the app can read and write nothing. Only the functions, on `service_role`,
  touch these rows.
- The single exception is `app_config`, readable by anon **only where `is_public`**. A CHECK
  constraint refuses to mark a secret-looking key public, because the anon key is published.

## Setup

1. Create the project, then `supabase link --project-ref <ref>`.
2. In `migrations/0003_reconcile.sql`, replace `<PROJECT_REF>` with the project ref.
3. `supabase db push`
4. `supabase functions deploy`
5. Fill in the private `app_config` rows from the dashboard (all seeded empty):
   `fast2sms_api_key`, `fast2sms_otp_id`, `cashfree_app_id`, `cashfree_secret_key`,
   `cashfree_plan_id`, `gemini_api_key`.
6. Point the Cashfree webhook at `https://<ref>.supabase.co/functions/v1/cashfree-webhook`.
7. Flip `cashfree_env` to `production` only once a sandbox mandate has been tested end to end.
   It ships as `sandbox` so a half-configured project cannot take real money.

Without a Fast2SMS template you can set `allow_dev_otp = true` (and leave `fast2sms_otp_id`
empty) to accept `000000` and send no SMS. Never leave that on once a template exists.

## Money

The client sends **no amount and no plan id** — only its session token. Everything billable is
resolved server-side:

| Config key | Value | Public |
|---|---|---|
| `cashfree_trial_days` | `1` | yes — the paywall must state it, and one row cannot drift |
| `cashfree_trial_amount` | `1` | no |
| `cashfree_recurring_amount` | `249` | no |
| `entitlement_grace_hours` | `2` | no |
| `trial_price_label` / `plan_price_label` | `₹1` / `₹249` | yes — display copy only |

`entitlement_grace_hours` is 2, not the 12 a longer trial can afford: on a 24-hour trial a
12-hour grace hands out another 50% free.

**Entitlement is derived, never stored.** `_shared/entitlement.ts` computes it from
`payment_type` plus `trial_ends_at` / `current_period_end`, so a stalled webhook expires an
account by the clock instead of leaving it entitled forever, and a renewal is just a date
moving forward.

**Known risk:** Cashfree requires `subscription_first_charge_time` to sit at least ~24h out for
a UPI Autopay mandate, and `trial_days = 1` lands exactly there. Test a real sandbox mandate
before launch; if Cashfree refuses the schedule, raise `cashfree_trial_days` to 2.

## Idempotency

Money moves through three independent guards, because webhooks are redelivered:

- `payment_events.dedupe_key` — unique on `sha256(event_type | timestamp | raw body)`, so a
  redelivered webhook is a no-op rather than a second state transition. Per *delivery attempt*
  on purpose: Cashfree stamps a fresh `x-webhook-timestamp` each time, and a retry that follows
  a failed attempt is meant to run the money path again.
- `subscription_payments.cf_payment_id` — unique, so a charge cannot be counted twice.
- `subscriptions_one_active_per_user` — a partial unique index, so a retry can never leave two
  mandates debiting in parallel.

`payment_events.notification_key` is the analytics-scoped sibling of `dedupe_key`, and the
distinction matters: it identifies the *notification* (`pay:{id}:{status}`, or a body hash where
nothing nameable is in the payload) rather than the delivery, so it is stable across retries.
`Webhook Received` is reported once per `(notification_key, outcome)` — a webhook stuck in a
retry loop is counted once, not once a minute, while one that fails and then succeeds still
reports both. `Webhook Retrying` fires once when a notification passes ten deliveries, so that
silence is never mistaken for health.

The webhook verifies `base64(HMAC-SHA256(timestamp + raw body, cashfree_secret_key))` in
constant time over the **raw bytes**, then re-fetches the subscription from Cashfree and writes
absolute state rather than trusting the payload.

`subscription-reconcile` runs hourly on pg_cron as the safety net for a dropped webhook.

## Palm readings

`palm-reading` takes a base64 photograph and returns an eight-line reading. **The photograph is
never stored.** It goes to Gemini and is dropped when the request ends — there is no column and
no bucket that could hold one — so the only copy that outlives the request is on the user's own
device. `palm_readings` keeps the text, plus `model`/`latency_ms`/`image_bytes` for tuning.

The key lives in `gemini_api_key` (private). `GEMINI_AI_KEY` is also read, for a row created
under that name before the convention settled. Note that the secret-guard CHECK in `0001` was
case-**sensitive**, so an uppercase `..._KEY` could be marked public and published to every
install through the anon key; `0004_palm` forces those rows private and makes the constraint
case-insensitive.

Three guards, because this endpoint spends money on every call:

- Entitlement is re-checked here. `EntitlementGate` in the app is a convenience, not a boundary.
- `palm_readings_per_day` (default 10) caps a single account. The row is inserted as `pending`
  **before** the model is called, so a request that is paid for is counted even when it fails.
  `failed` rows are excluded — a user should not lose a reading because the model was down.
- The image is capped at ~1.5 MB of base64 and rejected locally above that.

Model ids live in config so a retirement is a dashboard edit, not a redeploy — which has
already happened once: `gemini-2.5-flash` was retired mid-build. **Not every model accepts this
request shape** (inline image + `responseSchema` + `thinkingBudget: 0`); `gemini-3.6-flash` and
every `*-flash-lite` answer 400. Verify end to end before changing `gemini_model` or
`gemini_model_fallback`. Current pair: `gemini-3.8-flash` / `gemini-3.5-flash`, ~9-11s.

## The chat's two dashboard levers

`chat_prompt_version` picks which Astro prompt is live — `v2` is current, `v1` is the text that
shipped before answers were reworked to commit to a timing question and name the effort involved.
Both live in `_shared/astro_chat.ts` and the duplication between them is deliberate: a rollback is
only worth having if it is a snapshot nobody has been improving on the side. Flipping the row
reverts the model within the 60-second config TTL, no redeploy. Anything unrecognised reads as
`v2`, so a blank or misspelt cell cannot strand everyone on the old prompt.

`chat_languages` is a comma-separated list — `Hinglish,English,Hindi` — and `chat_language_default`
names which of them a user who has never chosen gets. Both public: the Profile picker draws from
them. Adding a language is one edit to one cell, because `_shared/chat_language.ts` has a written
instruction for the three known ones and a generic template for anything else. Blanking
`chat_languages` hides the picker and is the off switch for the whole feature.

An edit reaches the **prompt** within 60 seconds (`loadConfig`'s TTL) and the **app** the next
time the user lands on Home, which re-reads config when its cache is over a minute old. Anything
faster on the client would mean a request per back-navigation; the two windows match so the
picker and the prompt cannot disagree for long about which languages exist.

The stored choice is `users.language`, nullable, and null is meaningful — it means "follow the
default", so changing the default moves everyone who never expressed a preference and nobody who
did. A value retired from the list falls back to the default at read time rather than being
honoured. `update-profile` validates against the list, not against a hardcoded enum, or adding a
language would need a deploy after all.

**A user's pick never touches `app_config`.** It is written to their own `users.language` row by
`update-profile`, and `chat_language_default` is only ever *read*. Nothing in this repo writes to
`app_config` at all — both accesses, here and in the app, are `select` — and the table's RLS
carries a single `SELECT` policy, so the anon key that ships inside the app could not write to it
even if some future code tried. Only the dashboard changes a default, and it governs exactly the
accounts that have never chosen.

One rule is scoped rather than shared: `PANDIT_VOICE`'s "Roman letters only, never Devanagari"
protects the PDF's Latin-only font subset and a TTS that reads Devanagari as silence. The chat has
neither, so it passes its own `CHAT_VOICE` and Hindi is written in Devanagari. Palm and face keep
the rule, and a test asserts they still do.

The prompt's boundaries are written as rules about how to write, not as a disclaimer to append:
no health, diagnosis or lifespan claims, no guarantees, no dates, and no deterministic verbs.
The Mercury line ships as communication and vitality, never as a "health line" — that label
steers the model straight at the claims the prompt forbids. Rejection is deliberately narrow:
an early version bounced real palms because a second hand was in frame, and a false "no palm"
sends a paying user back to retake a photo that was fine.

## Tests

```
deno test functions/tests/                   # 58 tests
deno check functions/*/index.ts functions/_shared/*.ts
```

Covers entitlement boundaries, HMAC tamper and replay, payment classification, IST date
arithmetic and month-end clamping, and `normalisePalmReading` — every way a language model can
break the reading contract, since the screen renders whatever comes out of it.

---

## Folder index

*A map of this directory, kept alongside the notes above.*

### Files

- `config.toml` — Supabase CLI project config. Two structurally important settings:
  **`[auth] enabled = false`** (hence no `auth.uid()`, hence RLS with zero policies) and
  **`verify_jwt = false` on all 14 functions** (they are called with the anon key before a
  session exists, so each authenticates for itself). Also `[api] max_rows = 1000`,
  Postgres 17, local ports 54321/54322/54323.

### Subfolders

- `functions/` — the whole backend API: 14 Edge Functions, plus `_shared/` and `tests/`. Its
  README carries the endpoint-by-endpoint table with the auth mechanism for each.
- `functions/_shared/` — credentials, the billing state machine (`subscription_sync.ts`,
  `cashfree.ts`), the model prompts and normalisers, and the non-LLM astronomy in `jyotish.ts`.
- `functions/tests/` — `deno test`, 182 tests over the pure logic.
- `migrations/` — 16 `.sql` files in lexical order. See its README for what each adds and for
  the two manual setup steps that are easy to miss.

### Notes

- Not deployed from here: `.temp/` and `.branches/` are gitignored CLI machine state, local to
  whoever ran `supabase link` or `supabase start`.
- The test counts quoted above (58, and 38 in the root README) predate later additions —
  `deno test functions/tests/` currently runs 182.
