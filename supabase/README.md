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
   `cashfree_plan_id`.
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
  redelivered webhook is a no-op rather than a second state transition.
- `subscription_payments.cf_payment_id` — unique, so a charge cannot be counted twice.
- `subscriptions_one_active_per_user` — a partial unique index, so a retry can never leave two
  mandates debiting in parallel.

The webhook verifies `base64(HMAC-SHA256(timestamp + raw body, cashfree_secret_key))` in
constant time over the **raw bytes**, then re-fetches the subscription from Cashfree and writes
absolute state rather than trusting the payload.

`subscription-reconcile` runs hourly on pg_cron as the safety net for a dropped webhook.

## Tests

```
deno test functions/tests/payments_test.ts   # 38 tests
deno check functions/*/index.ts functions/_shared/*.ts
```

Covers entitlement boundaries, HMAC tamper and replay, payment classification, IST date
arithmetic and month-end clamping.
