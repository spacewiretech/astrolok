-- Push notifications: the sender's log, its queue, and the segments it sends to.
--
-- BEFORE APPLYING: the cron job below posts to this project's URL, like `0003_reconcile.sql`.
--
-- DEPLOY ORDER: after `20260917000001_kundali.sql`, before any Edge Function — `entitlement.ts`
-- selects `users.push_marketing_opt_out`, added here.
--
-- Everything ships switched off: `notifications_enabled` and every `notif_<campaign>_enabled` are
-- seeded `false`. Nothing is sent until someone turns a campaign on, and `notif_min_app_build`
-- keeps pushes away from builds that cannot route them.
--
-- ## The pipeline
--
-- Trigger → segment check → notification sent → deep link → outcome tracked.
--
--  * Scheduled campaigns: `notification-dispatch` runs every five minutes, asks
--    `notification_candidates` who qualifies for each enabled campaign, and enqueues them.
--  * Inline campaigns (the cancellation reason, a failed autopay) are enqueued straight from the
--    subscription sync, the moment Cashfree tells us, and sent in the same request.
--  * Every row is unique on `dedupe_key`, which names the real-world occurrence — a cancellation, a
--    kundali — so the webhook, the reconcile sweep and the status poll racing each other still send
--    one push.
--  * The row's final status and Mixpanel's `Notification Sent` / `Push Opened` close the loop.

-- ---------------------------------------------------------------- what a device can receive

alter table public.push_tokens
  -- The app build that registered the token. Old builds ignore a push's route, so a campaign that
  -- depends on one is only sent to builds at or above `notif_min_app_build`.
  add column if not exists app_build integer check (app_build is null or app_build >= 0),
  -- Android hands out a token whether or not notifications are allowed, so a token is not proof a
  -- push will be seen. Null: registered by a build that did not report it.
  add column if not exists notifications_authorized boolean;

alter table public.users
  -- Profile → "Offers & reminders". Marketing campaigns skip these accounts; transactional ones
  -- (a failed autopay, a kundali that is ready) still send.
  add column if not exists push_marketing_opt_out boolean not null default false;

-- ---------------------------------------------------------------- notifications

