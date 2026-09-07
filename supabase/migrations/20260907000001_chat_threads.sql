-- Astro Chat, part two: a conversation becomes conversations.
--
-- 0004 shipped one thread per account — `chat_messages` keyed on `user_id` and nothing else, with
-- the prompt fed the user's last twenty turns regardless of what they were about. That works right
-- up until somebody asks a second question: the answer about work arrives carrying last week's
-- question about love, and there is no way back to either.
--
-- So: threads. What deliberately does NOT become per-thread is `user_facts` — what Astro knows
-- about someone follows them into every conversation, which is the whole point of the memory — and
-- the daily quota, which is a limit on the account, not on a screen.

-- ---------------------------------------------------------------- the threads

create table public.chat_threads (
  id      uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(user_id) on delete cascade,

  -- Written by `astro-chat` from the first reply's own title ("Your Love Reading"), which the
  -- model already writes as a 2-5 word subject line — so a thread names itself and nobody is
  -- asked to name it. Empty until that first reply lands; the app shows a placeholder meanwhile.
  title text not null default '' check (char_length(title) <= 80),

  -- The newest turn, as one line under the title in the sidebar. Denormalised deliberately: the
  -- alternative is reading the latest message of every listed thread on every drawer open, which
  -- is either N queries or one query with a per-thread limit Postgrest cannot express — and a
  -- global limit there would let one busy conversation starve every other thread of its preview.
  -- Written on the same update that touches `last_message_at`, so it cannot drift.
  preview text not null default '' check (char_length(preview) <= 200),

  created_at timestamptz not null default now(),

  -- What the sidebar sorts on. Touched on every turn rather than derived with a max() over
  -- `chat_messages`, because the sidebar reads it on every open and that aggregate would grow
  -- with the conversation.
  last_message_at timestamptz not null default now(),

  -- Soft delete. A hard delete would cascade the messages away, and the daily quota is a count of
  -- `role='user'` rows in a rolling 24 hours — so deleting a thread would refund the questions it
  -- cost, and the allowance would be advisory. The rows stay countable; the thread stops being
  -- listed. `purge_expired` clears these out a month later.
  deleted_at timestamptz
);

-- The one read the sidebar makes: this user's live threads, newest conversation first.
create index chat_threads_user_recent_idx
  on public.chat_threads (user_id, last_message_at desc)
  where deleted_at is null;

alter table public.chat_threads enable row level security;
-- Zero policies, matching `chat_messages` and both readings: anon and authenticated are denied
-- outright and service_role bypasses RLS, so only an Edge Function resolving a session token can
-- see that a conversation exists, let alone read it.

comment on table public.chat_threads is
  'One row per conversation with Astro. Titles itself from the first reply. Soft-deleted so the '
  'daily quota cannot be refunded by deleting a thread. Written only by Edge Functions.';

-- ---------------------------------------------------------------- the messages

-- Nullable for the length of this migration, then set NOT NULL once the backfill below has given
-- every existing row a home. A message with no thread would be a message no screen can reach.
alter table public.chat_messages
  add column if not exists thread_id uuid references public.chat_threads(id) on delete cascade;

-- ---------------------------------------------------------------- the backfill

-- Everything anybody has already said becomes one thread per account, spanning the real dates of
-- what it holds. Named rather than left blank: these are conversations people had, and finding
-- them under an empty title would read as a bug.
insert into public.chat_threads (user_id, title, created_at, last_message_at)
select user_id, 'Your conversation', min(created_at), max(created_at)
  from public.chat_messages
 where thread_id is null
 group by user_id;

-- Exactly one thread exists per user at this point — the insert above just made them, and there
-- were none before — so this cannot fan a message out across two.
update public.chat_messages m
   set thread_id = t.id
  from public.chat_threads t
 where m.thread_id is null
   and t.user_id = m.user_id;

alter table public.chat_messages alter column thread_id set not null;

-- And give each backfilled thread the preview it would have had. `distinct on` takes the newest
-- turn per thread in one pass; an Astro turn previews as its answer, a user turn as their words.
update public.chat_threads t
   set preview = p.preview
  from (
    select distinct on (thread_id)
           thread_id,
           left(
             btrim(coalesce(body->>'verdict', body->>'opening', body->>'text', '')),
             100
           ) as preview
      from public.chat_messages
     order by thread_id, created_at desc
  ) p
 where p.thread_id = t.id
   and p.preview <> '';

-- Replaces `chat_messages_user_created_idx` as the hot path: every read is now scoped to a thread
-- — the prompt window, the transcript, the sidebar's preview. The old index stays for the quota
-- count, which is still per user.
create index chat_messages_thread_created_idx
  on public.chat_messages (thread_id, created_at desc);

comment on column public.chat_messages.thread_id is
  'The conversation this turn belongs to. Cascades: deleting a thread for real deletes its turns, '
  'which is why the app soft-deletes instead.';

-- ---------------------------------------------------------------- housekeeping

-- Replaced whole rather than altered — 0003 owns the pg_cron schedule that calls this, and the
-- schedule keeps pointing at the same name.
--
-- The nine statements 0004 left behind are carried forward verbatim below. This function is
-- defined by `create or replace` in six migrations now, so anything omitted here is silently
-- switched off: dropping the `payment_events` sweeps would leave the webhook audit table growing
-- without bound, and nothing would report it. Count them before you commit — there should be
-- eleven now: the nine, plus the two thread sweeps at the end.
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
$$;

revoke all on function public.purge_expired() from public, anon, authenticated;

comment on function public.purge_expired is
  'Daily sweep: expired sessions, stale OTP throttle rows, aged webhook deliveries, palm and '
  'face readings that never completed or have aged out, chat turns over a year old, and chat '
  'threads that were deleted a month ago or have been emptied by the sweep. Never user_facts.';
