-- The kundali: a full birth chart, cast from a Google place, read by the sage, revealed a day later.
--
-- BEFORE APPLYING: the cron job below posts to this project's URL, like `0003_reconcile.sql`. Replace
-- qktgingrvecpetrofimy if this is ever applied to a different project.
--
-- DEPLOY ORDER: this migration, then every Edge Function (`entitlement.ts` now selects the birth
-- place columns added here, so a function deployed first would fail every user lookup), then the app.
--
-- ## The shape of it
--
--  * `kundali` (Edge Function) casts the chart at request time — arithmetic, milliseconds — and
--    inserts a `queued` row whose `unlock_at` is `kundali_unlock_hours` away.
--  * `kundali-worker`, every five minutes, claims queued rows and has the model write the reading.
--  * The app sees the chart and the reading only after `unlock_at`. That rule lives in one function,
--    `kundaliPayload` in `_shared/kundali.ts`.
--
-- ## Google's caching terms
--
-- Place ids may be stored indefinitely; latitude and longitude for 30 days. The chart is already
-- cast by then, so `purge_expired` nulls the coordinates (on `users` and `kundalis`) after 30 days
-- and a regeneration resolves the place id again.

-- ---------------------------------------------------------------- the birth place on the account

alter table public.users
  add column if not exists birth_place_id text
    check (birth_place_id is null or char_length(birth_place_id) between 1 and 300),
  add column if not exists birth_lat numeric(7, 4)
    check (birth_lat is null or birth_lat between -90 and 90),
  add column if not exists birth_lng numeric(7, 4)
    check (birth_lng is null or birth_lng between -180 and 180),
  add column if not exists birth_tz text
    check (birth_tz is null or char_length(birth_tz) between 1 and 64),
  add column if not exists birth_coords_at timestamptz;

comment on column public.users.birth_tz is
  'IANA zone of the birth place, set by the kundali form. The kundali reads birth_time on this '
  'zone; astro-chat and the Profile chart card still read it as IST.';
comment on column public.users.birth_coords_at is
  'When birth_lat/birth_lng were fetched from Google. purge_expired nulls them after 30 days.';

-- ---------------------------------------------------------------- kundalis

