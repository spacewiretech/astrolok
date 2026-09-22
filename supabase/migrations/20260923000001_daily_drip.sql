-- The daily drip: six pushes a day to everyone who is not paying, two to everyone who is.
--
-- DEPLOY ORDER: after `20260917000002_notifications.sql`, whose `notification_candidates` this
-- rewrites, and before deploying `notification-dispatch` — the Edge Function's six new campaign keys
-- need these branches to exist, and these branches need nothing from it.
--
-- Everything ships switched off: `notif_drip_enabled` and all six `notif_daily_*_enabled` rows are
-- seeded `false`, and `v_due` below is false while the master switch is. Applying this migration
-- changes nothing for anybody. Nothing is sent until someone turns a slot on, one at a time, having
-- first run `./push.sh dry <campaign>`.
--
-- ## Why this is not just more campaigns
--
-- The fourteen campaigns before this one are *event*-driven: a kundali unlocks, a mandate fails, a
-- trial goes unused, and a push follows. None of them fire on a day when nothing has happened, which
-- is most days. The drip is the other half — a fixed schedule, so the app has a reason to be opened
-- on an ordinary Tuesday.
--
-- Three properties are deliberate and worth keeping:
--
--  * **No model is involved anywhere.** Who qualifies is the SQL below. Which of the twenty-six
--    variants they get is `drip_variant()`, an md5 of (user, slot, IST day). Nothing is generated at
--    send time; the only model in the story is the one that answers after the user taps.
--  * **The count is structural, not configured.** Six slots exist; four carry
--    `payment_type <> 'active'`. A paying account is sent two a day by construction. There is no
--    per-user cap to set wrong. (`notify.ts` also applies a hard ceiling across *all* campaigns, so
--    six is a maximum and not an average — see the asymmetric cap block there.)
--  * **A missed slot is lost, not queued.** `expires_at` is the slot plus two hours, and the window
--    predicate only looks forward. If the dispatcher is down at 13:00 the kundali push is skipped
--    `stale`; it does not arrive at 16:00 on top of the 15:30 one, and tomorrow is not double-loaded.
--    The cost of that choice is that silence is what a failure looks like — watch the daily counts.
--
-- ## The slots
--
--   08:00  daily_today     what today holds, and the colour to wear   everyone
--   10:30  daily_palm      read your palm, or ask Astro through it    non-active only
--   13:00  daily_kundali   cast your chart, or ask Astro about it     non-active only
--   15:30  daily_face      read your face, or ask Astro through it    non-active only
--   18:00  daily_chat      a question worth asking                    non-active only
--   20:00  daily_evening   tomorrow, and a graha from your own chart  everyone
--
-- All six sit inside the waking window (08:00–22:00 IST), so `quietHoursDeferral` never moves one —
-- which matters, because a "what does today hold" that arrives tomorrow morning is a lie. Slots are
-- at least 120 minutes apart, which is what keeps the drip's own 45-minute gap from ever tripping.
--
-- The hours are `app_config` rows (`notif_drip_slot_<slot>`), so the schedule can be retimed from the
-- dashboard without a migration. The fallbacks below are duplicated in `DRIP_SLOTS` in
-- `notification_campaigns.ts`, and `drip_schedule_test.ts` asserts the two agree.

-- ---------------------------------------------------------------- helpers

-- A numeric `app_config` row, or the fallback. Deliberately total: a blank, absent or mistyped value
-- (`ten`, `8pm`, `-3`) returns the fallback rather than raising, because this is read inside the
-- dispatcher's candidate query and one typo in the dashboard must not stop all twenty campaigns.
create or replace function public.drip_setting(p_key text, p_fallback numeric)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select t.v::numeric
      from (select btrim(value) as v from public.app_config where key = p_key) t
     where t.v ~ '^[0-9]+(\.[0-9]+)?$'
  ), p_fallback);
$$;

