-- Two monthly prices, split across new signups: ₹3 trial → ₹499/month, or ₹3 trial → ₹299/month.
--
-- Every account that exists when this runs stays on ₹499, the price it has already been shown. New
-- signups alternate on the running user total — odd total, the next user gets ₹499; even, ₹299 —
-- so the two plans fill evenly and their conversion and renewal can be compared side by side.
--
-- Nobody is told the other price exists. The ₹299 rows are private, and a user's own price reaches
-- the device only inside their own user payload (`_shared/pricing.ts`), so the paywall and
-- `subscription-start` read one answer and cannot disagree.
--
-- Off until `pricing_split_enabled` is set and `cashfree_plan_id_299` is filled in. Until both, and
-- for any app build that does not send `plan_variants: true` to `verify-otp`, every new signup gets
-- ₹499 exactly as before. That last condition exists because an installed build reads the ₹499
-- label straight from config: splitting its signups would show them ₹499 and open a ₹299 mandate.

-- ---------------------------------------------------------------- users

-- Nullable on purpose: null means "not assigned yet". A column default cannot do this job, because
-- `verify-otp` upserts and ON CONFLICT evaluates defaults on every login, not only on the insert.
alter table public.users
  add column if not exists plan_variant text
    check (plan_variant in ('plan_499', 'plan_299'));

comment on column public.users.plan_variant is
  'plan_499 | plan_299. Set once by assign_plan_variant at signup and never changed. Null reads as plan_499.';

-- Existing accounts stay on ₹499. The touch trigger is held off for the backfill: nobody edited
-- these rows, and bumping every `updated_at` would say they had.
alter table public.users disable trigger users_touch_updated_at;
update public.users set plan_variant = 'plan_499' where plan_variant is null;
alter table public.users enable trigger users_touch_updated_at;

-- ---------------------------------------------------------------- subscriptions

-- Beside `plan_id`, which names the Cashfree plan but not which side of the split it is. Reports
-- group by this; `plan_id` can change in the dashboard, the variant cannot.
alter table public.subscriptions
  add column if not exists plan_variant text
    check (plan_variant in ('plan_499', 'plan_299'));

-- The touch trigger must not fire here. `subscription-reconcile` reads `subscriptions.updated_at` as
-- its "last checked" marker, so a backfill that bumped every row would hide every mandate from the
-- stale sweep for a whole window.
alter table public.subscriptions disable trigger subscriptions_touch_updated_at;
update public.subscriptions set plan_variant = 'plan_499' where plan_variant is null;
alter table public.subscriptions enable trigger subscriptions_touch_updated_at;

-- ---------------------------------------------------------------- the counter

-- The running user total the alternation is decided on. A counter rather than `count(*)` at signup:
-- two concurrent signups would both read the same count and land on the same plan, and the count
-- is a sequential scan on the one path that has to stay fast.
--
-- Seeded with today's total and bumped once per new account, so it stays equal to the number of
-- users the rule talks about.
create table if not exists public.plan_assignment_counter (
  id    boolean primary key default true check (id),
  total bigint  not null
);

alter table public.plan_assignment_counter enable row level security;

insert into public.plan_assignment_counter (id, total)
select true, count(*) from public.users
on conflict (id) do nothing;

comment on table public.plan_assignment_counter is
  'Single row. Users counted so far, for the plan_499/plan_299 alternation in assign_plan_variant.';

-- ---------------------------------------------------------------- assignment

-- Idempotent: an account that already has a plan always gets the same one back, so a retried
-- sign-in can never move someone to the other price.
--
-- The counter's row lock is what makes two concurrent signups take turns rather than read the same
-- total. It is bumped whether or not the split applies, so it keeps counting every user.
create or replace function public.assign_plan_variant(p_user_id uuid, p_split boolean)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing text;
  v_total    bigint;
  v_variant  text;
begin
  select plan_variant into v_existing
  from public.users
  where user_id = p_user_id
  for update;

  if not found then
    raise exception 'no user %', p_user_id;
  end if;

  if v_existing is not null then
    return v_existing;
  end if;

  update public.plan_assignment_counter
  set total = total + 1
  where id = true
  returning total into v_total;

  -- `v_total - 1` users existed before this one. Odd → ₹499, even → ₹299. A missing counter row
  -- leaves v_total null, which falls through to ₹499: the safe direction is the existing price.
  if p_split and (v_total - 1) % 2 = 0 then
    v_variant := 'plan_299';
  else
    v_variant := 'plan_499';
  end if;

  update public.users set plan_variant = v_variant where user_id = p_user_id;
  return v_variant;
end;
$$;

revoke all on function public.assign_plan_variant(uuid, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------- config

-- All private. `plan_price_label` and `plan_price_amount` stay public for ₹499, which is what every
-- existing account and every old build shows; the ₹299 copy is served only inside a ₹299 user's
-- own payload.
insert into public.app_config (key, value, is_public, description) values
  ('cashfree_plan_name', '', false,
   'Cashfree name of the ₹499 plan in cashfree_plan_id. Tracking only: sent to Mixpanel as plan_name.'),
  ('cashfree_plan_id_299', '', false,
   'Pre-created PERIODIC plan in the Cashfree dashboard at ₹299. Blank keeps every signup on ₹499.'),
  ('cashfree_plan_name_299', '', false,
   'Cashfree name of the ₹299 plan. Tracking only: sent to Mixpanel as plan_name.'),
  ('cashfree_recurring_amount_299', '299', false,
   'Recurring amount of the ₹299 plan in INR. Must match the plan configured at Cashfree.'),
  ('plan_price_label_299', '₹299', false,
   'Paywall copy for ₹299 accounts. Private so no other account can read it.'),
  ('pricing_split_enabled', 'false', false,
   'true alternates new signups between plan_499 and plan_299. false puts every new signup on '
   'plan_499; accounts already on plan_299 keep it.')
on conflict (key) do nothing;