create table public.kundalis (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null references public.users(user_id) on delete cascade,

  status                 text not null default 'queued'
                         check (status in ('queued', 'generating', 'ready', 'failed')),

  -- What the chart was cast from. A snapshot: editing the profile later does not change a chart.
  dob                    date not null,
  birth_time             time not null,
  birth_place            text not null check (char_length(birth_place) between 1 and 120),
  birth_place_id         text check (birth_place_id is null or char_length(birth_place_id) between 1 and 300),
  birth_lat              numeric(7, 4) check (birth_lat is null or birth_lat between -90 and 90),
  birth_lng              numeric(7, 4) check (birth_lng is null or birth_lng between -180 and 180),
  birth_tz               text not null check (char_length(birth_tz) between 1 and 64),
  -- Seconds, not minutes: India's pre-1906 zones are not whole minutes.
  utc_offset_seconds     integer not null check (utc_offset_seconds between -54000 and 54000),

  chart                  jsonb not null,
  report                 jsonb,
  language               text,
  model                  text,
  prompt_version         text,
  latency_ms             integer,

  requested_at           timestamptz not null default now(),
  unlock_at              timestamptz not null,

  -- The worker's queue.
  next_attempt_at        timestamptz not null default now(),
  locked_at              timestamptz,
  attempts               smallint not null default 0,
  last_error             text,

  generated_at           timestamptz,
  first_viewed_at        timestamptz,
  -- Stamped when the waiting screen is opened, so the halfway reminder skips anyone already back.
  waiting_last_viewed_at timestamptz,
  -- Set when a regeneration replaces this row. Kept a month, then purged.
  superseded_at          timestamptz,

  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

-- One live kundali per account. `replace_live_kundali` supersedes before it inserts.
create unique index kundalis_one_live_idx on public.kundalis (user_id) where superseded_at is null;

create index kundalis_due_idx on public.kundalis (next_attempt_at)
  where status in ('queued', 'generating') and superseded_at is null;

create index kundalis_unlock_idx on public.kundalis (unlock_at)
  where status = 'ready' and superseded_at is null;

create trigger kundalis_touch_updated_at
  before update on public.kundalis
  for each row execute function public.touch_updated_at();

alter table public.kundalis enable row level security;
-- Zero policies, like every other user table: only the Edge Functions, on service_role.

comment on table public.kundalis is
  'Birth charts and their readings. One live row per account; regenerations supersede. The chart '
  'and report are revealed to the app only after unlock_at (see _shared/kundali.ts).';

-- Atomic replace: supersede the live row and insert the new one in one transaction, so a failed
-- insert can never leave an account with no kundali at all.
create or replace function public.replace_live_kundali(p_user_id uuid, p_row jsonb)
returns setof public.kundalis
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.kundalis
     set superseded_at = now()
   where user_id = p_user_id and superseded_at is null;

  return query
  insert into public.kundalis (
    user_id, status, dob, birth_time, birth_place, birth_place_id, birth_lat, birth_lng, birth_tz,
    utc_offset_seconds, chart, unlock_at, next_attempt_at
  ) values (
    p_user_id,
    'queued',
    (p_row->>'dob')::date,
    (p_row->>'birth_time')::time,
    p_row->>'birth_place',
    nullif(p_row->>'birth_place_id', ''),
    (p_row->>'birth_lat')::numeric,
    (p_row->>'birth_lng')::numeric,
    p_row->>'birth_tz',
    (p_row->>'utc_offset_seconds')::integer,
    p_row->'chart',
    (p_row->>'unlock_at')::timestamptz,
    (p_row->>'next_attempt_at')::timestamptz
  )
  returning *;
end;
$$;

revoke all on function public.replace_live_kundali(uuid, jsonb) from public, anon, authenticated;

-- The worker's claim. SKIP LOCKED so two overlapping runs take different rows; a row stuck in
-- `generating` past [p_stale_minutes] belonged to a run that died, and is taken back.
create or replace function public.claim_due_kundalis(p_limit integer, p_stale_minutes integer)
returns setof public.kundalis
language sql
security definer
set search_path = public
as $$
  update public.kundalis k
     set status = 'generating', locked_at = now(), attempts = k.attempts + 1
   where k.id in (
     select id from public.kundalis
      where superseded_at is null
        and (
          (status = 'queued' and next_attempt_at <= now())
          or (status = 'generating' and locked_at < now() - make_interval(mins => p_stale_minutes))
        )
      order by next_attempt_at
      limit p_limit
      for update skip locked
   )
  returning k.*;
$$;

revoke all on function public.claim_due_kundalis(integer, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------- per-user rate limits

-- A fixed window per key, for metered upstreams the Edge Functions proxy (Google Places today).
create table public.api_throttle (
  key                text primary key check (char_length(key) between 1 and 200),
  window_started_at  timestamptz not null default now(),
  count              integer not null default 0
);

alter table public.api_throttle enable row level security;

create or replace function public.consume_rate_limit(p_key text, p_window_seconds integer, p_max integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  insert into public.api_throttle as t (key, window_started_at, count)
  values (p_key, now(), 1)
  on conflict (key) do update
    set window_started_at = case when now() - t.window_started_at > make_interval(secs => p_window_seconds)
                                 then now() else t.window_started_at end,
        count = case when now() - t.window_started_at > make_interval(secs => p_window_seconds)
                     then 1 else t.count + 1 end
  returning count into v_count;

  return v_count <= p_max;
end;
$$;

revoke all on function public.consume_rate_limit(text, integer, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------- config

insert into public.app_config (key, value, is_public, description) values
  ('kundali_enabled', 'false', true,
   'Shows the Kundali card on Home. Off until the app build that has the feature is live.'),
  ('kundali_unlock_hours', '24', true,
   'Hours between asking for a kundali and it being revealed. The app''s countdown reads this.'),
  ('kundali_generate_delay_minutes', '10', false,
   'Minutes after a request before the worker writes the reading.'),
  ('kundali_max_regenerations', '2', false,
   'How many times an account may re-cast its kundali with different birth details.'),
  ('kundali_max_attempts', '8', false,
   'Model attempts before a kundali is marked failed. The user can ask again with the same details.'),
  ('kundali_stage_fractions', '0.02,0.10,0.55,1', false,
   'When each waiting-screen stage ticks off, as fractions of the wait. Four increasing values, last 1.'),
  ('kundali_worker_batch', '3', false,
   'Kundalis the worker claims per five-minute run.'),
  ('place_search_enabled', 'true', true,
   'Birth-place search on the kundali form. False shows the form''s "unavailable" state.'),
  ('place_search_per_hour', '120', false,
   'Place searches (autocomplete + details) one account may make per hour.'),
  ('google_places_api_key', '', false,
   'Google Maps Platform key restricted to Places API (New) and Time Zone API.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------- schedule

do $$
begin
  if exists (select 1 from cron.job where jobname = 'kundali-worker-5min') then
    perform cron.unschedule('kundali-worker-5min');
  end if;
end
$$;

-- Every five minutes, offset from the reconcile job's minute. The function answers 202 at once and
-- works after the response, so the short timeout is enough.
select cron.schedule(
  'kundali-worker-5min',
  '3-59/5 * * * *',
  $job$
  select net.http_post(
    url := 'https://qktgingrvecpetrofimy.supabase.co/functions/v1/kundali-worker',
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
$$;

revoke all on function public.purge_expired() from public, anon, authenticated;

comment on function public.purge_expired is
  'Daily sweep: expired sessions, stale OTP throttle rows, aged webhook deliveries, palm and '
  'face readings that never completed or have aged out, chat turns over a year old, chat threads '
  'deleted a month ago or emptied, superseded kundalis, Google coordinates past 30 days, and old '
  'rate-limit windows. Never user_facts.';