-- The UTC instant today's IST `p_hour` falls at — 10.5 being half past ten. "Today" is the IST
-- calendar day `p_now` is in, so every branch agrees about which day it is whatever the server's
-- clock says. Stable rather than immutable: `at time zone` depends on the tz database.
create or replace function public.drip_slot_at(p_now timestamptz, p_hour numeric)
returns timestamptz
language sql
stable
as $$
  select (date_trunc('day', p_now at time zone 'Asia/Kolkata')
          + make_interval(mins => round(p_hour * 60)::integer)) at time zone 'Asia/Kolkata';
$$;

-- This account's shuffle for this slot today: `md5(user, slot, IST day)` as an integer.
--
-- It returns the raw hash, not an index. `dripVariantFor` in `drip_copy.ts` takes it modulo the pool,
-- so the number of variants lives in one file and this function never has to be migrated to add one.
--
-- Seven hex digits, not eight. `('x' || …)::bit(32)::integer` is a signed cast that comes back
-- negative about half the time, and Postgres `%` keeps the sign — `-7 % 4` is `-3`, which would index
-- nothing. Twenty-eight bits cannot reach the sign bit, so the result is always in [0, 2^28).
--
-- The IST day is in the hash, so the choice rotates daily. The user id is in the hash, so two people
-- do not get the same sentence on the same morning. The slot is in the hash, so the 10:30 and 13:00
-- pushes shuffle independently. None of it is random: `random()` is volatile and the same row
-- enqueued twice would disagree with itself.
--
-- VERIFY ONCE on this project's Postgres before switching anything on:
--   select public.drip_variant('00000000-0000-0000-0000-000000000001'::uuid, now(), 'palm');
-- must return a value in 0 … 268435455.
create or replace function public.drip_variant(p_user_id uuid, p_now timestamptz, p_slot text)
returns integer
language sql
stable
as $$
  select ('x' || substr(md5(
            p_user_id::text || ':' || p_slot || ':' ||
            to_char(p_now at time zone 'Asia/Kolkata', 'YYYYMMDD')
          ), 1, 7))::bit(28)::integer;
$$;

revoke all on function public.drip_setting(text, numeric) from public, anon, authenticated;
revoke all on function public.drip_slot_at(timestamptz, numeric) from public, anon, authenticated;
revoke all on function public.drip_variant(uuid, timestamptz, text) from public, anon, authenticated;

-- ---------------------------------------------------------------- segments

