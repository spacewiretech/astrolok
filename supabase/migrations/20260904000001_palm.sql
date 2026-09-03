-- Palm reading.
--
-- One row per reading attempt. The row is inserted *before* Gemini is called, so it doubles as
-- the daily quota anchor and as a record of failures — see the comment on `status`.
--
-- The photograph is never stored. It reaches the Edge Function as base64, is passed to Gemini,
-- and is dropped when the request ends. The only copy that outlives the request is the one on
-- the user's own device. The capture screen promises "Your images are private and secure", and
-- this is what makes that literally true rather than a reassuring phrase.

-- ---------------------------------------------------------------- config guard

-- The secret guard added in 0001 is case-sensitive: `~` in Postgres does not fold case, so
-- `_key$` matches `gemini_api_key` but NOT `GEMINI_AI_KEY`. An uppercase secret could therefore
-- be marked public, and the anon key that reads public rows ships inside every install — so a
-- public credential is a published credential.
--
-- Force any secret-shaped row private FIRST. Swapping the constraint before this would fail on
-- an existing violating row and take the whole migration with it.
update public.app_config
   set is_public = false
 where is_public
   and key ~* '(^fast2sms|_key$|_secret$|_token$|password|credential)';

alter table public.app_config
  drop constraint if exists app_config_secrets_stay_private;

alter table public.app_config
  add constraint app_config_secrets_stay_private
  check (
    is_public = false
    or key !~* '(^fast2sms|_key$|_secret$|_token$|password|credential)'
  );

comment on constraint app_config_secrets_stay_private on public.app_config is
  'Secret-looking keys cannot be marked public. The anon key that reads public rows ships '
  'inside the app, so a public credential is a published credential. Case-insensitive: an '
  'uppercase GEMINI_AI_KEY must be caught exactly as a lowercase gemini_api_key is.';

-- ---------------------------------------------------------------- config rows

-- Seeded empty and private, like every other credential. Paste the value in from the
-- dashboard so it never enters git history.
--
-- `gemini_api_key` is the name to use going forward; the function also reads `GEMINI_AI_KEY`
-- so a row already created under that name keeps working.
insert into public.app_config (key, value, is_public, description) values
  ('gemini_api_key', '', false,
   'Google AI Studio API key. Read only by the palm-reading Edge Function.'),

  -- Corrected by 0004_palm_models.sql, which is also where the notes on which models actually
  -- accept this request shape live. Left as-is here so the two files read in order.
  ('gemini_model', 'gemini-3.8-flash', false,
   'Model for palm readings. Flash keeps the scan screen near 10s; Pro roughly triples it.'),

  ('gemini_model_fallback', 'gemini-3.5-flash', false,
   'Tried once when the primary model answers 429 or 503. Empty disables the retry.'),

  ('palm_readings_per_day', '10', true,
   'Readings one account may request per day. Public so the app can say how many are left.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------- readings

create table public.palm_readings (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.users(user_id) on delete cascade,

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- Written as 'pending' before the model is called, so a request that is charged for is
  -- counted even if it never comes back. Without that, a failure loop would be free and
  -- unbounded against a paid API.
  --
  --   pending  → inserted, model not yet answered
  --   ready    → a reading the app can render
  --   rejected → the image was not a palm; the user is asked for another photo
  --   failed   → the model errored or returned something unusable
  status        text not null default 'pending'
                check (status in ('pending', 'ready', 'failed', 'rejected')),

  -- Which of the rejection cases, so the app can say "too dark" rather than a flat refusal.
  reject_reason text,

  -- What the user asked the reading to concentrate on. No health option, deliberately: see
  -- the prompt boundaries in _shared/gemini.ts.
  focus         text not null default 'life_path'
                check (focus in ('love', 'career', 'money', 'personality', 'life_path')),

  headline                text,
  strongest_trait_title   text,
  strongest_trait_summary text,
  strongest_trait_detail  text,

  -- What the model could actually see of the hand — skin texture, firmness, proportion,
  -- calluses. This is the whole personalisation mechanism: every paragraph of the reading is
  -- written to cite it, so it is kept whole rather than flattened into columns.
  hand  jsonb not null default '{}'::jsonb,

  -- The eight lines, already normalised and in display order.
  --
  -- JSONB rather than a child table because the lines are always written together and always
  -- read together — there is no query that wants one line — and because the shape will move
  -- (a ninth line, a per-line crop, a translation), which is a write here and an ALTER on a
  -- hot table otherwise. The `<= 12` bound is a sanity guard, not a business rule; the real
  -- guarantee is normalisePalmReading() in the function.
  lines jsonb not null default '[]'::jsonb
        check (jsonb_typeof(lines) = 'array' and jsonb_array_length(lines) <= 12),

  -- Diagnostics for tuning the prompt and watching latency. `image_bytes` is a size, not an
  -- image: there is no column here that could hold one.
  model       text,
  latency_ms  integer,
  image_bytes integer
);

-- The two reads that exist: the day's quota count, and the user's history newest-first.
create index palm_readings_user_created_idx
  on public.palm_readings (user_id, created_at desc);

alter table public.palm_readings enable row level security;
-- Deliberately no policies, matching `users`. RLS with zero policies denies anon and
-- authenticated outright, while service_role bypasses RLS — so only the Edge Functions,
-- which resolve the caller from a session token, can read or write a reading.

create trigger palm_readings_touch_updated_at
  before update on public.palm_readings
  for each row execute function public.touch_updated_at();

comment on table public.palm_readings is
  'One row per palm reading attempt. Written only by Edge Functions (service_role). Holds no '
  'image: the photo is passed to the model and dropped, and the only lasting copy is on the '
  'user''s own device.';

comment on column public.palm_readings.status is
  'Inserted as pending before the model call so a paid request is always counted against the '
  'daily quota, even when it fails.';

-- ---------------------------------------------------------------- housekeeping

-- Replaced whole rather than altered — 0003 owns the pg_cron schedule that calls this, and the
-- schedule keeps pointing at the same name.
--
-- The four statements above the palm ones are 0003's body, carried forward verbatim. This
-- function is defined by `create or replace` in three migrations now, so anything omitted here
-- is silently switched off: dropping the `payment_events` sweeps would leave the webhook audit
-- table growing without bound, and nothing would report it.
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
$$;

revoke all on function public.purge_expired() from public, anon, authenticated;

comment on function public.purge_expired is
  'Daily sweep: expired sessions, stale OTP throttle rows, aged webhook deliveries, and palm '
  'readings that either never completed or have aged out.';
