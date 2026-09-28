-- What happened to each day's trials, on the marketing sheet.
--
-- Six counts beside the renewals, one per way a paid trial can end without becoming a paying
-- subscriber. The same buckets as the 2026-09-28 trial-outcome report (10,236 trials from 14–25
-- Sep): cancelled in the trial 62.1%, debit failed then cancelled 4.9%, debit failed with the
-- mandate still live 17.5%, paused in the UPI app 3.3%, debit stuck pending 1.3%, other 0.6%.
--
-- ---------------------------------------------------------------- what a row means
--
-- These are a *cohort*, not events: the row for 2026-09-20 says where the trials that started on
-- 2026-09-20 have got to, whenever the cancel or the failure actually happened. That is the only
-- reading under which the buckets are exclusive — one account, one outcome — and add up against
-- `trials` on the same row. `renewals` beside them is still counted by debit day, as before.
--
-- A cohort keeps moving after the day is over. A trial runs a day, the first debit follows, and a
-- mandate whose debit failed is retried about 30 days later — so a morning post of yesterday
-- alone would write a row that is almost all "no outcome yet" and never correct it. Hence the
-- second half of this migration: each morning re-posts the last 30 days, and the sheet upserts
-- them in place.
--
-- The buckets need not sum to `trials`. Two groups are in none of them on purpose: the trials that
-- converted (the renewal columns report paying subscribers already), and the ones with no outcome
-- yet — mandate `ACTIVE` and no debit attempted. The second is nearly everyone on the latest day or
-- two, and should shrink to nothing after that. It does not quite: 39 of the 14–25 Sep trials were
-- still there on 09-28, because the hourly reconcile is behind on `ACTIVE` mandates. The report put
-- those 39 under "Other"; here they wait with the undecided, since on a daily sheet "Other" would
-- otherwise be the whole of yesterday.
--
-- ---------------------------------------------------------------- the buckets
--
-- First match wins, in this order:
--   paid          any successful RECURRING charge, or a full-price AUTH, on any of the account's
--                 mandates. Not a column. Checked first so a re-checkout that ended in a payment
--                 counts as a payment, not as the cancel that preceded it.
--   cancelled     any of the account's mandates CANCELLED or CUSTOMER_CANCELLED, and the trial
--                 mandate's debit never *really* failed.
--   failed + cancelled   the same, but the debit did really fail first. Includes a re-checkout
--                 (`CANCELLED`, "replaced by a new mandate") that never paid.
--   failed, live  the trial mandate is still ACTIVE and its debit really failed. Overwhelmingly
--                 insufficient funds; the next attempt is ~30 days out, so this is the group
--                 worth chasing.
--   paused        the mandate is CUSTOMER_PAUSED (or any *_PAUSED).
--   pending       a debit INITIALIZED / PENDING / BANK_APPROVAL_PENDING that never resolved.
--   no outcome    ACTIVE and no debit row at all. Not a column.
--   other         anything left: LINK_EXPIRED, and the odd ACTIVE mandate with only a
--                 not-real failure on it.
--
-- "Really failed" excludes the rows Cashfree writes for a debit that was never going to happen
-- because the mandate was already gone — `failure_reason` matching revoked / "notification
-- couldn't be sent" / "not active" / paused. Those are how a cancel looks from the debit's side,
-- and counting them as failures moves most of "cancelled in the trial" into "failed, then
-- cancelled".
--
-- ---------------------------------------------------------------- order of deployment
--
-- `post_daily_metrics` now sends `{"secret", "rows": [...]}`, many days in one request. The Apps
-- Script on the sheet has to understand that before this is applied, or the 09:00 post is refused
-- with "no report_date" and nothing is written. Paste and deploy the new
-- supabase/scripts/daily_metrics_sheet.gs first (it accepts the old single-day body too), then
-- apply this.

-- ---------------------------------------------------------------- the counts

-- The return type grows, so drop and recreate: `create or replace` cannot change it.
-- `post_daily_metrics` is replaced below and does not depend on the column list.
drop function if exists public.daily_marketing_metrics(date);

