-- ₹699 replaces ₹299 as the price new signups are split against, and the split stops being 50/50.
--
-- Before this, new signups went ₹499 or ₹299 by the parity of `paid_total`. After it they go ₹499
-- or ₹699, with ₹699 taking `pricing_split_699_percent` of them (seeded 25) and ₹499 the rest.
-- The share is read from `app_config` at every signup, so it can be changed at any time from the
-- dashboard, taking effect within the minute the config cache lives.
--
-- ## ₹299 is closed, not withdrawn
--
-- `plan_299` stays a valid variant and its config rows stay filled in. On the day this was written
-- 2,150 mandates were live on the ₹299 Cashfree plan and 38,426 accounts were assigned it. Those
-- mandates debit ₹299 at Cashfree regardless, so repointing the `_299` rows at the ₹699 plan
-- would have put "₹699/month" on the screen of every one of them while charging ₹299 — and opened
-- a ₹699 mandate the next time any of them re-subscribed. Keeping ₹299 whole means every existing
-- account sees and pays exactly what it did; only accounts assigned from now on can land on ₹699.
--
-- That includes the ~31,000 ₹299 accounts that never paid: a plan is set once and never changed,
-- so they are still offered ₹299 if they come back. Few do — under 1% of checkouts in the week
-- before this started more than a day after signup.
--
-- ## Still keyed on payers
--
-- The position in the split still comes from `paid_total` — accounts with `total_paid_amount > 1`,
-- i.e. that have ever moved money — for the reasons in `20260918000001_plan_split_paid_counter.sql`,
-- and with the same clustering. What changes is only how a count maps to a price. At P percent, a
-- count `n` goes to ₹699 when `(n * P) % 100 < P`: exactly P of every 100 consecutive counts, spread
-- as evenly as whole numbers allow. At 25 that is every fourth count, so roughly one run of signups
-- on ₹699, then three on ₹499. At 50 it is every even count, which is the old rule exactly.
--
-- ## Order
--
-- Safe before the functions deploy. The new parameters default to `plan_299` at 50, so the deployed
-- `verify-otp`, which does not send them, keeps assigning exactly as before. The new `verify-otp`
-- sends `plan_699` and the configured share — but only once `cashfree_plan_id_699` is filled in;
-- until then `splitEnabled` is false and every new signup gets ₹499.

-- ---------------------------------------------------------------- the variant

alter table public.users
  drop constraint if exists users_plan_variant_check,
  add constraint users_plan_variant_check
    check (plan_variant in ('plan_499', 'plan_299', 'plan_699'));

comment on column public.users.plan_variant is
  'plan_499 | plan_699 | plan_299. Set once by assign_plan_variant at signup and never changed. '
  'Null reads as plan_499. plan_299 is closed to new signups since 20260929000003.';

-- The touch trigger does not fire on a constraint change, so `subscription-reconcile`'s
-- `updated_at` marker is untouched.
alter table public.subscriptions
  drop constraint if exists subscriptions_plan_variant_check,
  add constraint subscriptions_plan_variant_check
    check (plan_variant in ('plan_499', 'plan_299', 'plan_699'));

-- ---------------------------------------------------------------- assignment

-- A new signature, so the old one goes first: left beside it, a call naming only the first two
-- arguments would match both and fail as ambiguous.
drop function if exists public.assign_plan_variant(uuid, boolean);

-- Otherwise as before: idempotent per account, bumps the signup counter, reads `paid_total`
-- without writing it, and puts every account on ₹499 when `p_split` is false.
create or replace function public.assign_plan_variant(
  p_user_id           uuid,
  p_split             boolean,
  p_alternate         text    default 'plan_299',
  p_alternate_percent integer default 50
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing text;
  v_paid     bigint;
  v_percent  integer;
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
  returning paid_total into v_paid;

  v_percent := least(greatest(coalesce(p_alternate_percent, 0), 0), 100);

  -- P of every 100 consecutive payer counts go to the alternate, evenly spread. A missing counter
  -- row leaves v_paid null, which falls through to ₹499, as does an alternate that is not a plan:
  -- the safe direction is the price every existing account already has.
  if p_split
     and p_alternate in ('plan_299', 'plan_699')
     and (v_paid * v_percent) % 100 < v_percent then
    v_variant := p_alternate;
  else
    v_variant := 'plan_499';
  end if;

  update public.users set plan_variant = v_variant where user_id = p_user_id;
  return v_variant;
end;
$$;

revoke all on function public.assign_plan_variant(uuid, boolean, text, integer)
  from public, anon, authenticated;

comment on column public.plan_assignment_counter.paid_total is
  'Accounts with total_paid_amount > 1, maintained by users_track_paid_total. Drives the '
  'plan_499/plan_699 split in assign_plan_variant.';

-- ---------------------------------------------------------------- config

-- All private, like the ₹299 rows: the ₹699 copy is served only inside a ₹699 user's own payload.
-- `cashfree_plan_id_699` ships blank, which keeps the split off (everyone on ₹499) until the
-- Cashfree plan id is pasted in.
insert into public.app_config (key, value, is_public, description) values
  ('cashfree_plan_id_699', '', false,
   'Pre-created PERIODIC plan in the Cashfree dashboard at ₹699. Blank puts every new signup on '
   '₹499.'),
  ('cashfree_plan_name_699', '', false,
   'Cashfree name of the ₹699 plan. Tracking only: sent to Mixpanel as plan_name.'),
  ('cashfree_recurring_amount_699', '699', false,
   'Recurring amount of the ₹699 plan in INR. Must match the plan configured at Cashfree.'),
  ('plan_price_label_699', '₹699', false,
   'Paywall copy for ₹699 accounts. Private so no other account can read it.'),
  ('pricing_split_699_percent', '25', false,
   'Share of new signups, 0-100, put on ₹699 while pricing_split_enabled is true; the rest get '
   '₹499. Counted over paying accounts (total_paid_amount > 1). Whole numbers; blank reads as 0.')
on conflict (key) do nothing;

update public.app_config
set description = 'true splits new signups between plan_499 and plan_699, by '
                  'pricing_split_699_percent. false puts every new signup on plan_499; accounts '
                  'already on plan_699 or plan_299 keep it.'
where key = 'pricing_split_enabled';

-- The ₹299 rows keep their values: they are what 2,150 live mandates and their accounts are priced
-- from. Only the descriptions change, so nobody reads them as spare and repoints them.
update public.app_config
set description = 'The ₹299 plan, closed to new signups since 20260929000003. Still what every '
                  'plan_299 account is shown and re-subscribes at, so keep it filled in while any '
                  'plan_299 account is live.'
where key = 'cashfree_plan_id_299';
