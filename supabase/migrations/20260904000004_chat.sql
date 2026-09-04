-- Astro Chat: the transcript, the memory, and the two birth details a chart needs.
--
-- Two tables with very different lifetimes, and the difference is deliberate:
--
--   `chat_messages` is a record of a conversation. It ages out after a year like the readings.
--   `user_facts`    is what Astro knows about someone. It is not swept at all — it goes when the
--                   user says so, or when the account does. A memory that quietly forgot itself
--                   after a year would be worse than no memory, because the user would never
--                   learn it had happened.

-- ---------------------------------------------------------------- birth details

-- A chart needs an hour. `dob` alone fixes the Moon only to within a day, and the Moon crosses a
-- nakshatra in about that — so without a time the nakshatra cannot be named honestly, which is
-- exactly what computeChart() refuses to do. Both nullable: a reading without them is less
-- precise, not impossible.
--
-- `time` without a zone, because it is a wall-clock fact about a place, not an instant.
-- `jyotish.ts` reads it as IST; see IST_OFFSET_HOURS there for why, and for what to change when
-- that stops being true.
alter table public.users
  add column if not exists birth_time  time,
  add column if not exists birth_place text check (birth_place is null or char_length(btrim(birth_place)) between 1 and 120);

comment on column public.users.birth_time is
  'Local wall-clock time of birth, read as IST. Null until the user tells Astro; the chart then '
  'withholds the nakshatra rather than guessing one.';

comment on column public.users.birth_place is
  'Free text, as the user said it. Not geocoded — it is colour for the reading, and the timezone '
  'is assumed IST regardless.';

-- ---------------------------------------------------------------- the transcript

create table public.chat_messages (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.users(user_id) on delete cascade,
  created_at timestamptz not null default now(),

  -- 'astro' rather than 'assistant' or 'model': the app, the designs and the prompt all call
  -- this character Astro, and a column that calls it something else is a translation nobody
  -- asked for.
  role text not null check (role in ('user', 'astro')),

  -- A user turn is {"text": "..."}. An Astro turn is the whole normalised reply — title, opening,
  -- sections, options, ask_for — stored intact so reopening the app re-renders exactly what was
  -- on screen, rather than a re-flattened approximation of it.
  body jsonb not null default '{}'::jsonb,

  -- Diagnostics, on the Astro turn only. Never the prompt and never the reply text: those are in
  -- `body`, and duplicating them here would mean two places to purge.
  model      text,
  latency_ms integer
);

-- The one read that exists: this user's recent turns, newest first, for both the prompt window
-- and the screen.
create index chat_messages_user_created_idx
  on public.chat_messages (user_id, created_at desc);

alter table public.chat_messages enable row level security;
-- Zero policies, matching `users` and both readings: anon and authenticated are denied outright,
-- service_role bypasses RLS, so only an Edge Function resolving a session token can read a
-- conversation. This is somebody's private counsel; it should be the hardest thing here to reach.

comment on table public.chat_messages is
  'One row per turn of the Astro conversation. Written only by Edge Functions (service_role).';

-- ---------------------------------------------------------------- the memory

create table public.user_facts (
  user_id uuid not null references public.users(user_id) on delete cascade,

  -- A short snake_case slug — works_as, lives_in, worries_about. The primary key below is what
  -- makes memory *correcting* rather than *accumulating*: telling Astro you have changed jobs
  -- overwrites the old answer instead of leaving two contradictory ones in the prompt.
  key text not null check (key ~ '^[a-z][a-z0-9_]{1,39}$'),

  value text not null check (char_length(btrim(value)) between 1 and 200),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  primary key (user_id, key)
);

create index user_facts_user_updated_idx
  on public.user_facts (user_id, updated_at desc);

alter table public.user_facts enable row level security;
-- Zero policies, as above. This table holds what somebody told an astrologer about their life.

create trigger user_facts_touch_updated_at
  before update on public.user_facts
  for each row execute function public.touch_updated_at();

comment on table public.user_facts is
  'What Astro has learned about a user, one row per fact, keyed so a fact is corrected rather '
  'than duplicated. Shown to the user in Profile and deletable there. Never swept by '
  'purge_expired: this is their memory, and it goes when they say so.';

-- ---------------------------------------------------------------- config

insert into public.app_config (key, value, is_public, description) values
  ('chat_messages_per_day', '40', true,
   'Messages one account may send Astro per day. Public so the app can say how many are left.'),

  -- How much of the conversation is replayed to the model each turn. Every turn is re-sent, so
  -- this multiplies the cost of a long conversation; twenty is enough to hold a thread without
  -- paying to re-read an hour-old tangent.
  ('chat_history_turns', '20', false,
   'How many past turns are sent back to the model with each new message.'),

  -- The prompt carries every fact, so an uncapped memory is an unbounded prompt — a cost problem
  -- and a quality one, since the fiftieth fact dilutes the first.
  ('chat_facts_max', '50', false,
   'Facts kept per user. Beyond this the least recently updated are dropped.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------- housekeeping

-- Replaced whole rather than altered — 0003 owns the pg_cron schedule that calls this, and the
-- schedule keeps pointing at the same name.
--
-- The eight statements above the chat one are 0004's body, carried forward verbatim. This
-- function is defined by `create or replace` in five migrations now, so anything omitted here is
-- silently switched off: dropping the `payment_events` sweeps would leave the webhook audit table
-- growing without bound, and nothing would report it. Count them before you commit — there
-- should be nine.
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
$$;

revoke all on function public.purge_expired() from public, anon, authenticated;

comment on function public.purge_expired is
  'Daily sweep: expired sessions, stale OTP throttle rows, aged webhook deliveries, palm and '
  'face readings that never completed or have aged out, and chat turns over a year old. Never '
  'user_facts.';
