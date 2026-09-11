# supabase/migrations

## Purpose

The schema, in order. Applied with `supabase db push`. Filenames are `YYYYMMDDNNNNNN_name.sql`
and run in lexical order.

## Files

**Foundation**
- `20260903000001_init.sql` — tables `users`, `app_config`, `user_sessions`, `otp_throttle`;
  type `payment_status`; functions `consume_otp_quota`, `purge_expired`, `touch_updated_at`;
  touch triggers and indexes. **RLS on everywhere, with exactly one policy** (public
  `app_config` rows).
- `20260903000002_cashfree.sql` — billing tables `subscriptions`, `subscription_payments`,
  `subscription_refunds`, `payment_events`, `payment_disputes`; the trial/billing columns on
  `users`. RLS on, zero policies.
- `20260903000003_reconcile.sql` — enables `pg_cron` + `pg_net` and schedules the reconcile
  sweep. **Contains a `<PROJECT_REF>` placeholder that must be replaced at setup.**

**Features**
- `20260904000001_palm.sql` — `palm_readings` (quota anchor and failure record), index, trigger,
  new `app_config` rows.
- `20260904000002_palm_models.sql` — data only: corrects four retired Gemini model ids.
- `20260904000003_face.sql` — `face_readings`, mirroring `palm_readings`, plus two ceremonial
  columns added to both.
- `20260904000004_chat.sql` — `chat_messages` (ages out) and `user_facts` (persistent memory);
  birth-detail columns on `users`.
- `20260907000001_chat_threads.sql` — `chat_threads` and a `thread_id` on `chat_messages` — one
  thread per account became many.

**Config rows**
- `20260907000002_support_links.sql` — `support_url`, `help_url`, `privacy_url`, `terms_url`.
- `20260908000001_review_account.sql` — `review_mobile`, `review_otp`.
- `20260908000002_mixpanel_token.sql` — drops and re-adds the
  `app_config_secrets_stay_private` CHECK constraint to carve out **one named exception** for
  `mixpanel_token`, then seeds that row blank.
- `20260908000003_facebook.sql` — `trial_price_amount`, `plan_price_amount`, `currency_code`,
  `facebook_app_id`, `facebook_events_enabled`.
- `20260908000004_reconcile_stale_sweep.sql` — `reconcile_stale_hours`, widening the sweep to
  mandates that silently stopped being live.

**Recent**
- `20260909000001_payment_type_none.sql` — `alter type payment_status add value 'none'`.
- `20260909000002_payment_type_none_backfill.sql` — makes `none` the default and backfills
  never-paid rows. **A separate file because Postgres cannot use a new enum value in the same
  transaction that created it.**
- `20260909000003_payment_events_reported.sql` — a reported/notification-key column on
  `payment_events` plus `payment_events_notification_idx`, so Mixpanel emits one event per
  notification rather than per delivery attempt.

## Notes

- **Every table holding user data has RLS enabled with zero policies.** The anon key ships
  inside the app and can therefore read and write nothing; only the functions, on
  `service_role`, touch these rows. The single exception is `app_config`, readable by anon where
  `is_public`.
- `app_config_secrets_stay_private` refuses `is_public = true` for anything matching
  `^fast2sms`, `_key$`, `_secret$`, `_token$`, `password` or `credential`. `mixpanel_token` is
  spelled out as a named exception (it is write-only ingestion, and already ships in the app),
  so the next `_token$` key added still fails closed.
- `purge_expired` is **extended by several migrations** — each feature that adds an ageing table
  updates it. Check the latest definition rather than the first.
- Config rows are seeded **blank** on purpose: a half-configured project must not be able to
  take real money or send real SMS. `cashfree_env` ships as `sandbox` for the same reason.
- Steps 2 and 5 of the setup in [../README.md](../README.md) are manual and easy to miss.