create function public.daily_marketing_metrics(p_day date)
returns table (
  report_date           date,
  signups               bigint,
  trials                bigint,
  renewals              bigint,
  renewals_499          bigint,
  renewals_299          bigint,
  cancelled_in_trial    bigint,
  failed_then_cancelled bigint,
  failed_mandate_active bigint,
  paused_in_upi         bigint,
  debit_pending         bigint,
  outcome_other         bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with bounds as (
    select  p_day::timestamp      at time zone 'Asia/Kolkata' as from_ts,
           (p_day + 1)::timestamp at time zone 'Asia/Kolkata' as to_ts
  ),

  -- The store reviewers' account signs in and subscribes like anyone else, so without this it
  -- lands in the marketing numbers as a real user. `nullif` is what makes an unset or cleared
  -- `review_mobile` exclude nobody rather than everybody.
  review_users as (
    select u.user_id
      from public.app_config c
      join public.users u
        on u.mobile_no = nullif(btrim(c.value), '')
     where c.key = 'review_mobile'
  ),

  -- The ₹3, with the same fallback the functions use when the row is blank or missing.
  trial_fee as (
    select coalesce(
      (select nullif(btrim(value), '')::numeric
         from public.app_config where key = 'cashfree_trial_amount'),
      3) as amount
  ),

  -- The day's trials: one row per account whose ₹3 AUTH charge succeeded in the day, with the
  -- mandate that charge opened. A charge whose user was deleted stands on its own payment id
  -- rather than vanishing. See 20260928000001 for why the charge and not `trial_started_at`.
  trials as (
    select distinct on (coalesce(p.user_id::text, p.cf_payment_id))
           p.user_id, p.subscription_pk
      from public.subscription_payments p, bounds b, trial_fee f
     where p.kind   = 'AUTH'
       and p.status = 'SUCCESS'
       and p.amount <= f.amount
       and coalesce(p.payment_time, p.created_at) >= b.from_ts
       and coalesce(p.payment_time, p.created_at) <  b.to_ts
       and (p.user_id is null or p.user_id not in (select user_id from review_users))
     order by coalesce(p.user_id::text, p.cf_payment_id), coalesce(p.payment_time, p.created_at)
  ),

  -- Each fact below is gathered once for the whole cohort and joined back, never looked up per
  -- trial: a correlated subquery per row is what timed out when this was first measured.

  -- Paid full price, on any mandate — a trial that failed and was re-checked-out under a new
  -- mandate still converted.
  paid as (
    select p.user_id
      from public.subscription_payments p, trial_fee f
     where p.user_id in (select user_id from trials)
       and p.status = 'SUCCESS'
       and (p.kind = 'RECURRING' or (p.kind = 'AUTH' and p.amount > f.amount))
     group by 1
  ),

  -- Cancelled any mandate, by the user in their UPI app or by us on their behalf.
  cancelled as (
    select s.user_id
      from public.subscriptions s
     where s.user_id in (select user_id from trials)
       and s.status in ('CANCELLED', 'CUSTOMER_CANCELLED')
     group by 1
  ),

  -- The debits against the mandate the trial opened.
  debits as (
    select p.subscription_pk,
           bool_or(p.status = 'FAILED'
                   and coalesce(p.failure_reason, '') !~* 'revoked|notification couldn|not active|paused')
             as really_failed,
           bool_or(p.status in ('INITIALIZED', 'PENDING', 'BANK_APPROVAL_PENDING')) as in_flight
      from public.subscription_payments p
     where p.subscription_pk in (select subscription_pk from trials)
       and p.kind = 'RECURRING'
     group by 1
  ),

  outcomes as (
    select case
             when pd.user_id is not null                          then 'paid'
             when c.user_id is not null and not coalesce(d.really_failed, false)
                                                                  then 'cancelled_in_trial'
             when c.user_id is not null                           then 'failed_then_cancelled'
             when s.status = 'ACTIVE' and coalesce(d.really_failed, false)
                                                                  then 'failed_mandate_active'
             when s.status like '%PAUSED'                         then 'paused_in_upi'
             when coalesce(d.in_flight, false)                    then 'debit_pending'
             when s.status = 'ACTIVE' and d.subscription_pk is null then 'no_outcome_yet'
             else                                                      'other'
           end as outcome
      from trials t
      left join public.subscriptions s on s.id = t.subscription_pk
      left join paid pd                on pd.user_id = t.user_id
      left join cancelled c            on c.user_id = t.user_id
      left join debits d               on d.subscription_pk = t.subscription_pk
  ),

  -- Every successful recurring debit in the day, with the plan it belongs to. Gathered once and
  -- counted three ways below, rather than scanning `subscription_payments` three times.
  -- `cross join bounds` rather than a comma: a comma binds looser than `left join`, so with
  -- `from payments p, bounds b left join subscriptions s on s.id = p.subscription_pk` the join
  -- attaches to `bounds` alone and `p` is not in scope in its own ON clause.
  renewals as (
    select s.plan_variant
      from public.subscription_payments p
      cross join bounds b
      left join public.subscriptions s on s.id = p.subscription_pk
     where p.kind   = 'RECURRING'
       and p.status = 'SUCCESS'
       and coalesce(p.payment_time, p.created_at) >= b.from_ts
       and coalesce(p.payment_time, p.created_at) <  b.to_ts
       and (p.user_id is null or p.user_id not in (select user_id from review_users))
  )

  select
    p_day,

    -- `users` is upserted by verify-otp, not inserted, so a returning user logging in again does
    -- not mint a second row. `creation_time` is therefore a true first-ever-signup timestamp.
    (select count(*)
       from public.users u, bounds b
      where u.creation_time >= b.from_ts
        and u.creation_time <  b.to_ts
        and u.user_id not in (select user_id from review_users)),

    (select count(*) from trials),

    -- Every successful recurring debit, M0 onward: the first full-price charge after the trial
    -- counts the same as the sixth month.
    (select count(*) from renewals),
    (select count(*) from renewals where plan_variant = 'plan_499'),
    (select count(*) from renewals where plan_variant = 'plan_299'),

    (select count(*) from outcomes where outcome = 'cancelled_in_trial'),
    (select count(*) from outcomes where outcome = 'failed_then_cancelled'),
    (select count(*) from outcomes where outcome = 'failed_mandate_active'),
    (select count(*) from outcomes where outcome = 'paused_in_upi'),
    (select count(*) from outcomes where outcome = 'debit_pending'),
    (select count(*) from outcomes where outcome = 'other');
$$;

revoke all on function public.daily_marketing_metrics(date) from public, anon, authenticated;

comment on function public.daily_marketing_metrics is
  'For one Asia/Kolkata calendar day: signups, trials (accounts whose ₹3 AUTH charge succeeded), '
  'successful recurring renewals (total and by plan_variant), and where that day''s trials have '
  'got to — cancelled in the trial, debit failed then cancelled, debit failed with the mandate '
  'still active, paused, debit pending, other.';

-- ---------------------------------------------------------------- the push

-- One request for a run of days, rather than one per day. The Apps Script takes a lock and runs
-- one execution at a time, so posting 30 days as 30 requests queues them behind each other past
-- pg_net's timeout — the reason the first backfill wrote nothing. A single body is a single
-- execution holding the lock once.
--
--   post_daily_metrics()                          the last 30 days, ending yesterday IST — the cron
--   post_daily_metrics('2026-09-20')              that one day
--   post_daily_metrics('2026-09-03','2026-09-27') an inclusive range — a full reload
--
-- Returns the pg_net request id. The POST is queued, not awaited; what the sheet said comes back
-- later, and is proof of a write only when it is `{"ok":true,...}`:
--   select id, status_code, content from net._http_response order by id desc limit 5;
drop function if exists public.post_daily_metrics(date);

create function public.post_daily_metrics(p_from date default null, p_to date default null)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  -- How far back the morning post reaches. A month covers the ~30-day retry after a failed first
  -- debit, which is the slowest way a trial's outcome still changes; older rows are left as they
  -- last stood. Re-posting also carries renewals that confirmed after their day was first posted.
  c_refresh_days constant int := 30;

  v_yesterday date := (now() at time zone 'Asia/Kolkata')::date - 1;
  v_first  date;
  v_last   date;
  v_url    text;
  v_secret text;
  v_rows   jsonb;
  v_req    bigint;
begin
  -- Yesterday *in IST*, which is why this is not `current_date - 1`: the job fires at 03:30 UTC,
  -- where `current_date` is already today in UTC but still yesterday for the people reading it.
  if p_from is null then
    v_first := v_yesterday - (c_refresh_days - 1);
    v_last  := v_yesterday;
  else
    v_first := p_from;
    v_last  := coalesce(p_to, p_from);
  end if;

  if v_last < v_first then
    raise exception 'post_daily_metrics: % is after %', v_first, v_last;
  end if;

  select nullif(btrim(value), '') into v_url
    from public.app_config where key = 'metrics_sheet_url';
  select coalesce(value, '') into v_secret
    from public.app_config where key = 'metrics_sheet_secret';

  -- Seeded blank, like every other credential row. An unconfigured project posts nowhere rather
  -- than erroring hourly into the cron log.
  if v_url is null then
    raise notice 'metrics_sheet_url is empty; no metrics posted for % to %', v_first, v_last;
    return null;
  end if;

  select jsonb_agg(to_jsonb(m) order by m.report_date) into v_rows
    from generate_series(v_first, v_last, interval '1 day') d
    cross join lateral public.daily_marketing_metrics(d::date) m;

  -- 60s rather than 20: a month of rows is one Apps Script execution writing a few hundred cells.
  -- A timeout here loses only the reply, not the write — the script carries on regardless.
  select net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body    := jsonb_build_object('secret', v_secret, 'rows', v_rows),
    timeout_milliseconds := 60000
  ) into v_req;

  return v_req;
end;
$$;

revoke all on function public.post_daily_metrics(date, date) from public, anon, authenticated;

comment on function public.post_daily_metrics is
  'Posts marketing counts to metrics_sheet_url in one request. No arguments: the last 30 days '
  'ending yesterday IST (the 09:00 cron). One date: that day. Two: the inclusive range. Safe to '
  're-run: the sheet upserts on the date.';

-- The `daily-marketing-metrics` cron job runs `select public.post_daily_metrics();`, which resolves
-- to the new function through its defaults, so the schedule is left as it is.