create or replace function public.notification_candidates(
  p_campaign      text,
  p_now           timestamptz,
  p_delay_minutes integer,
  p_min_build     integer,
  p_limit         integer
)
returns table (user_id uuid, dedupe_key text, params jsonb, scheduled_for timestamptz, expires_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
-- The output columns share names with table columns (user_id, dedupe_key, ...). Without this,
-- every unqualified reference to them is an "ambiguous column" error at run time.
#variable_conflict use_column
declare
  v_delay interval := make_interval(mins => greatest(p_delay_minutes, 0));

  -- The daily drip's slot, worked out once rather than per candidate row. The dispatcher asks for one
  -- campaign at a time, so one set of these covers whichever drip slot this call is for.
  v_drip_on  boolean   := coalesce((select value = 'true' from public.app_config
                                     where key = 'notif_drip_enabled'), false);
  v_window   integer   := greatest(public.drip_setting('notif_drip_enqueue_window_minutes', 60)::integer, 1);
  v_dormant  integer   := public.drip_setting('notif_drip_dormant_days', 7)::integer;
  v_langs    text[]    := string_to_array(
                            lower(coalesce(nullif(btrim((select value from public.app_config
                                                          where key = 'notif_drip_languages')), ''),
                                           'english,hinglish,hindi,telugu,tamil,kannada,malayalam')), ',');
  v_ist_day  text      := to_char(p_now at time zone 'Asia/Kolkata', 'YYYYMMDD');
  v_hour     numeric;
  v_slot_at  timestamptz;
  v_expires  timestamptz;
  v_due      boolean   := false;
begin
  -- Which IST minute is this slot written for, and are we inside the window before it? Everything the
  -- six branches below need in order to agree with each other about "today".
  if p_campaign like 'daily\_%' then
    v_hour := public.drip_setting(
      'notif_drip_slot_' || right(p_campaign, -6),
      case p_campaign
        when 'daily_today'   then 8
        when 'daily_palm'    then 10.5
        when 'daily_kundali' then 13
        when 'daily_face'    then 15.5
        when 'daily_chat'    then 18
        when 'daily_evening' then 20
      end);

    v_slot_at := public.drip_slot_at(p_now, v_hour);
    -- Two hours, and then it is gone. A "what does today hold" that lands at nine in the evening is
    -- worse than one that never lands, and a dispatcher outage must not turn six pushes into a pile.
    v_expires := v_slot_at + interval '2 hours';
    v_due     := v_drip_on
                 and p_now >= v_slot_at - make_interval(mins => v_window)
                 and p_now <  v_slot_at;
  end if;
  return query
  with candidates as (
    -- The reveal. Entitled or not is decided at send time: a lapsed account gets the "renew to
    -- reveal" variant only when that campaign is switched on.
    select k.user_id, 'kundali_ready:' || k.id as dedupe_key,
           jsonb_build_object('kundali_id', k.id) as params,
           greatest(k.unlock_at, p_now) as scheduled_for, k.unlock_at + interval '3 days' as expires_at
      from public.kundalis k
     where p_campaign = 'kundali_ready'
       and k.superseded_at is null and k.status = 'ready' and k.first_viewed_at is null
       and k.unlock_at <= p_now and k.unlock_at > p_now - interval '3 days'

    union all
    -- Halfway through the wait, for anyone who has not come back to look at it.
    select k.user_id, 'kundali_halfway:' || k.id, jsonb_build_object('kundali_id', k.id),
           p_now, k.unlock_at - interval '1 hour'
      from public.kundalis k
     where p_campaign = 'kundali_halfway'
       and k.superseded_at is null and k.status <> 'failed'
       and p_now >= k.requested_at + (k.unlock_at - k.requested_at) / 2
       and p_now < k.unlock_at - interval '2 hours'
       and (k.waiting_last_viewed_at is null or k.waiting_last_viewed_at < k.requested_at + interval '30 minutes')

    union all
    -- Revealed a day ago and still unopened.
    select k.user_id, 'kundali_not_opened:' || k.id, jsonb_build_object('kundali_id', k.id),
           p_now, p_now + interval '2 days'
      from public.kundalis k
     where p_campaign = 'kundali_not_opened'
       and k.superseded_at is null and k.status = 'ready' and k.first_viewed_at is null
       and k.unlock_at <= p_now - interval '24 hours' and k.unlock_at > p_now - interval '7 days'

    union all
    -- Read their palm, never their face. (594 → 308 in the funnel.)
    select p.user_id, 'palm_no_face:' || p.user_id, '{}'::jsonb, p_now, p_now + interval '2 days'
      from (select r.user_id, min(r.created_at) as first_at
              from public.palm_readings r
             where r.status = 'ready' and r.created_at > p_now - interval '7 days'
             group by r.user_id) p
     where p_campaign = 'palm_no_face'
       and p.first_at <= p_now - v_delay
       and not exists (select 1 from public.face_readings f where f.user_id = p.user_id and f.status = 'ready')

    union all
    -- A reading, but never a question to Astro. (308 → 219.)
    select r.user_id, 'reading_no_chat:' || r.user_id, '{}'::jsonb, p_now, p_now + interval '2 days'
      from (select x.user_id, min(x.created_at) as first_at
              from (select user_id, created_at from public.palm_readings
                     where status = 'ready' and created_at > p_now - interval '7 days'
                    union all
                    select user_id, created_at from public.face_readings
                     where status = 'ready' and created_at > p_now - interval '7 days') x
             group by x.user_id) r
     where p_campaign = 'reading_no_chat'
       and r.first_at <= p_now - v_delay
       and not exists (select 1 from public.chat_messages m where m.user_id = r.user_id and m.role = 'user')

    union all
    -- A few hours into a one-day trial with nothing read yet.
    select u.user_id, 'trial_no_reading:' || u.user_id, '{}'::jsonb, p_now, u.trial_ends_at - interval '1 hour'
      from public.users u
     where p_campaign = 'trial_no_reading'
       and u.payment_type = 'trial'
       and u.trial_started_at <= p_now - v_delay and u.trial_started_at > p_now - interval '2 days'
       and u.trial_ends_at > p_now + interval '2 hours'
       and not exists (select 1 from public.palm_readings r
                        where r.user_id = u.user_id and r.status = 'ready' and r.created_at >= u.trial_started_at)
       and not exists (select 1 from public.face_readings r
                        where r.user_id = u.user_id and r.status = 'ready' and r.created_at >= u.trial_started_at)

    union all
    -- Chose a language, reached the paywall, never started a trial. (The 21% paywall bounce.)
    select u.user_id, 'paywall_abandoned:' || u.user_id, '{}'::jsonb, p_now, p_now + interval '24 hours'
      from public.users u
     where p_campaign = 'paywall_abandoned'
       and u.payment_type = 'none' and u.language is not null
       and u.creation_time <= p_now - v_delay and u.creation_time > p_now - interval '24 hours'

    union all
    -- Paid, but never gave a name or a birth date, so Home never opened.
    select u.user_id, 'onboarding_incomplete:' || u.user_id, '{}'::jsonb, p_now, p_now + interval '2 days'
      from public.users u
     where p_campaign = 'onboarding_incomplete'
       and (u.name is null or u.dob is null)
       and u.payment_type in ('trial', 'active')
       and coalesce(u.trial_started_at, u.subscription_started_at) <= p_now - v_delay
       and coalesce(u.trial_started_at, u.subscription_started_at) > p_now - interval '3 days'

    union all
    -- Charged the full price after the trial and has not opened the app since. (The 48%.)
    select c.user_id, 'post_charge_no_return:' || c.user_id, '{}'::jsonb, p_now, p_now + interval '2 days'
      from (select sp.user_id, min(coalesce(sp.payment_time, sp.created_at)) as first_charge
              from public.subscription_payments sp
             where sp.kind = 'RECURRING' and sp.status = 'SUCCESS' and sp.user_id is not null
             group by sp.user_id) c
     where p_campaign = 'post_charge_no_return'
       and c.first_charge <= p_now - interval '24 hours' and c.first_charge > p_now - interval '72 hours'
       and not exists (select 1 from public.user_sessions s
                        where s.user_id = c.user_id and s.last_seen_at > c.first_charge)

    union all
    -- A paying subscriber whose paid time ran out a day or two ago. (The 28% post-conversion churn.)
    select u.user_id, 'winback_paid:' || u.user_id || ':' || to_char(u.current_period_end, 'YYYYMMDD'),
           '{}'::jsonb, p_now, p_now + interval '3 days'
      from public.users u
     where p_campaign = 'winback_paid'
       and u.payment_type in ('cancelled', 'expired')
       and u.current_period_end <= p_now - interval '1 day' and u.current_period_end > p_now - interval '3 days'
       and exists (select 1 from public.subscription_payments sp
                    where sp.user_id = u.user_id and sp.kind = 'RECURRING' and sp.status = 'SUCCESS')
       and not exists (select 1 from public.subscriptions s where s.user_id = u.user_id and s.status = 'ACTIVE')

    union all
    -- Entitled and away for three days. Once a week at most.
    select u.user_id,
           'dormant:' || u.user_id || ':' || to_char(ls.last_seen at time zone 'Asia/Kolkata', 'YYYYMMDD'),
           '{}'::jsonb, p_now, p_now + interval '2 days'
      from public.users u
      join lateral (select max(s.last_seen_at) as last_seen from public.user_sessions s where s.user_id = u.user_id) ls
        on true
     where p_campaign = 'dormant'
       and u.payment_type in ('trial', 'active', 'cancelled')
       and ls.last_seen < p_now - interval '3 days' and ls.last_seen > p_now - interval '30 days'
       and not exists (select 1 from public.notifications n
                        where n.user_id = u.user_id and n.campaign = 'dormant'
                          and n.created_at > p_now - interval '7 days')


    union all
    -- The drip. Six statements, one per slot, and between them the whole of "six a day for everyone
    -- who is not paying, two for everyone who is": the four middle ones carry `payment_type <>
    -- 'active'` and the two bookends do not. The count is structural — there is no per-user cap that
    -- can be set wrong, and `countsTowardCap` is false for all six in `notification_campaigns.ts`.
    --
    -- What a row carries is deliberately thin: the slot, the IST day, and `pick` — a raw hash that
    -- `dripVariantFor` in `drip_copy.ts` takes modulo the pool. Nothing here knows how many variants
    -- exist, so adding a twenty-seventh is an edit to a TypeScript file rather than a migration.
    --
    -- What a row does NOT carry is whether the reader has already scanned their palm. That is read
    -- live in `resolveDrip` at send time: a row enqueued at 09:30 is sent at 10:30, and someone who
    -- scanned their palm in between must get "ask Astro about it", not "read your palm".
    --
    -- 08:00. The day ahead and its colour, and one of the two slots everyone gets.
    select u.user_id, 'daily_today:' || u.user_id || ':' || v_ist_day,
           jsonb_build_object('slot', 'today', 'day', v_ist_day,
                              'pick', public.drip_variant(u.user_id, p_now, 'today')),
           v_slot_at, v_expires
      from public.users u
     where p_campaign = 'daily_today' and v_due
       and not u.push_marketing_opt_out
       and lower(coalesce(nullif(btrim(u.language), ''), 'hinglish')) = any (v_langs)

    union all
    -- 10:30. The palm.
    select u.user_id, 'daily_palm:' || u.user_id || ':' || v_ist_day,
           jsonb_build_object('slot', 'palm', 'day', v_ist_day,
                              'pick', public.drip_variant(u.user_id, p_now, 'palm')),
           v_slot_at, v_expires
      from public.users u
     where p_campaign = 'daily_palm' and v_due
       and not u.push_marketing_opt_out
       and lower(coalesce(nullif(btrim(u.language), ''), 'hinglish')) = any (v_langs)
       and u.payment_type <> 'active'
       -- Ignoring six a day earns two a day, not six for ever. `notif_drip_dormant_days` = 0 turns
       -- the step-down off; the two bookend slots never step down, so nobody is dropped to silence.
       and (v_dormant <= 0
            or exists (select 1 from public.user_sessions s
                        where s.user_id = u.user_id
                          and s.last_seen_at > p_now - make_interval(days => v_dormant)))

    union all
    -- 13:00. The kundali. Never asks twice — see `resolveDrip`.
    select u.user_id, 'daily_kundali:' || u.user_id || ':' || v_ist_day,
           jsonb_build_object('slot', 'kundali', 'day', v_ist_day,
                              'pick', public.drip_variant(u.user_id, p_now, 'kundali')),
           v_slot_at, v_expires
      from public.users u
     where p_campaign = 'daily_kundali' and v_due
       and not u.push_marketing_opt_out
       and lower(coalesce(nullif(btrim(u.language), ''), 'hinglish')) = any (v_langs)
       and u.payment_type <> 'active'
       -- Ignoring six a day earns two a day, not six for ever. `notif_drip_dormant_days` = 0 turns
       -- the step-down off; the two bookend slots never step down, so nobody is dropped to silence.
       and (v_dormant <= 0
            or exists (select 1 from public.user_sessions s
                        where s.user_id = u.user_id
                          and s.last_seen_at > p_now - make_interval(days => v_dormant)))

    union all
    -- 15:30. The face.
    select u.user_id, 'daily_face:' || u.user_id || ':' || v_ist_day,
           jsonb_build_object('slot', 'face', 'day', v_ist_day,
                              'pick', public.drip_variant(u.user_id, p_now, 'face')),
           v_slot_at, v_expires
      from public.users u
     where p_campaign = 'daily_face' and v_due
       and not u.push_marketing_opt_out
       and lower(coalesce(nullif(btrim(u.language), ''), 'hinglish')) = any (v_langs)
       and u.payment_type <> 'active'
       -- Ignoring six a day earns two a day, not six for ever. `notif_drip_dormant_days` = 0 turns
       -- the step-down off; the two bookend slots never step down, so nobody is dropped to silence.
       and (v_dormant <= 0
            or exists (select 1 from public.user_sessions s
                        where s.user_id = u.user_id
                          and s.last_seen_at > p_now - make_interval(days => v_dormant)))

    union all
    -- 18:00. A question worth asking.
    select u.user_id, 'daily_chat:' || u.user_id || ':' || v_ist_day,
           jsonb_build_object('slot', 'chat', 'day', v_ist_day,
                              'pick', public.drip_variant(u.user_id, p_now, 'chat')),
           v_slot_at, v_expires
      from public.users u
     where p_campaign = 'daily_chat' and v_due
       and not u.push_marketing_opt_out
       and lower(coalesce(nullif(btrim(u.language), ''), 'hinglish')) = any (v_langs)
       and u.payment_type <> 'active'
       -- Ignoring six a day earns two a day, not six for ever. `notif_drip_dormant_days` = 0 turns
       -- the step-down off; the two bookend slots never step down, so nobody is dropped to silence.
       and (v_dormant <= 0
            or exists (select 1 from public.user_sessions s
                        where s.user_id = u.user_id
                          and s.last_seen_at > p_now - make_interval(days => v_dormant)))

    union all
    -- 20:00. Tomorrow, and the second slot a paying account gets. For anyone with a chart it names
    -- a graha out of their own report — read at send time, where the kundali is already being looked
    -- at to decide the state, so it costs no extra query.
    select u.user_id, 'daily_evening:' || u.user_id || ':' || v_ist_day,
           jsonb_build_object('slot', 'evening', 'day', v_ist_day,
                              'pick', public.drip_variant(u.user_id, p_now, 'evening')),
           v_slot_at, v_expires
      from public.users u
     where p_campaign = 'daily_evening' and v_due
       and not u.push_marketing_opt_out
       and lower(coalesce(nullif(btrim(u.language), ''), 'hinglish')) = any (v_langs)
  )
  select c.user_id, c.dedupe_key, c.params, c.scheduled_for, c.expires_at
    from candidates c
   where c.expires_at > p_now
     and public.notif_has_target(c.user_id, p_now, p_min_build)
     and not exists (select 1 from public.notifications n where n.dedupe_key = c.dedupe_key)
   limit p_limit;
end;
$$;

revoke all on function public.notification_candidates(text, timestamptz, integer, integer, integer)
  from public, anon, authenticated;

-- ---------------------------------------------------------------- indexes
--
-- At six rows per account per day the drip is the heaviest thing in the system, and every predicate
-- it adds wants cover. `users` is deliberately not indexed for it: `payment_type <> 'active'` selects
-- most of the table, so one sequential scan per slot is the right plan and an index would not be used.
--
-- The sessions index is not new work for the drip alone — `dormant` has been doing an unindexed
-- `max(last_seen_at)` per candidate since it shipped.

create index if not exists user_sessions_user_seen_idx
  on public.user_sessions (user_id, last_seen_at);

-- `resolveDrip` asks "has this account ever had a reading" once per drip push at send time.
create index if not exists palm_readings_ready_user_idx
  on public.palm_readings (user_id)
  where status = 'ready';

create index if not exists face_readings_ready_user_idx
  on public.face_readings (user_id)
  where status = 'ready';

-- `claim_due_notifications` orders by `(kind = 'transactional') desc, scheduled_for`, but
-- `notifications_due_idx` leads with `scheduled_for` alone, so every claim sorts. At six rows per
-- account per day that sort stops being free.
create index if not exists notifications_due_priority_idx
  on public.notifications (((kind = 'transactional')) desc, scheduled_for)
  where status in ('queued', 'sending');

-- ---------------------------------------------------------------- config

insert into public.app_config (key, value, is_public, description) values
  ('notif_drip_enabled', 'false', false,
   'Master switch for the whole daily drip, read in SQL (so nothing is enqueued) and in TypeScript '
   '(so anything already queued dies `disabled`). Turning this off is the one-key kill switch.'),

  ('notif_daily_today_enabled', 'false', false,
   '08:00 IST: what today holds, and the colour to wear. Every account, paying or not.'),
  ('notif_daily_palm_enabled', 'false', false,
   '10:30 IST: the palm slot. payment_type <> active only.'),
  ('notif_daily_kundali_enabled', 'false', false,
   '13:00 IST: the kundali slot. payment_type <> active only. Never asks twice for the same chart.'),
  ('notif_daily_face_enabled', 'false', false,
   '15:30 IST: the face slot. payment_type <> active only.'),
  ('notif_daily_chat_enabled', 'false', false,
   '18:00 IST: a question for Astro. payment_type <> active only.'),
  ('notif_daily_evening_enabled', 'false', false,
   '20:00 IST: tomorrow, named after a graha from the reader''s own chart. Every account.'),

  ('notif_drip_slot_today', '8', false,
   'IST hour the first slot is written for. Fractional means half past: 10.5 is 10:30. Keep every '
   'slot inside notif_quiet_end_ist .. notif_quiet_start_ist or it will be deferred to the morning.'),
  ('notif_drip_slot_palm', '10.5', false, 'IST hour of the palm slot.'),
  ('notif_drip_slot_kundali', '13', false, 'IST hour of the kundali slot.'),
  ('notif_drip_slot_face', '15.5', false, 'IST hour of the face slot.'),
  ('notif_drip_slot_chat', '18', false, 'IST hour of the chat slot.'),
  ('notif_drip_slot_evening', '20', false, 'IST hour of the evening slot.'),

  ('notif_drip_enqueue_window_minutes', '60', false,
   'How long before its slot a drip row may be enqueued. The dispatcher runs every five minutes and '
   'takes notif_dispatch_batch rows per campaign per run, so window/5 * batch is the ceiling on how '
   'many accounts one slot can reach. Widen this before raising the batch.'),

  ('notif_drip_dormant_days', '7', false,
   'An account with no session this recently drops from six pushes a day to the two bookend slots. '
   '0 turns the step-down off and sends all six regardless of whether anyone is listening.'),

  ('notif_drip_languages', 'english,hinglish,hindi,telugu,tamil,kannada,malayalam', false,
   'Which users.language values the drip is sent to, lower-case and comma-separated. All seven are '
   'on. NOTE: drip_copy.ts asks for native review of Hindi, Telugu, Tamil, Kannada and Malayalam — '
   'set this to english,hinglish to pilot on the two that need none, and widen as review lands.'),

  ('notif_drip_daily_total', '6', false,
   'Hard ceiling on pushes per IST day from ALL campaigns for a non-active account. The drip is what '
   'yields: if an event campaign fires first, it spends one of the six.'),

  ('notif_drip_daily_total_active', '2', false,
   'The same ceiling for payment_type = active.'),

  ('notif_drip_min_gap_minutes', '45', false,
   'How long a drip push waits after any other push. Slots are 120+ minutes apart so this never '
   'applies drip-to-drip; it only moves a drip row out of an event push''s way.'),

  ('notif_drip_chat_autosend', 'false', false,
   'False: a push that opens chat puts its question in the composer for the user to send. True: the '
   'app sends it on arrival, which spends a Gemini call and starts a thread per push. Travels to the '
   'app in the payload, so changing it needs no release. Builds before 11 ignore it either way.'),

  ('notif_dispatch_batch', '200', false,
   'Rows notification-dispatch enqueues per campaign per run. Was hardcoded at 200. PostgREST caps '
   'any single response at [api] max_rows = 1000 in config.toml, so values above 1000 do nothing — '
   'the dispatcher loops instead, and logs when a pass comes back full.')
on conflict (key) do nothing;
