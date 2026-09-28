-- Trials are counted from the ₹3 charge itself.
--
-- Until now `trials` was accounts whose `trial_started_at` fell in the day and whose lifetime
-- `total_paid_amount` was over ₹2. That is a proxy on both halves. `trial_started_at` is when the
-- mandate was *approved*, not when anything was paid, and "paid over ₹2 at some point" admits an
-- account whose first charge was a full-price authorisation — no trial at all. On 2026-09-26 it
-- counted 1,787 against 1,751 real ₹3 debits: 35 of the extra accounts had never paid ₹3, having
-- authorised straight at ₹299/₹499, and one paid its ₹3 on a different day.
--
-- The count now comes from the record the trial actually is: a `kind = 'AUTH'`, `status =
-- 'SUCCESS'` row in `subscription_payments` for the trial fee. It is the same charge the server's
-- Mixpanel `Mandate Authorised` event is sent from, and the row Cashfree's
-- `SUBSCRIPTION_PAYMENT_SUCCESS` webhook writes — so the sheet and that event are now counting one
-- thing. It is *not* the app's `Payment Completed`, which is sent at the end of the paywall's poll
-- and runs ~16% short, because a ₹3 that confirms after the poll gives up never reports success.
--
-- Deliberately the charge, not "a charge that arrived by `SUBSCRIPTION_PAYMENT_SUCCESS` webhook".
-- The two are identical from 2026-09-17 on, but before that the webhook was not always arriving
-- and the hourly reconcile recorded the payments instead: 566 trials on 09-15 and 476 on 09-16
-- have no webhook at all. The money was taken either way; filtering on the webhook would report
-- 09-15 as zero trials.
--
-- Counted as distinct accounts, so a person charged ₹3 twice in one day is one trial. `created_at`
-- dates the charge because Cashfree sends no `payment_time` for subscription payments — it is when
-- the first notification (or the reconcile) recorded the row, a median of 27 seconds after the
-- mandate opened. The same `coalesce` as renewals, so the two columns bound a day identically.
--
-- The trial fee is read from `cashfree_trial_amount`, the row the functions charge from, rather
-- than written here as 3: the fee changing must not make this report zero trials.
--
-- One property changes for the better: a past day no longer moves. The old count read a lifetime
-- running total at query time, so a refund or a late first payment revised a day already reported;
-- a charge row does not change after the fact.
--
-- Signups and renewals are untouched. Same signature, so `create or replace`.

create or replace function public.daily_marketing_metrics(p_day date)
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

  -- The ₹3, with the same fallback the functions use when the row is blank or missing.
  trial_fee as (
    select coalesce(
      (select nullif(btrim(value), '')::numeric
         from public.app_config where key = 'cashfree_trial_amount'),
      3) as amount
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

    -- Accounts whose ₹3 trial fee was debited in the day. `amount <= fee` is what keeps out a
    -- returning subscriber's full-price authorisation, which Cashfree also labels AUTH. A charge
    -- whose user was deleted counts once on its own payment id rather than vanishing.
    (select count(distinct coalesce(p.user_id::text, p.cf_payment_id))
       from public.subscription_payments p, bounds b, trial_fee f
      where p.kind   = 'AUTH'
        and p.status = 'SUCCESS'
        and p.amount <= f.amount
        and coalesce(p.payment_time, p.created_at) >= b.from_ts
        and coalesce(p.payment_time, p.created_at) <  b.to_ts
        and (p.user_id is null or p.user_id not in (select user_id from review_users))),

    -- Every successful recurring debit, M0 onward: the first full-price charge after the trial
    -- counts the same as the sixth month.
    (select count(*) from renewals),
    (select count(*) from renewals where plan_variant = 'plan_499'),
    (select count(*) from renewals where plan_variant = 'plan_299');
$$;

revoke all on function public.daily_marketing_metrics(date) from public, anon, authenticated;

comment on function public.daily_marketing_metrics is
  'Signups, trials (accounts whose ₹3 AUTH charge succeeded) and successful recurring renewals — '
  'total, and split by plan_variant into ₹499 and ₹299 — for one Asia/Kolkata calendar day.';
