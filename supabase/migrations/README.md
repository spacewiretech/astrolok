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
- `20260914000001_push_tokens.sql` — `push_tokens` (FCM token as primary key, `user_id`,
  `session_token_hash`, `platform`), RLS on with zero policies. The foreign key to
  `user_sessions` cascades, so sign-out and session expiry remove a device's token and
  **`purge_expired` needs no change**.
- `20260914000002_trial_reading_limit.sql` — `trial_palm_readings` and `trial_face_readings`
  (both `1`, public), the per-trial reading allowance. No schema change: the count comes from the
  reading tables and `users.trial_started_at`.
- `20260915000001_chat_chart.sql` — `users.chart` (jsonb, nullable): the chart `astro-chat` last
  gave the sage, compared on every turn so a rashi that moved when the birth hour arrived is
  corrected out loud. A snapshot, never a source — the live chart is recomputed from `dob` and
  `birth_time`. Also moves `chat_prompt_version` from `v2` to `v3`; a project on `v1` stays put.
- `20260915000002_chat_feedback.sql` — `chat_feedback`, one row per user (the primary key is what
  makes the rating once per account; `rating` null is a dismissal), RLS on with zero policies,
  and `chat_rating_after_messages` (`5`, private). **Not in `purge_expired`**: one row per user,
  gone with the account.
- `20260915000003_facebook_capi.sql` — `facebook_dataset_id`, `facebook_capi_access_token`,
  `facebook_capi_enabled` (ships **false**), `facebook_graph_api_version`,
  `facebook_capi_test_event_code`. All private. No schema change — these let the server report the
  recurring debit to Meta, which the client provably cannot. **Not the app secret**, which
  `20260908000003` forbids here and which this integration does not use: the modern app-event path
  authenticates against a Dataset, not the app.
- `20260915000004_pricing_plans.sql` — the ₹499 / ₹299 price split. `users.plan_variant` and
  `subscriptions.plan_variant` (`plan_499` / `plan_299`, existing rows backfilled to `plan_499`),
  `plan_assignment_counter` (one row, the running user total) and `assign_plan_variant`, which
  `verify-otp` calls once per new account: odd total → ₹499, even → ₹299. Config
  `cashfree_plan_id_299`, `cashfree_plan_name_299`, `cashfree_recurring_amount_299`,
  `plan_price_label_299`, `cashfree_plan_name` and `pricing_split_enabled` (ships **false**), all
  private. **`users.plan_variant` is nullable on purpose**: `verify-otp` upserts, and a column
  default would be evaluated on every login rather than once.
- `20260916000001_otp_autofill.sql` — `sms_retriever_enabled` (public, ships **false**). Chooses
  how the Android OTP sheet reads the code: false is the one-tap SMS User Consent sheet, which
  works with any SMS; true is the zero-tap SMS Retriever, which only fires for an SMS ending with
  the Play App Signing hash. That text is the Fast2SMS template, so turn this on only after the
  template carries the hash. No schema change.
- `20260916000002_chat_feedback_comment.sql` — `chat_feedback.comment` (text, nullable, at most 500
  characters): the optional written answer submitted with the chat rating. It sits on the same row
  as the score, so there is still one answer per account. No backfill.
- `20260916000004_onboarding_languages.sql` — data only: adds Telugu, Tamil, Kannada and Malayalam
  to `chat_languages` for the onboarding language picker. **Only rewrites a row still holding the
  shipped `Hinglish,English,Hindi`**; a list edited in the dashboard is left alone and needs the
  four added by hand. The default stays Hinglish.
- `20260917000001_kundali.sql` — the kundali: birth-place columns on `users` (`birth_place_id`,
  `birth_lat`, `birth_lng`, `birth_tz`, `birth_coords_at`), the `kundalis` table (one live row per
  account, a queue for the worker, `unlock_at` for the reveal), `replace_live_kundali` (atomic
  re-cast) and `claim_due_kundalis` (SKIP LOCKED), a per-user `api_throttle` with
  `consume_rate_limit`, the `kundali_*` and `place_search_*` config rows (`kundali_enabled` ships
  **false**), the `kundali-worker-5min` cron job, and `purge_expired` extended to drop superseded
  kundalis and **null Google coordinates older than 30 days** (Places caching terms).
