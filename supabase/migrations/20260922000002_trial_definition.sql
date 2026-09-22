-- A trial is money, not a mandate.
--
-- `daily_marketing_metrics` counted trials as accounts whose `trial_started_at` fell in the day.
-- That column is written from `snapshot.authorizedAt` in subscription_sync.ts — the moment Cashfree
-- reports the mandate authorised — and a UPI autopay mandate is authorised when the user approves
-- it in their UPI app, which is not the same event as the ₹3 actually being debited. A large share
-- of approvals never produce a payment at all: at the time of this migration 18,492 accounts had
-- `trial_started_at` set and only 6,322 of them had ever paid more than ₹2.
--
-- So the reported figure was roughly 2.8x the real one — 3,863 trials on 2026-09-16 against 1,280.
-- Marketing has been reading it as paid conversions.
--
-- The original comment argued for `trial_started_at` over "a count of ₹3 AUTH payments" on
-- idempotency grounds, and that part was right: the column is written once and never overwritten,
-- so a reconcile re-reading an old mandate cannot mint a second trial. It is kept here as the day
-- bucket for exactly that reason. What is added is the requirement that the account actually paid.
--
-- Cross-checked against `subscription_payments` where kind='AUTH' and status='SUCCESS', an entirely
-- independent record of the same event. The two agree within about 1% every day (09-16: 1,280 vs
-- 1,289; 09-21: 842 vs 846), which is the corroboration for this definition rather than the old one.
--
-- Known property, accepted deliberately: `total_paid_amount` is a lifetime running total read at
-- query time, not a snapshot of what was true that morning. A refund that takes an account back
-- under ₹2 removes it from a day already reported, and a late first payment adds one. The AUTH
-- event does not drift this way, so if a past day's number ever needs to be frozen, that is the
-- column to move to — it is within 1% of this one.

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

    -- Trials that were paid for. `trial_started_at` still supplies the day — it is written once and
    -- never overwritten, so it cannot report the same account twice — but on its own it counts
    -- authorised mandates, most of which never pay. `total_paid_amount > 2` is what separates the
    -- ₹3 that opened a trial from an approval that produced no money. `coalesce` because the column
    -- is null until a first payment lands, and `null > 2` would drop the row either way.
    (select count(*)
       from public.users u, bounds b
      where u.trial_started_at >= b.from_ts
        and u.trial_started_at <  b.to_ts
        and coalesce(u.total_paid_amount, 0) > 2
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

-- `create or replace` keeps the privileges the original migration set, but re-issued so that the
-- function's exposure is readable from this file alone rather than inferred from an earlier one.
revoke all on function public.daily_marketing_metrics(date) from public, anon, authenticated;

comment on function public.daily_marketing_metrics is
  'Signups, paid trials (₹3 actually debited) and successful recurring renewals for one '
  'Asia/Kolkata calendar day.';
