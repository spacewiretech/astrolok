-- Cashfree UPI Autopay: a ₹3 authorisation opens a 1-day trial, then ₹249/month recurs.
--
-- Security model is unchanged from the init migration: every table here is RLS-on with zero
-- policies, so the anon key that ships inside the app cannot read or write any of it. Only the
-- Edge Functions, holding service_role, touch these rows — which is the whole point, because
-- a client that can write `payment_type` is a client that never has to pay.
--
-- Entitlement is deliberately NOT stored as a boolean. It is derived from `payment_type` plus
-- two timestamps, so a stalled webhook expires an account by the clock rather than leaving it
-- entitled forever, and so a successful renewal is just a date moving forward.

-- ---------------------------------------------------------------- users

alter table public.users
  -- Null means "the trial has not started". A brand new row is `trial` with a null date, which
  -- reads as NOT entitled — the clock only starts once Cashfree captures the authorisation.
  add column if not exists trial_ends_at          timestamptz,

  -- Set from the last successful recurring debit. When a renewal fails this simply stops
  -- moving, and the account lapses on its own. No failure branch has to remember to do it.
  add column if not exists current_period_end     timestamptz,

  -- Denormalised pointer to the live mandate, so `me` stays a single-row read on the hot path.
  add column if not exists active_subscription_id text,

  -- Charge history, denormalised for the same reason. The reconcile sweep recomputes these, so
  -- drift repairs itself. The authorisation amount counts toward total_paid_amount but never
  -- toward successful_charge_count: it bought the trial, not a month.
  add column if not exists successful_charge_count integer       not null default 0,
  add column if not exists failed_charge_count     integer       not null default 0,
  add column if not exists total_paid_amount       numeric(12,2) not null default 0,

  add column if not exists trial_started_at        timestamptz,
  add column if not exists subscription_started_at timestamptz,
  add column if not exists first_paid_at           timestamptz,
  add column if not exists next_billing_at         timestamptz,
  add column if not exists cancelled_at            timestamptz,

  add column if not exists last_payment_at         timestamptz,
  add column if not exists last_payment_amount     numeric(10,2),
  add column if not exists last_payment_status     text,

  -- Informational only, and deliberately NOT a new payment_status enum value. isEntitled ends
  -- in `default: return false`, so adding ON_HOLD or PAUSED to that enum would instantly
  -- revoke access from exactly the users we want to warn.
  add column if not exists billing_state           text;

comment on column public.users.trial_ends_at is
  'Null until Cashfree captures the authorisation amount. Set to authorization_time + trial days.';
comment on column public.users.current_period_end is
  'End of the paid period from the last successful recurring debit.';
comment on column public.users.billing_state is
  'on_hold | paused | dunning | disputed. Informational: never consulted for entitlement.';

-- The reconcile sweep looks for trials that should have converted by now.
create index if not exists users_trial_ends_at_idx
  on public.users (trial_ends_at)
  where payment_type = 'trial';

create index if not exists users_billing_state_idx
  on public.users (billing_state)
  where billing_state is not null;

-- ---------------------------------------------------------------- subscriptions

