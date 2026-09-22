-- Split the renewal count by plan.
--
-- Marketing wants to see the ₹499 and ₹299 halves of "Subscription Renewed" separately, now that
-- both are live. `renewals` stays as the total, so the sheet still has one number to quote and the
-- two new columns are checkable against it.
--
-- Split on `subscriptions.plan_variant`, not on `plan_id`. The variant is the business fact —
-- which price the account is on — while the plan id is a Cashfree artefact that has already
-- changed three times for ₹499 alone: `plan_1789372781486_txhn0s`, `plan_1789711113368_lh3xbw`
-- and `id_circle360_499` on the old account, all of them `plan_499`. Keying on plan ids would mean
-- editing this function every time a plan is recreated in the dashboard, and quietly reporting
-- zero until somebody noticed.
--
-- Deliberately no amount filter here either, for the same reason the total has none: the variant
-- says which plan, and the price attached to a plan is free to change without this becoming wrong.
--
-- The two halves need not add up to `renewals`. A payment whose `subscription_pk` is null — the
-- row was deleted, or a webhook arrived that could not be matched to a subscription — counts in
-- the total and in neither half. There are none today; the total is kept as its own column so that
-- if that changes it is visible as a gap rather than hidden by a split that silently loses rows.
--
-- The return type gains two columns, so this drops and recreates rather than `create or replace`,
-- which cannot change a function's signature. `post_daily_metrics` builds its body with
-- `to_jsonb(m)` over whatever this returns, so it picks the new columns up with no change.

drop function if exists public.daily_marketing_metrics(date);

create function public.daily_marketing_metrics(p_day date)
returns table (
  report_date  date,
  signups      bigint,
  trials       bigint,
  renewals     bigint,
  renewals_499 bigint,
  renewals_299 bigint
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

    -- Trials that were paid for. `trial_started_at` still supplies the day — it is written once and
    -- never overwritten, so it cannot report the same account twice — but on its own it counts
    -- authorised mandates, most of which never pay. `total_paid_amount > 2` is what separates the
    -- ₹3 that opened a trial from an approval that produced no money.
    (select count(*)
       from public.users u, bounds b
      where u.trial_started_at >= b.from_ts
        and u.trial_started_at <  b.to_ts
        and coalesce(u.total_paid_amount, 0) > 2
        and u.user_id not in (select user_id from review_users)),

    -- Every successful recurring debit, M0 onward: the first full-price charge after the trial
    -- counts the same as the sixth month.
    (select count(*) from renewals),
    (select count(*) from renewals where plan_variant = 'plan_499'),
    (select count(*) from renewals where plan_variant = 'plan_299');
$$;

revoke all on function public.daily_marketing_metrics(date) from public, anon, authenticated;

comment on function public.daily_marketing_metrics is
  'Signups, paid trials (₹3 actually debited) and successful recurring renewals — total, and '
  'split by plan_variant into ₹499 and ₹299 — for one Asia/Kolkata calendar day.';
