-- Retrying a debit that failed for insufficient funds.
--
-- Cashfree makes one attempt per billing cycle on our UPI mandates and never retries on its own:
-- every charge webhook since 2026-09-14 carries `retry_attempts: 0`. A user whose ₹499/₹299 bounced
-- for want of balance kept a live mandate, lost access, and waited a month for the next scheduled
-- debit. On 2026-09-28 that was 2,449 live mandates.
--
-- The schedule, counted from the day the charge failed (IST):
--   attempt 1  failure day + 2   (48 h)
--   attempt 2  failure day + 4   (~92 h)
--   attempt 3  the next 5th after attempt 2, skipped when it would land on or after the mandate's
--              regular monthly charge — that charge is the next attempt anyway, and Cashfree allows
--              3 retries per billing cycle.
-- Only the date matters: Cashfree's manage-payment RETRY ignores the time, and a UPI debit needs a
-- pre-debit notice 25 h ahead, which Cashfree sends itself once the retry is requested.
--
-- `payment-retry` (hourly, below) does all of it. Nothing on the webhook path changed: a retried
-- charge that succeeds is recorded, credited and reported by the same code as any other debit.

-- ---------------------------------------------------------------- ledger: when did a charge last change

-- A retry that reuses the failed charge's `cf_payment_id` lands as an *update* to the same ledger
-- row, and nothing on the row said when that happened. `payment-retry` needs it to tell a retry's
-- result from the failure it was retrying. Existing rows get the migration time, which is earlier
-- than any retry can be requested.
alter table public.subscription_payments
  add column if not exists updated_at timestamptz not null default now();

drop trigger if exists subscription_payments_touch_updated_at on public.subscription_payments;
create trigger subscription_payments_touch_updated_at
  before update on public.subscription_payments
  for each row execute function public.touch_updated_at();

-- Nothing indexed the ledger by mandate, so every per-subscription lookup scanned the table.
create index if not exists subscription_payments_subscription_idx
  on public.subscription_payments (subscription_pk, created_at desc);

-- ---------------------------------------------------------------- retries

-- One row per retry attempt of one failed charge. The chain for a charge is its rows in attempt
-- order; each is written only once the previous one has failed, so there is never more than one
-- open attempt per charge.
create table if not exists public.payment_retries (
  id                  uuid primary key default gen_random_uuid(),
  subscription_pk     uuid not null references public.subscriptions(id) on delete cascade,
  user_id             uuid not null,
  subscription_id     text not null,
  plan_id             text,

  -- The charge that failed first. Every attempt in the chain carries it, so it is the chain's key.
  cf_payment_id       text not null,
  -- Cashfree's own payment id for the charge being retried: the path parameter of the manage call.
  payment_id          text not null,
  amount              numeric(10,2),

  attempt             smallint not null check (attempt between 1 and 3),
  -- The IST day the schedule counts from: the failure day, or the backlog start for charges that
  -- failed before retries existed.
  base_date           date not null,
  backlog             boolean not null default false,
  -- The IST date sent to Cashfree. Null only on a skipped attempt.
  scheduled_for       date,
  -- The mandate's regular next debit, read from Cashfree before attempt 1 changed anything.
  -- Attempt 3 is skipped when it would not come before it.
  regular_next_date   date,

  -- pending → sending → requested → succeeded | failed | ended
  --                   ↘ rejected (Cashfree refused the retry)
  -- skipped: never sent. ended: the mandate stopped being ACTIVE before a result arrived.
  status              text not null default 'pending'
                        check (status in ('pending', 'sending', 'requested', 'succeeded', 'failed',
                                          'rejected', 'ended', 'skipped')),
  send_attempts       smallint not null default 0,
  claimed_at          timestamptz,
  requested_at        timestamptz,
  resolved_at         timestamptz,

  -- The payment Cashfree says the retry is, from its response. Usually the same charge.
  retry_cf_payment_id text,
  result_reason       text,
  response            jsonb,
  error               text,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  unique (cf_payment_id, attempt)
);

create index if not exists payment_retries_open_idx
  on public.payment_retries (status, scheduled_for)
  where status in ('pending', 'sending', 'requested');

create index if not exists payment_retries_retry_payment_idx
  on public.payment_retries (retry_cf_payment_id)
  where retry_cf_payment_id is not null;