-- One row per mandate attempt, including the ones the user abandoned at the UPI sheet.
-- Keeping the failures is what makes "why did this user never get charged" answerable.
create table if not exists public.subscriptions (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid not null references public.users(user_id) on delete cascade,

  -- Ours, sent to Cashfree as `subscription_id`. Also used as the idempotency key on create.
  subscription_id         text not null unique,
  -- Cashfree's own reference, returned by the create call.
  cf_subscription_id      text unique,

  plan_id                 text not null,

  -- Free text on purpose. A CHECK here would make an unrecognised Cashfree status fail the
  -- webhook closed, which is exactly backwards: an unknown status must still be recorded so it
  -- can be seen, not rejected. Known values: INITIALIZED, PENDING_AUTHORIZATION, ACTIVE,
  -- ON_HOLD, PAUSED, CANCELLED, COMPLETED, plus the local-only ABANDONED and FAILED_TO_CREATE.
  status                  text not null default 'INITIALIZED',

  -- The checkout token handed to the SDK, and when it stops working. Short-lived and already
  -- visible to the client, so there is nothing to protect here — it is stored so a double-tap
  -- or a backgrounded checkout can resume instead of minting a second mandate.
  session_id              text,
  session_expiry          timestamptz,

  authorization_amount    numeric(10,2),
  recurring_amount        numeric(10,2),

  first_charge_time       timestamptz,
  next_schedule_date      timestamptz,
  authorized_at           timestamptz,
  cancelled_at            timestamptz,

  last_payment_at         timestamptz,
  last_payment_status     text,
  failure_reason          text,

  -- The last full snapshot fetched from Cashfree. Cheap insurance: when a payment is disputed
  -- months later, this is the only record of what the gateway actually said at the time.
  raw                     jsonb,

  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

-- The invariant that stops double billing. A user may accumulate any number of abandoned or
-- cancelled mandates, but never two live ones — so a retry can never leave two UPI mandates
-- debiting ₹249 in parallel.
create unique index if not exists subscriptions_one_active_per_user
  on public.subscriptions (user_id)
  where status = 'ACTIVE';

create index if not exists subscriptions_user_created_idx
  on public.subscriptions (user_id, created_at desc);

-- Driven by the hourly reconcile, which looks for schedules that should have fired.
create index if not exists subscriptions_next_schedule_idx
  on public.subscriptions (next_schedule_date)
  where status in ('ACTIVE', 'ON_HOLD', 'PENDING_AUTHORIZATION');

alter table public.subscriptions enable row level security;

create trigger subscriptions_touch_updated_at
  before update on public.subscriptions
  for each row execute function public.touch_updated_at();

comment on table public.subscriptions is
  'One row per Cashfree mandate attempt. Written only by Edge Functions (service_role).';

-- ---------------------------------------------------------------- payments

-- One row per charge attempt, authorisation and recurring alike.
--
-- Both foreign keys are `set null`, not cascade: a charge record answers "was this person
-- actually billed" months later, and it has to outlive the account it belonged to.
create table if not exists public.subscription_payments (
  id              uuid primary key default gen_random_uuid(),
  subscription_pk uuid references public.subscriptions(id) on delete set null,
  user_id         uuid references public.users(user_id) on delete set null,

  -- The real idempotency guard for money. A webhook redelivered three times upserts one row.
  cf_payment_id   text not null unique,

  -- AUTH is the ₹3 that opens the trial; RECURRING is each ₹249 debit.
  kind            text not null default 'RECURRING',

  amount          numeric(10,2),
  currency        text not null default 'INR',
  status          text not null,
  payment_time    timestamptz,
  failure_reason  text,
  raw             jsonb,

  created_at      timestamptz not null default now()
);

create index if not exists subscription_payments_user_idx
  on public.subscription_payments (user_id, payment_time desc);

alter table public.subscription_payments enable row level security;

comment on table public.subscription_payments is
  'Ledger of Cashfree charge attempts, unique on cf_payment_id so redelivery cannot double-count.';

-- ---------------------------------------------------------------- webhook audit

-- Every delivery lands here before anything is acted on, verified or not. A forged call that
-- fails the signature check is still worth having a record of.
create table if not exists public.payment_events (
  id                 bigserial primary key,
  event_type         text,

  -- sha256(event_type | x-webhook-timestamp | raw body). The unique constraint is what makes a
  -- redelivered webhook a no-op rather than a second state transition.
  dedupe_key         text not null unique,

  signature_ok       boolean not null default false,
  header_timestamp   text,
  -- Recorded, never enforced: Cashfree retries may carry the original timestamp, so rejecting
  -- on skew would drop legitimate retries. Replay is already neutralised by dedupe_key and by
  -- the unique cf_payment_id, so a replayed event can only re-assert state we already hold.
  skew_seconds       integer,

  cf_subscription_id text,
  subscription_id    text,
  payload            jsonb,

  received_at        timestamptz not null default now(),
  processed_at       timestamptz,
  process_error      text
);

create index if not exists payment_events_subscription_idx
  on public.payment_events (subscription_id, received_at desc);

create index if not exists payment_events_unprocessed_idx
  on public.payment_events (received_at)
  where processed_at is null;

alter table public.payment_events enable row level security;

comment on table public.payment_events is
  'Raw Cashfree webhook deliveries. Unique dedupe_key makes redelivery idempotent.';

-- ---------------------------------------------------------------- refunds

create table if not exists public.subscription_refunds (
  id             uuid primary key default gen_random_uuid(),

  payment_pk     uuid references public.subscription_payments(id) on delete set null,
  user_id        uuid references public.users(user_id) on delete set null,

  -- The idempotency guard, mirroring subscription_payments.cf_payment_id. A redelivered refund
  -- webhook upserts one row rather than clawing back two months.
  cf_refund_id   text not null unique,
  cf_payment_id  text,

  amount         numeric(10,2),
  currency       text not null default 'INR',
  status         text not null,
  reason         text,
  refund_time    timestamptz,
  raw            jsonb,

  created_at     timestamptz not null default now()
);

create index if not exists subscription_refunds_user_idx
  on public.subscription_refunds (user_id, refund_time desc);
create index if not exists subscription_refunds_payment_idx
  on public.subscription_refunds (cf_payment_id);

alter table public.subscription_refunds enable row level security;

comment on table public.subscription_refunds is
  'Cashfree refunds, unique on cf_refund_id. Written only by Edge Functions (service_role).';

-- ---------------------------------------------------------------- disputes

create table if not exists public.payment_disputes (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid references public.users(user_id) on delete set null,

  cf_dispute_id  text not null unique,
  cf_payment_id  text,

  amount         numeric(10,2),
  currency       text not null default 'INR',

  -- Free text for the same reason subscriptions.status is: an unrecognised dispute state must
  -- be recorded so it can be seen, not rejected.
  status         text not null,
  dispute_type   text,
  reason         text,
  respond_by     timestamptz,
  raw            jsonb,

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists payment_disputes_user_idx
  on public.payment_disputes (user_id, created_at desc);

alter table public.payment_disputes enable row level security;

create trigger payment_disputes_touch_updated_at
  before update on public.payment_disputes
  for each row execute function public.touch_updated_at();

comment on table public.payment_disputes is
  'Chargebacks and disputes. Opening one does not revoke access; losing one does.';

-- ---------------------------------------------------------------- config

-- Every amount, plan id and credential the payment functions need. All private except the two
-- the paywall has to display: the CHECK constraint from 0001 already forces `_key$`/`_secret$`
-- names to is_public = false, and the rest are private simply because a device has no use for
-- them.
--
-- Secrets are seeded empty so they can be pasted into the dashboard without a migration
-- carrying a credential in git history. While cashfree_secret_key is empty every payment
-- function fails closed, which is the right default.
insert into public.app_config (key, value, is_public, description) values
  ('cashfree_app_id', '', false,
   'Cashfree x-client-id. Read only by Edge Functions via service_role.'),
  ('cashfree_secret_key', '', false,
   'Cashfree x-client-secret. Also the HMAC key for webhook signatures. Paste from the '
   'Cashfree dashboard; while empty every payment function fails closed.'),
  ('cashfree_env', 'sandbox', false,
   'sandbox -> sandbox.cashfree.com, production -> api.cashfree.com. One-cell switch. '
   'Starts on sandbox so a half-configured project cannot take real money.'),
  ('cashfree_api_version', '2025-01-01', false,
   'Sent as x-api-version. Payload shapes change between versions.'),
  ('cashfree_plan_id', '', false,
   'Pre-created PERIODIC plan in the Cashfree dashboard, at the recurring amount below.'),
  ('cashfree_trial_amount', '3', false,
   'Authorisation amount in INR, captured and kept. This is the trial fee.'),
  ('cashfree_recurring_amount', '249', false,
   'Recurring amount in INR. Must match the plan configured at Cashfree.'),

  -- Public because the paywall has to state it, and because one row read by both sides cannot
  -- drift: a private copy would eventually promise one day while the server billed after two.
  -- Nothing is exposed by it, and app_config is read-only to the anon key.
  ('cashfree_trial_days', '1', true,
   'Days between authorisation and the first recurring debit. Also the paywall copy.'),

  -- Two hours, not the twelve a longer trial can afford. On a 24-hour trial a 12-hour grace
  -- hands out another 50% free; two is still long enough that a paid-up user mid-settlement is
  -- not thrown out.
  ('entitlement_grace_hours', '2', false,
   'How long access survives past trial_ends_at / current_period_end while a debit settles.'),

  ('reconcile_secret', '', false,
   'Shared secret for subscription-reconcile, sent as x-reconcile-secret by the cron job. '
   'Filled automatically by 0003_reconcile.sql. Empty means the endpoint refuses every call.'),

  ('trial_price_label', '₹3', true,
   'Paywall copy only. Never used to compute a charge.'),
  ('plan_price_label', '₹249', true,
   'Paywall copy only. Shown struck through beside the trial price, and in the mandate '
   'consent line. Never used to compute a charge.'),

  -- Seeded EMPTY on purpose. The paywall hides the rating row entirely while both are blank,
  -- so a launch build cannot claim a score or a subscriber count the app has not earned.
  -- Play treats a misrepresented rating the same way it treats a mislabelled free trial.
  ('rating_label', '', true,
   'e.g. 4.6. Leave empty until the rating is real; the paywall hides the row.'),
  ('subscriber_label', '', true,
   'e.g. 10M+ Subscribers. Leave empty until the number is real.'),

  ('paywall_video_url', '', true,
   'Public MP4 the paywall plays. Empty shows the static poster instead.')
on conflict (key) do nothing;
