-- The ₹499 / ₹299 alternation now turns on the number of *paying* accounts, not the number of
-- accounts.
--
-- Before this, `assign_plan_variant` alternated on a counter bumped once per signup: the Nth user
-- to sign up got ₹499 or ₹299 by the parity of N. This changes the parity to come from how many
-- accounts have ever paid more than `PAID_THRESHOLD`, leaving the signup counter in place purely
-- as a record.
--
-- ## What this costs, and why it is deliberate
--
-- Payments arrive about six times more slowly than signups (138 payments against 806 signups in
-- the 24h before this was written). The parity therefore only flips once every ~6 signups, so
-- roughly six consecutive accounts are assigned the same price, then six the other. Three
-- consequences follow, and all three were accepted knowingly:
--
--   * **Assignment clusters in time.** A run of six shares whatever else those minutes have in
--     common — a campaign, a push send, a time of day — so the two arms are no longer separated
--     only by price.
--   * **Assignment depends on the outcome.** Which price an account is shown is now a function of
--     how many earlier accounts converted, which is the quantity the experiment exists to measure.
--   * **Arms fill unevenly by build.** `plan_499` still collects every account on a build that
--     does not send `plan_variants: true`, so a straight `plan_499` vs `plan_299` comparison in
--     SQL stays confounded regardless of this change. Compare in Mixpanel, segmented by app
--     version.
--
-- Written down because the next person to read `assign_plan_variant` will see parity keyed on a
-- conversion count and assume it is a bug. It is not: it is a decision.
--
-- ## Why a counter and not `count(*)`
--
-- Same reason the signup counter exists. `count(*) where total_paid_amount > 1` is a sequential
-- scan over every user, and this runs on `verify-otp` — the sign-in hot path. A column maintained
-- by a trigger on the one statement that can change the answer is O(1) at signup instead.

-- ---------------------------------------------------------------- the paid counter

-- What counts as "has paid". Deliberately low: the ₹3 trial authorisation clears it, so this
-- counts accounts that have ever moved money, not accounts that have bought a month. Raise it to
-- the cheapest plan price (299) to mean the latter — and reseed `paid_total` if you do, or the
-- parity carries on from a total that no longer matches the predicate.
--
-- Inlined rather than read from `app_config`: the trigger below runs inside every payment write,
-- and a config lookup there would put a join on the money path to save an edit that happens once.

alter table public.plan_assignment_counter
  add column if not exists paid_total bigint not null default 0;

comment on column public.plan_assignment_counter.paid_total is
  'Accounts with total_paid_amount > 1, maintained by users_track_paid_total. Drives the '
  'plan_499/plan_299 alternation in assign_plan_variant.';

comment on column public.plan_assignment_counter.total is
  'Accounts seen at signup. No longer drives assignment — kept as the running signup count.';

-- Seeded from the current truth, so the parity continues from where the data already stands
-- rather than restarting at zero and re-running a sequence these accounts have already had.
update public.plan_assignment_counter
set paid_total = (select count(*) from public.users where total_paid_amount > 1)
where id = true;

-- ---------------------------------------------------------------- keeping it true

-- Only the crossing matters. `refreshPaymentTotals` in `_shared/subscription_sync.ts` recomputes
-- and rewrites `total_paid_amount` on every charge, successful or not, and the reconcile sweep
-- replays that hourly — so this fires far more often than an account actually starts or stops
-- being a payer. Acting on the transition rather than on the write is what makes those replays
-- no-ops instead of inflating the count every hour.
--
-- The decrement is not symmetry for its own sake: a refund runs the same recompute backwards, and
-- an account refunded below the threshold has to stop being counted or the total only ever climbs.
create or replace function public.track_paid_total()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_was boolean;
  v_is  boolean;
begin
  v_is := coalesce(new.total_paid_amount, 0) > 1;

  if tg_op = 'INSERT' then
    v_was := false;
  else
    v_was := coalesce(old.total_paid_amount, 0) > 1;
  end if;

  if v_is and not v_was then
    update public.plan_assignment_counter set paid_total = paid_total + 1 where id = true;
  elsif v_was and not v_is then
    -- Floored at zero. A counter that has drifted below the real figure is a reporting problem;
    -- a negative one makes `% 2` meaningless and silently inverts the split.
    update public.plan_assignment_counter
    set paid_total = greatest(paid_total - 1, 0)
    where id = true;
  end if;

  return null;
end;
$$;

-- Two triggers, one function. `update of total_paid_amount` narrows the update case to statements
-- that actually name the column, which keeps this off the many other writes to `users` — profile
-- edits, chart writes, entitlement changes — that cannot affect the answer. That narrowing is not
-- available on insert, hence the pair.
drop trigger if exists users_track_paid_total_ins on public.users;
create trigger users_track_paid_total_ins
  after insert on public.users
  for each row
  when (new.total_paid_amount > 1)
  execute function public.track_paid_total();

drop trigger if exists users_track_paid_total_upd on public.users;
create trigger users_track_paid_total_upd
  after update of total_paid_amount on public.users
  for each row
  when (old.total_paid_amount is distinct from new.total_paid_amount)
  execute function public.track_paid_total();

-- ---------------------------------------------------------------- assignment

-- Unchanged in signature and in every other respect: still idempotent per account, still returns
-- the existing plan for an account that has one, still bumps the signup counter so `total` keeps
-- counting, and still puts every account on ₹499 when `p_split` is false.
--
-- The one difference is where the parity comes from. `paid_total` is read, never written, so two
-- concurrent signups genuinely do read the same number and land on the same plan — which is the
-- clustering described at the top, not a race this could lock its way out of.
create or replace function public.assign_plan_variant(p_user_id uuid, p_split boolean)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing text;
  v_paid     bigint;
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

  -- Still bumped, so `total` remains an honest count of accounts seen at signup even though
  -- nothing reads it for assignment any more.
  update public.plan_assignment_counter
  set total = total + 1
  where id = true
  returning paid_total into v_paid;

  -- Even number of payers → ₹299, odd → ₹499. A missing counter row leaves v_paid null, which
  -- falls through to ₹499: the safe direction is the price every existing account already has.
  if p_split and v_paid % 2 = 0 then
    v_variant := 'plan_299';
  else
    v_variant := 'plan_499';
  end if;

  update public.users set plan_variant = v_variant where user_id = p_user_id;
  return v_variant;
end;
$$;

revoke all on function public.assign_plan_variant(uuid, boolean) from public, anon, authenticated;
revoke all on function public.track_paid_total() from public, anon, authenticated;