- `20260917000002_notifications.sql` — push notifications: `push_tokens.app_build` and
  `notifications_authorized`, `users.push_marketing_opt_out`, the `notifications` log (unique
  `dedupe_key` per real-world occurrence), `cancellation_feedback`, the claim functions,
  `notification_candidates` (one plpgsql function, a branch per scheduled campaign), the
  `notif_*` config rows (**every switch false**), the `notification-dispatch-5min` cron job, and
  `purge_expired` extended to drop push history after 180 days. **Apply both `20260917…`
  migrations before deploying any function** — `entitlement.ts` selects the new user columns.
- `20260922000001_daily_metrics.sql` — the marketing sheet. `daily_marketing_metrics(date)`
  (signups, trials started, successful `RECURRING` charges for one **Asia/Kolkata** day, with the
  `review_mobile` account excluded), `post_daily_metrics(date default null)` which POSTs them
  through pg_net, the `metrics_sheet_url` / `metrics_sheet_secret` config rows (both private,
  seeded blank) and the `daily-marketing-metrics` cron job at 03:30 UTC / 09:00 IST. No schema
  change and no Edge Function: the receiving half is an Apps Script Web App on the sheet, kept at
  [../scripts/daily_metrics_sheet.gs](../scripts/daily_metrics_sheet.gs). **Trials count
  `users.trial_started_at`, not ₹3 AUTH payments** — that column is written once and never
  overwritten, so a reconcile re-reading an old mandate cannot report the same trial twice.

- `20260923000001_daily_drip.sql` — the daily drip. Rewrites `notification_candidates` with six
  more branches (one per slot), adds `drip_setting`, `drip_slot_at` and `drip_variant`, four
  indexes, and nineteen `notif_drip_*` / `notif_daily_*_enabled` config rows. **All seeded off**, and
  the SQL itself checks `notif_drip_enabled`, so applying it changes nothing until someone turns a
  slot on. Six pushes a day to `payment_type <> 'active'`, two to `active`; see
  [NOTIFICATIONS.md](../../NOTIFICATIONS.md#the-daily-drip).
- `20260924000001_chat_prompt_v4.sql` — data only: moves `chat_prompt_version` from `v3` to `v4`
  (a "when" answered with a window computed from the dasha, the birth hour asked for once, plain
  Hindi, a shorter body) and rewrites the row's description. A project rolled back to v2 or v1
  stays put. **Safe in either order against the functions deploy** — code from before v4 reads
  `v4` as unrecognised, which there means v3.

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
- `referrals.referred_user_id` is the **primary key**, not just a column. Every duplicate-claim
  case — a retried call, an app killed mid-attribution, two links clicked, a reinstall, two
  concurrent requests — collapses into "the second insert conflicts", which is what lets the
  claim code be idempotent by reading the winner back rather than by guarding the race.
- `user_attribution.first_*` is written by an insert that does nothing on conflict, so first
  touch is physically incapable of being overwritten. See `20260911000001_referrals.sql`.
- Steps 2 and 5 of the setup in [../README.md](../README.md) are manual and easy to miss.
- `20260922000001_daily_metrics.sql` → **superseded in part by `20260922000002`**; see below.
- `20260922000002_trial_definition.sql` — redefines the `trials` count in
  `daily_marketing_metrics`. `trial_started_at` is set from Cashfree's mandate *authorisation*,
  not from a payment, and a UPI autopay approval very often never debits the ₹3 — 18,492 accounts
  had the column set against 6,322 that had ever paid over ₹2, so the reported figure was ~2.8x
  the truth. The day still comes from `trial_started_at` (written once, so it cannot double-count)
  but now requires `total_paid_amount > 2`. Cross-checked against `AUTH`/`SUCCESS` rows in
  `subscription_payments`, which agree within ~1%. **No schema change** — function body only.
- `20260922000003_renewals_by_plan.sql` — adds `renewals_499` / `renewals_299` to
  `daily_marketing_metrics`, split on `subscriptions.plan_variant` (`plan_499` / `plan_299`) rather
  than on `plan_id` — ₹499 already spans three plan ids including the legacy account's
  `id_circle360_499`, so keying on ids would silently report zero after any plan is recreated.
  `renewals` stays as the total; the halves need not sum to it, since a payment with no
  `subscription_pk` counts in the total and neither half. **Drops and recreates** the function
  rather than `create or replace`, which cannot change a return type.
