-- Makes `none` the state every new account starts in, and moves the existing never-paid accounts
-- onto it.
--
-- Separate from 0001 because the value it uses was added there: Postgres will not let an enum
-- value be read in the transaction that created it.

-- ---------------------------------------------------------------- default

alter table public.users
  alter column payment_type set default 'none';

comment on type public.payment_status is
  'Subscription state. New users start on `none`, which grants nothing and marks an account that '
  'has never authorised a mandate. `trial` means the authorisation was captured and the trial '
  'clock in trial_ends_at is running.';

comment on column public.users.trial_ends_at is
  'Null until Cashfree captures the authorisation amount, at which point payment_type moves from '
  'none to trial. Set to authorization_time + trial days, once, and never extended.';

-- ---------------------------------------------------------------- backfill
--
-- Deliberately conservative: a row only moves when every marker of a mandate is absent. Being
-- wrong in the other direction — leaving a paid account on `trial` — costs nothing, because
-- entitlement is derived from the dates and those are untouched. Being wrong this way would hand
-- someone who has already paid a second ₹3 trial.
--
-- `expired` and `cancelled` are not considered at all. Neither state is reachable without a
-- mandate having existed, so by definition none of those accounts belong on `none`.

-- Suspended so the backfill genuinely changes nothing but payment_type. Without this the row's
-- updated_at would move, which is the one other visible field on every account in the table.
alter table public.users disable trigger users_touch_updated_at;

-- Wrapped so the number of accounts moved is reported rather than inferred. This runs once
-- against live rows and cannot be re-run to find out afterwards what it did, so the count
-- belongs in the deploy log.
do $$
declare
  v_before integer;
  v_moved  integer;
  v_paid   integer;
begin
  select count(*) into v_before from public.users where payment_type = 'trial';
  select count(*) into v_paid   from public.users
    where payment_type in ('active', 'expired', 'cancelled');

  update public.users as u
  set payment_type = 'none'
  where u.payment_type = 'trial'
    and u.trial_ends_at           is null
    and u.current_period_end      is null
    and u.trial_started_at        is null
    and u.subscription_started_at is null
    and u.first_paid_at           is null
    and u.active_subscription_id  is null
    and u.successful_charge_count = 0
    and u.total_paid_amount       = 0
    -- A checkout the user opened and abandoned never took any money, so it is not evidence of a
    -- spent trial. Anything else — even PENDING_AUTHORIZATION — is left alone for a human to
    -- look at rather than guessed about.
    and not exists (
      select 1
      from public.subscriptions s
      where s.user_id = u.user_id
        and s.status not in ('ABANDONED', 'FAILED_TO_CREATE')
    );

  get diagnostics v_moved = row_count;

  raise notice 'payment_type backfill: % of % trial rows moved to none; % left on trial (they '
    'hold a mandate); % active/expired/cancelled rows untouched',
    v_moved, v_before, v_before - v_moved, v_paid;

  -- The invariant the whole migration rests on. Anything that ever paid must still be able to
  -- prove it, so a backfill that touched a paying account fails the deploy rather than being
  -- discovered later by the customer.
  if exists (
    select 1 from public.users
    where payment_type = 'none'
      and (trial_ends_at is not null or current_period_end is not null
           or total_paid_amount > 0 or successful_charge_count > 0)
  ) then
    raise exception 'backfill moved an account with payment history to none; rolling back';
  end if;
end
$$;

alter table public.users enable trigger users_touch_updated_at;

-- ---------------------------------------------------------------- recurring amount
--
-- 20260903000002 seeded this at 249, which predates the price rise. It mattered less when the
-- value only named a future debit that Cashfree's own plan was the authority on. It matters now:
-- subscription-start reads this row to decide the authorisation amount charged *immediately* to a
-- returning subscriber, so a stale 249 here undercharges every one of them.
--
-- Guarded on the old value so it cannot overwrite a live figure that was set deliberately.

update public.app_config
set value = '499'
where key = 'cashfree_recurring_amount'
  and value = '249';