create table public.notifications (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.users(user_id) on delete cascade,

  campaign          text not null check (campaign ~ '^[a-z0-9_]{1,40}$'),
  dedupe_key        text not null unique check (char_length(dedupe_key) <= 200),
  kind              text not null check (kind in ('transactional', 'marketing')),

  route             text not null check (char_length(route) <= 60),
  params            jsonb not null default '{}'::jsonb,

  -- What was actually sent, filled in at send time.
  language          text,
  title             text,
  body              text,

  status            text not null default 'queued'
                    check (status in ('queued', 'sending', 'sent', 'failed', 'skipped')),
  skip_reason       text,
  error             text,
  trigger           text not null check (trigger in ('cron', 'inline', 'test')),

  scheduled_for     timestamptz not null default now(),
  expires_at        timestamptz not null,
  locked_at         timestamptz,
  attempts          smallint not null default 0,

  tokens_attempted  smallint,
  tokens_delivered  smallint,
  fcm_message_ids   text[],
  sent_at           timestamptz,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index notifications_due_idx on public.notifications (scheduled_for)
  where status in ('queued', 'sending');
create index notifications_user_sent_idx on public.notifications (user_id, sent_at desc)
  where status = 'sent';
create index notifications_campaign_idx on public.notifications (campaign, created_at desc);

create trigger notifications_touch_updated_at
  before update on public.notifications
  for each row execute function public.touch_updated_at();

alter table public.notifications enable row level security;

comment on table public.notifications is
  'Every push the backend decided to send, one row per real-world occurrence (dedupe_key), with '
  'what happened to it. Written only by Edge Functions. Purged after 180 days.';

-- ---------------------------------------------------------------- cancellation feedback

create table public.cancellation_feedback (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.users(user_id) on delete cascade,
  subscription_id  text not null,
  reason           text not null check (reason in (
                     'too_expensive', 'not_accurate', 'not_useful', 'only_exploring',
                     'payment_trouble', 'technical_issue', 'found_alternative', 'other', 'dismissed')),
  comment          text check (comment is null or char_length(comment) <= 500),
  was_in_trial     boolean,
  payment_type     text,
  language         text check (language is null or char_length(language) <= 40),
  source           text not null check (source in ('push', 'in_app')),
  notification_id  uuid references public.notifications(id) on delete set null,
  created_at       timestamptz not null default now(),
  unique (user_id, subscription_id)
);

alter table public.cancellation_feedback enable row level security;

comment on table public.cancellation_feedback is
  'Why a user ended a subscription, asked by the mid_cancel push. One answer per mandate. '
  'Written only by cancellation-feedback. Not purged: it goes with the account.';

-- ---------------------------------------------------------------- the queue

create or replace function public.claim_due_notifications(p_limit integer, p_stale_minutes integer)
returns setof public.notifications
language sql
security definer
set search_path = public
as $$
  update public.notifications n
     set status = 'sending', locked_at = now(), attempts = n.attempts + 1
   where n.id in (
     select id from public.notifications
      where (status = 'queued' and scheduled_for <= now())
         or (status = 'sending' and locked_at < now() - make_interval(mins => p_stale_minutes))
      order by (kind = 'transactional') desc, scheduled_for
      limit p_limit
      for update skip locked
   )
  returning n.*;
$$;

-- The inline path: one row, just enqueued, sent in the same request.
create or replace function public.claim_notification(p_id uuid)
returns setof public.notifications
language sql
security definer
set search_path = public
as $$
  update public.notifications n
     set status = 'sending', locked_at = now(), attempts = n.attempts + 1
   where n.id in (
     select id from public.notifications
      where id = p_id and status = 'queued' and scheduled_for <= now()
      for update skip locked
   )
  returning n.*;
$$;

revoke all on function public.claim_due_notifications(integer, integer) from public, anon, authenticated;
revoke all on function public.claim_notification(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- segments

-- Whether an account has at least one device that can show a push from this build onwards.
create or replace function public.notif_has_target(p_user_id uuid, p_now timestamptz, p_min_build integer)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.push_tokens t
      join public.user_sessions s on s.token_hash = t.session_token_hash
     where t.user_id = p_user_id
       and s.expires_at > p_now
       and t.notifications_authorized is true
       and coalesce(t.app_build, 0) >= p_min_build
  );
$$;

revoke all on function public.notif_has_target(uuid, timestamptz, integer) from public, anon, authenticated;

-- Who qualifies for a scheduled campaign right now.
--
-- A pre-filter, not the final word: `notify.ts` re-checks every row against the live account at
-- send time (entitlement is decided there, by the same `isEntitled` every other function uses),
-- so this SQL does not duplicate that rule. Every window below is bounded to at most a week, which
-- is what keeps a 180-day purge of `notifications` from ever letting a once-only key fire twice.
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
begin
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

-- ---------------------------------------------------------------- config

insert into public.app_config (key, value, is_public, description) values
  ('notifications_enabled', 'false', false,
   'Master switch for every push. Off: nothing is enqueued or sent.'),
  ('notif_min_app_build', '0', false,
   'Lowest app build number a push is sent to. Set to the first build that routes pushes.'),
  ('notif_daily_cap', '2', false,
   'Pushes counted toward the cap that one account may receive per IST day.'),
  ('notif_min_gap_minutes', '180', false,
   'Minimum minutes between two capped pushes to the same account.'),
  ('notif_quiet_start_ist', '22', false, 'Quiet hours start, hour of the day in IST.'),
  ('notif_quiet_end_ist', '8', false, 'Quiet hours end, hour of the day in IST.'),
  ('notif_mid_cancel_max_age_minutes', '180', false,
   'A cancellation first seen by the hourly reconcile is still asked about if the mandate was last '
   'seen live this recently.'),

  ('notif_mid_cancel_enabled', 'false', false, 'Why-are-you-leaving push, sent the minute a mandate is cancelled.'),
  ('notif_billing_issue_enabled', 'false', false, 'Autopay failed or mandate on hold.'),
  ('notif_kundali_ready_enabled', 'false', false, 'Kundali revealed.'),
  ('notif_kundali_ready_lapsed_enabled', 'false', false,
   'Kundali revealed to an account whose plan has lapsed: "renew to reveal". Consider leaving off.'),
  ('notif_kundali_halfway_enabled', 'false', false, 'Halfway through the kundali wait.'),
  ('notif_kundali_not_opened_enabled', 'false', false, 'Kundali revealed a day ago and not opened.'),
  ('notif_palm_no_face_enabled', 'false', false, 'Palm read, face not.'),
  ('notif_reading_no_chat_enabled', 'false', false, 'A reading, but no question to Astro.'),
  ('notif_trial_no_reading_enabled', 'false', false, 'Hours into a trial with no reading.'),
  ('notif_paywall_abandoned_enabled', 'false', false, 'Reached the paywall, never started a trial.'),
  ('notif_onboarding_incomplete_enabled', 'false', false, 'Paid but never finished name and birth date.'),
  ('notif_post_charge_no_return_enabled', 'false', false, 'Charged after the trial, not back since.'),
  ('notif_winback_paid_enabled', 'false', false, 'Paid subscriber whose plan ended a day or two ago.'),
  ('notif_dormant_enabled', 'false', false, 'Entitled and away for three days.'),

  ('notif_palm_no_face_delay_minutes', '120', false, 'Minutes after the first palm reading.'),
  ('notif_reading_no_chat_delay_minutes', '180', false, 'Minutes after the first reading.'),
  ('notif_trial_no_reading_delay_minutes', '180', false, 'Minutes after the trial starts.'),
  ('notif_paywall_abandoned_delay_minutes', '30', false, 'Minutes after signup.'),
  ('notif_onboarding_incomplete_delay_minutes', '20', false, 'Minutes after payment.'),

  ('fcm_service_account_key', '', false,
   'Firebase service-account JSON (Cloud Messaging admin) for project astrolok-21088.'),
  ('push_primer_enabled', 'true', true,
   'Shows the in-app notification primer after the language pick and on the kundali waiting screen.'),
  ('cancellation_feedback_enabled', 'true', true,
   'Shows the why-are-you-leaving screen when a mid_cancel push is opened.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------- schedule

do $$
begin
  if exists (select 1 from cron.job where jobname = 'notification-dispatch-5min') then
    perform cron.unschedule('notification-dispatch-5min');
  end if;
end
$$;

select cron.schedule(
  'notification-dispatch-5min',
  '1-59/5 * * * *',
  $job$
  select net.http_post(
    url := 'https://qktgingrvecpetrofimy.supabase.co/functions/v1/notification-dispatch',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select value from public.app_config where key = 'reconcile_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  );
  $job$
);

-- ---------------------------------------------------------------- retention

create or replace function public.purge_expired()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.user_sessions where expires_at < now();
  delete from public.otp_throttle  where last_send_at < now() - interval '7 days';
  delete from public.payment_events
   where signature_ok = false and received_at < now() - interval '30 days';
  delete from public.payment_events
   where signature_ok and received_at < now() - interval '180 days';

  -- A pending row whose function died, or a rejection the user has long since retried past.
  -- Kept a week so a support question about "it failed yesterday" can still be answered.
  delete from public.palm_readings
   where status <> 'ready' and created_at < now() - interval '7 days';

  -- Readings are the user's, but they are not a permanent record and the table would grow
  -- without bound. A year is long enough that nobody loses something they were still using.
  delete from public.palm_readings
   where created_at < now() - interval '365 days';

  -- The same two sweeps for faces, on the same schedule and for the same reasons.
  delete from public.face_readings
   where status <> 'ready' and created_at < now() - interval '7 days';

  delete from public.face_readings
   where created_at < now() - interval '365 days';

  -- Chat turns age out on the same year as the readings. `user_facts` deliberately does not
  -- appear here: see the comment on that table.
  delete from public.chat_messages
   where created_at < now() - interval '365 days';

  -- A thread the user deleted. Held a month first, so "I deleted the wrong one" is still a
  -- support question somebody can answer rather than a shrug.
  delete from public.chat_threads
   where deleted_at is not null and deleted_at < now() - interval '30 days';

  -- Threads the sweep above emptied — a year-old conversation whose every turn has just aged out
  -- would otherwise sit in the sidebar forever, opening onto nothing.
  delete from public.chat_threads t
   where t.deleted_at is null
     and t.last_message_at < now() - interval '365 days'
     and not exists (select 1 from public.chat_messages m where m.thread_id = t.id);

  -- A kundali replaced by a regeneration. Held a month, like a deleted thread.
  delete from public.kundalis
   where superseded_at is not null and superseded_at < now() - interval '30 days';

  -- Google allows latitude and longitude to be cached for 30 days. The chart is cast long before.
  update public.kundalis
     set birth_lat = null, birth_lng = null
   where birth_lat is not null and requested_at < now() - interval '30 days';
  update public.users
     set birth_lat = null, birth_lng = null
   where birth_lat is not null
     and (birth_coords_at is null or birth_coords_at < now() - interval '30 days');

  delete from public.api_throttle where window_started_at < now() - interval '1 day';

  -- Half a year of push history. Safe for once-only dedupe keys: no candidate window reaches back
  -- further than a week.
  delete from public.notifications where created_at < now() - interval '180 days';
$$;

revoke all on function public.purge_expired() from public, anon, authenticated;

comment on function public.purge_expired is
  'Daily sweep: expired sessions, stale OTP throttle rows, aged webhook deliveries, palm and '
  'face readings that never completed or have aged out, chat turns over a year old, chat threads '
  'deleted a month ago or emptied, superseded kundalis, Google coordinates past 30 days, old '
  'rate-limit windows and push history past 180 days. Never user_facts.';