alter table public.payment_retries enable row level security;

create trigger payment_retries_touch_updated_at
  before update on public.payment_retries
  for each row execute function public.touch_updated_at();

comment on table public.payment_retries is
  'Retries of debits that failed for insufficient funds. Written only by payment-retry (service_role).';

-- ---------------------------------------------------------------- candidates

-- Failed charges that should start a retry chain.
--
-- Only a mandate's latest recurring charge: an old failed cycle followed by a newer debit is
-- history, not something to collect. Only insufficient funds: a revoked or paused mandate cannot
-- be debited however often it is asked. A charge that is itself the payment of some retry never
-- starts a chain of its own.
--
-- `p_since` separates new failures (schedule from their own failure day) from the backlog that
-- failed before retries existed, which schedules from `p_backlog_base` or is left alone when that
-- is null.
create or replace function public.payment_retry_candidates(
  p_since        timestamptz,
  p_backlog_base date,
  p_limit        integer,
  p_only         text[] default null
)
returns table (
  subscription_pk    uuid,
  user_id            uuid,
  subscription_id    text,
  plan_id            text,
  cf_payment_id      text,
  payment_id         text,
  amount             numeric,
  failed_at          timestamptz,
  base_date          date,
  backlog            boolean,
  next_schedule_date timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with latest as (
    select distinct on (p.subscription_pk) p.*
    from public.subscription_payments p
    where p.kind = 'RECURRING' and p.subscription_pk is not null
    order by p.subscription_pk, p.created_at desc
  )
  select s.id, s.user_id, s.subscription_id, s.plan_id,
         l.cf_payment_id, l.raw->>'payment_id', l.amount, l.created_at,
         case when l.created_at >= p_since
              then (l.created_at at time zone 'Asia/Kolkata')::date
              else p_backlog_base end,
         l.created_at < p_since,
         s.next_schedule_date
  from latest l
  join public.subscriptions s on s.id = l.subscription_pk
  where l.status = 'FAILED'
    and l.failure_reason ~* 'insufficient'
    and s.status = 'ACTIVE'
    and coalesce(l.raw->>'payment_id', '') <> ''
    and (l.created_at >= p_since or p_backlog_base is not null)
    and not exists (
      select 1 from public.payment_retries r
      where r.cf_payment_id = l.cf_payment_id or r.retry_cf_payment_id = l.cf_payment_id
    )
    and (p_only is null or s.subscription_id = any(p_only))
  order by l.created_at
  limit p_limit;
$$;

revoke all on function public.payment_retry_candidates(timestamptz, date, integer, text[])
  from public, anon, authenticated;

-- ---------------------------------------------------------------- claiming

-- Hands pending attempts to one run, so two overlapping runs cannot both send the same retry.
-- An attempt left in `sending` by a run that died is handed out again after ten minutes; the
-- idempotency key on the Cashfree call makes the resend harmless.
create or replace function public.payment_retry_claim(p_limit integer, p_only text[] default null)
returns setof public.payment_retries
language sql
security definer
set search_path = public
as $$
  update public.payment_retries r
     set status = 'sending', claimed_at = now(), send_attempts = r.send_attempts + 1
   where r.id in (
     select id from public.payment_retries
      where (status = 'pending' or (status = 'sending' and claimed_at < now() - interval '10 minutes'))
        and (p_only is null or subscription_id = any(p_only))
      order by created_at
      limit p_limit
      for update skip locked
   )
  returning r.*;
$$;

revoke all on function public.payment_retry_claim(integer, text[])
  from public, anon, authenticated;

-- ---------------------------------------------------------------- outcomes

-- Closes requested attempts whose result has arrived, and returns them so the caller can report
-- each one and plan the next.
--
-- succeeded: any recurring debit on the mandate succeeded after the retry was requested.
-- failed:    the retried charge failed again. Its row must have changed at least 30 minutes after
--            the request (so an echo of the old failure is not read as the answer) and no earlier
--            than 12 hours before the retry day (a debit cannot run before its date; a pre-debit
--            notice can fail the evening before).
-- ended:     the mandate is no longer ACTIVE and no success came.
create or replace function public.payment_retry_resolve()
returns table (
  id              uuid,
  user_id         uuid,
  subscription_pk uuid,
  subscription_id text,
  plan_id         text,
  cf_payment_id   text,
  amount          numeric,
  attempt         smallint,
  base_date       date,
  backlog         boolean,
  scheduled_for   date,
  regular_next_date date,
  status          text,
  result_reason   text,
  next_payment_id text,
  requested_at    timestamptz,
  resolved_at     timestamptz
)
language sql
security definer
set search_path = public
as $$
  with outcome as (
    select r.id,
      exists (
        select 1 from public.subscription_payments p
         where p.subscription_pk = r.subscription_pk and p.kind = 'RECURRING'
           and p.status = 'SUCCESS' and p.updated_at > r.requested_at
      ) as succeeded,
      f.failure_reason,
      f.payment_id as failed_payment_id,
      s.status as sub_status
    from public.payment_retries r
    join public.subscriptions s on s.id = r.subscription_pk
    left join lateral (
      select p.failure_reason, p.raw->>'payment_id' as payment_id
        from public.subscription_payments p
       where p.cf_payment_id = coalesce(r.retry_cf_payment_id, r.cf_payment_id)
         and p.status = 'FAILED'
         and p.updated_at > greatest(
               r.requested_at + interval '30 minutes',
               (r.scheduled_for::timestamp - interval '12 hours') at time zone 'Asia/Kolkata')
       limit 1
    ) f on true
    where r.status = 'requested'
  )
  update public.payment_retries r
     set status = case when o.succeeded then 'succeeded'
                       when o.failure_reason is not null then 'failed'
                       else 'ended' end,
         result_reason = case when o.succeeded then null
                              when o.failure_reason is not null then o.failure_reason
                              else 'mandate ' || o.sub_status end,
         resolved_at = now()
    from outcome o
   where o.id = r.id
     and (o.succeeded or o.failure_reason is not null or o.sub_status <> 'ACTIVE')
  returning r.id, r.user_id, r.subscription_pk, r.subscription_id, r.plan_id, r.cf_payment_id,
            r.amount, r.attempt, r.base_date, r.backlog, r.scheduled_for, r.regular_next_date,
            r.status, r.result_reason, coalesce(o.failed_payment_id, r.payment_id),
            r.requested_at, r.resolved_at;
$$;

revoke all on function public.payment_retry_resolve()
  from public, anon, authenticated;

-- ---------------------------------------------------------------- config

insert into public.app_config (key, value, is_public, description) values
  ('cashfree_retry_enabled', 'false', false,
   'Retry debits that failed for insufficient funds (payment-retry). Off: the hourly run does nothing.'),
  ('cashfree_retry_since', '', false,
   'Failures recorded at or after this instant are new and scheduled from their own failure day. '
   'Set when retries are switched on.'),
  ('cashfree_retry_backlog_base', '', false,
   'IST date the backlog (failures before cashfree_retry_since) is scheduled from, as if it had '
   'failed that day. Blank: the backlog is left alone.'),
  ('cashfree_retry_offsets_days', '2,4', false,
   'Days after the failure day for the first retries, in order.'),
  ('cashfree_retry_day_of_month', '5', false,
   'Day of the month for the last retry, skipped when it would not come before the regular charge.'),
  ('cashfree_retry_min_lead_days', '1', false,
   'A retry is never scheduled sooner than this many days after today (IST).'),
  ('cashfree_retry_batch', '100', false,
   'Most retries one payment-retry run sends to Cashfree.'),
  ('cashfree_retry_api_version', '', false,
   'x-api-version for the manage-payment call. Blank: cashfree_api_version.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------- schedule

do $$
begin
  if exists (select 1 from cron.job where jobname = 'payment-retry-hourly') then
    perform cron.unschedule('payment-retry-hourly');
  end if;
end
$$;

-- Hourly at 37 minutes past, clear of the reconcile at :07. Retries are day-granular, so an hour
-- between a failure arriving and the next retry being requested costs nothing. Authenticated with
-- the reconcile's secret: same caller, same trust.
select cron.schedule(
  'payment-retry-hourly',
  '37 * * * *',
  $job$
  select net.http_post(
    url := 'https://qktgingrvecpetrofimy.supabase.co/functions/v1/payment-retry',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-reconcile-secret', (select value from public.app_config where key = 'reconcile_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $job$
);
