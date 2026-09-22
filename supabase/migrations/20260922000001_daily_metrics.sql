-- The daily marketing numbers, pushed to a Google Sheet.
--
-- Three counts for yesterday — signups, trials started, subscriptions renewed — posted once a
-- morning to an Apps Script Web App bound to the marketing sheet, which writes the row.
--
-- Pushed rather than pulled, because the alternative is worse. A script living in the sheet that
-- queried this database directly would need the `service_role` key in its Script Properties, and
-- every editor of that sheet can read those. The anon key is no help: every table counted below
-- has RLS on with zero policies. So the database keeps the credentials and the sheet only
-- receives.
--
-- Done in SQL over pg_cron rather than as an Edge Function on purpose. There is no request to
-- authenticate and no third-party SDK to carry — just three aggregates and one POST — and a new
-- function is a new `config.toml` block to forget, which is the failure that left referrals and
-- attribution dead in production for a week.

-- ---------------------------------------------------------------- config

insert into public.app_config (key, value, is_public, description) values
  ('metrics_sheet_url', '', false,
   'The /exec URL of the Apps Script Web App deployed from the marketing sheet. Empty disables '
   'the daily push entirely — see supabase/scripts/daily_metrics_sheet.gs.'),
  ('metrics_sheet_secret', '', false,
   'Shared secret sent in the POST body and compared against the METRICS_SECRET script property '
   'on the sheet side. An Apps Script Web App open to "anyone with the link" is otherwise an '
   'unauthenticated writer into the sheet.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------- the counts

-- A day is a calendar day in Asia/Kolkata, not a UTC day. Everyone reading this sheet is in IST,
-- and a UTC day would silently move the 5.5 hours before midnight into the wrong row — so
-- "signups on the 21st" would disagree with every other number anyone quotes.
create or replace function public.daily_marketing_metrics(p_day date)
returns table (
  report_date date,
  signups     bigint,
  trials      bigint,
  renewals    bigint
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

    -- `trial_started_at`, not a count of ₹3 AUTH payments. The column is written once and never
    -- overwritten (`user.trial_started_at ?? snapshot.authorizedAt` in subscription_sync.ts), so
    -- a reconcile that re-reads an old mandate cannot report a second trial for the same account,
    -- and a returning subscriber re-authorising at full price is not counted as a new one.
    (select count(*)
       from public.users u, bounds b
      where u.trial_started_at >= b.from_ts
        and u.trial_started_at <  b.to_ts
        and u.user_id not in (select user_id from review_users)),

    -- Every successful recurring debit, M0 onward: the first full-price charge after the trial
    -- counts the same as the sixth month. Deliberately no amount filter — ₹249 legacy mandates,
    -- and ₹299/₹499 once the price split is switched on, are all renewals, and a hardcoded
    -- amount here would quietly drop a whole plan the day pricing changes.
    --
    -- `payment_time` is Cashfree's own timestamp and is what the money actually happened at;
    -- `created_at` only stands in for the rare payload that arrives without one.
    (select count(*)
       from public.subscription_payments p, bounds b
      where p.kind   = 'RECURRING'
        and p.status = 'SUCCESS'
        and coalesce(p.payment_time, p.created_at) >= b.from_ts
        and coalesce(p.payment_time, p.created_at) <  b.to_ts
        and (p.user_id is null or p.user_id not in (select user_id from review_users)));
$$;

revoke all on function public.daily_marketing_metrics(date) from public, anon, authenticated;

comment on function public.daily_marketing_metrics is
  'Signups, trials started and successful recurring renewals for one Asia/Kolkata calendar day.';

-- ---------------------------------------------------------------- the push

-- Returns the pg_net request id. The POST is queued, not awaited, so a successful return means
-- the request was accepted for sending and nothing more — what the sheet said comes back later:
--   select id, status_code, content from net._http_response order by id desc limit 5;
create or replace function public.post_daily_metrics(p_day date default null)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day    date;
  v_url    text;
  v_secret text;
  v_body   jsonb;
  v_req    bigint;
begin
  -- Yesterday *in IST*, which is why this is not `current_date - 1`: the job fires at 03:30 UTC,
  -- where `current_date` is already today in UTC but still yesterday for the people reading it.
  v_day := coalesce(p_day, (now() at time zone 'Asia/Kolkata')::date - 1);

  select nullif(btrim(value), '') into v_url
    from public.app_config where key = 'metrics_sheet_url';
  select coalesce(value, '') into v_secret
    from public.app_config where key = 'metrics_sheet_secret';

  -- Seeded blank, like every other credential row. An unconfigured project posts nowhere rather
  -- than erroring hourly into the cron log.
  if v_url is null then
    raise notice 'metrics_sheet_url is empty; no metrics posted for %', v_day;
    return null;
  end if;

  select to_jsonb(m) into v_body from public.daily_marketing_metrics(v_day) m;

  select net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body    := v_body || jsonb_build_object('secret', v_secret),
    timeout_milliseconds := 20000
  ) into v_req;

  return v_req;
end;
$$;

revoke all on function public.post_daily_metrics(date) from public, anon, authenticated;

comment on function public.post_daily_metrics is
  'Posts one day of marketing counts to metrics_sheet_url. Defaults to yesterday IST. Safe to '
  're-run for any date: the sheet upserts on the date rather than appending.';

-- ---------------------------------------------------------------- schedule

do $$
begin
  if exists (select 1 from cron.job where jobname = 'daily-marketing-metrics') then
    perform cron.unschedule('daily-marketing-metrics');
  end if;
end
$$;

-- 03:30 UTC is 09:00 IST. pg_cron schedules in UTC and there is no per-job timezone, so the
-- offset is baked into the expression; India does not observe DST, so it never drifts.
--
-- Nine in the morning rather than just after midnight because the numbers are still moving at
-- midnight: Cashfree's recurring batches and their webhook retries settle overnight, and a sweep
-- at 00:05 reports a renewal count that the hourly reconcile then quietly revises upward.
select cron.schedule(
  'daily-marketing-metrics',
  '30 3 * * *',
  $job$select public.post_daily_metrics();$job$
);
