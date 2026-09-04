-- Face reading, and the two ceremonial lines both readings now carry.
--
-- A deliberate mirror of `palm_readings`: same statuses, same focus values, same
-- RLS-with-no-policies posture, same "the photograph is never stored" guarantee. Where the two
-- tables differ, it is because the readings genuinely differ — six named features rather than
-- eight named lines, and a set of trait chips the palm reading has no equivalent for.
--
-- The photograph is never stored. It reaches the Edge Function as base64, is passed to Gemini,
-- and is dropped when the request ends. The only copy that outlives the request is the one on
-- the user's own device. The capture screen promises "Your images are private and secure", and
-- this is what makes that literally true rather than a reassuring phrase. That promise carries
-- more weight here than it did for palms: this is a photograph of someone's face.

-- ---------------------------------------------------------------- config rows

-- Its own ceiling rather than a shared one. A user who has read their palm ten times today
-- should still be able to read their face — a shared counter would be a limit nobody would
-- expect from an app that sells both.
--
-- Public, like `palm_readings_per_day`, so the app can say how many are left. The Gemini key and
-- model rows are already seeded by 0004_palm.sql and are reused as-is; a second copy would be a
-- second thing to rotate.
insert into public.app_config (key, value, is_public, description) values
  ('face_readings_per_day', '10', true,
   'Face readings one account may request per day. Counted separately from palm readings.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------- palm: the pandit lines

-- Both readings now open with an invocation and close with a blessing. Per-line `sanskrit` and
-- `blessing` need no DDL — `lines` is jsonb — but these two are top-level and are columns.
alter table public.palm_readings
  add column if not exists invocation text,
  add column if not exists blessing   text;

comment on column public.palm_readings.invocation is
  'The reading''s opening line, written after the model has looked at the hand so that it is '
  'about this hand. Rendered above the headline and read aloud first.';

-- ---------------------------------------------------------------- face readings

create table public.face_readings (
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
  --   rejected → the image was not a face; the user is asked for another photo
  --   failed   → the model errored or returned something unusable
  status        text not null default 'pending'
                check (status in ('pending', 'ready', 'failed', 'rejected')),

  -- Which of the rejection cases, so the app can say "too dark" rather than a flat refusal.
  reject_reason text,

  -- Same five as palm, and no health option for the same reason: offering one would steer the
  -- model straight at the claims the prompt forbids.
  focus         text not null default 'life_path'
                check (focus in ('love', 'career', 'money', 'personality', 'life_path')),

  invocation              text,
  headline                text,
  core_trait_title        text,
  core_trait_summary      text,
  core_trait_detail       text,
  blessing                text,

  -- The four chips under the core trait, as an array of keys from a closed vocabulary. JSONB
  -- rather than text[] purely for consistency with the two columns below it.
  traits jsonb not null default '[]'::jsonb
         check (jsonb_typeof(traits) = 'array' and jsonb_array_length(traits) <= 6),

  -- What the model could actually see of the face — shape, set, proportion, the expression being
  -- held. This is the whole personalisation mechanism: every paragraph of the reading is written
  -- to cite it, so it is kept whole rather than flattened into columns.
  --
  -- Note what it does not and must not contain: complexion, skin tone, apparent age, apparent
  -- gender. Those are absent from the response schema and forbidden by the prompt, and a column
  -- for them would be an invitation to add them back.
  face  jsonb not null default '{}'::jsonb,

  -- The six features, already normalised and in display order.
  --
  -- JSONB rather than a child table for the same reasons as `palm_readings.lines`: they are
  -- always written together and always read together, and the shape will move. The `<= 8` bound
  -- is a sanity guard, not a business rule; the real guarantee is normaliseFaceReading().
  parts jsonb not null default '[]'::jsonb
        check (jsonb_typeof(parts) = 'array' and jsonb_array_length(parts) <= 8),

  -- Diagnostics for tuning the prompt and watching latency. `image_bytes` is a size, not an
  -- image: there is no column here that could hold one.
  model       text,
  latency_ms  integer,
  image_bytes integer
);

-- The two reads that exist: the day's quota count, and the user's history newest-first.
create index face_readings_user_created_idx
  on public.face_readings (user_id, created_at desc);

alter table public.face_readings enable row level security;
-- Deliberately no policies, matching `users` and `palm_readings`. RLS with zero policies denies
-- anon and authenticated outright, while service_role bypasses RLS — so only the Edge Functions,
-- which resolve the caller from a session token, can read or write a reading.

create trigger face_readings_touch_updated_at
  before update on public.face_readings
  for each row execute function public.touch_updated_at();

comment on table public.face_readings is
  'One row per face reading attempt. Written only by Edge Functions (service_role). Holds no '
  'image: the photo is passed to the model and dropped, and the only lasting copy is on the '
  'user''s own device.';

comment on column public.face_readings.status is
  'Inserted as pending before the model is called so a paid request is always counted against '
  'the daily quota, even when it fails.';

comment on column public.face_readings.face is
  'What the model could see: shape, set, proportion, expression. Never complexion, skin tone, '
  'apparent age or apparent gender — those are forbidden by the prompt and absent from the '
  'response schema, and this column must not become the place they come back.';

-- ---------------------------------------------------------------- housekeeping

-- Replaced whole rather than altered — 0003 owns the pg_cron schedule that calls this, and the
-- schedule keeps pointing at the same name.
--
-- The six statements above the face ones are 0004's body, carried forward verbatim. This
-- function is defined by `create or replace` in four migrations now, so anything omitted here is
-- silently switched off: dropping the `payment_events` sweeps would leave the webhook audit
-- table growing without bound, and nothing would report it. Count them before you commit — there
-- should be eight.
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
$$;

revoke all on function public.purge_expired() from public, anon, authenticated;

comment on function public.purge_expired is
  'Daily sweep: expired sessions, stale OTP throttle rows, aged webhook deliveries, and palm '
  'and face readings that either never completed or have aged out.';
