-- Astro Chat safety: a crisis message gets a fixed reply with helplines, and a person reviews it.
--
-- A read-only scan of ten days of chat (24 Sep 2026) found about nine messages from people saying
-- they wanted to die — "ನಾನು ಸಾಯುತ್ತೇನೆ", "mai mar jaunga usk bina", "…मन कर रहा है खुदकुशी" — and
-- nothing in the product that noticed. `astro-chat` now checks every message in code, before the
-- model, before the paywall and before the day's allowance, and answers with Tele-MANAS 14416,
-- iCall and 112 in the person's language. See `_shared/crisis.ts`.
--
-- Apply before deploying that `astro-chat`: it filters on `metered` and writes the flags table.

-- ---------------------------------------------------------------- metered turns

-- Whether a user turn counts against `chat_messages_per_day`. False for a crisis message, which
-- costs no model call and must never use up someone's questions. Every existing row counted, so
-- the default is true and the column is added without a rewrite.
alter table public.chat_messages
  add column if not exists metered boolean not null default true;

comment on column public.chat_messages.metered is
  'False when a user turn does not count against chat_messages_per_day — a crisis message '
  'answered with the fixed helpline reply, which calls no model. Both astro-chat and '
  'chat-history count only metered user turns.';

-- ---------------------------------------------------------------- the review queue

create table if not exists public.chat_safety_flags (
  id uuid primary key default gen_random_uuid(),

  -- Set null rather than cascaded: the flag outlives an account or a conversation deleted
  -- afterwards, as an anonymous count of how often this happens.
  user_id    uuid references public.users(user_id) on delete set null,
  thread_id  uuid references public.chat_threads(id) on delete set null,
  message_id uuid references public.chat_messages(id) on delete set null,

  -- Which phrase list matched and the reply's language. Never the words themselves: those live
  -- in the conversation, where deleting the conversation deletes them.
  rule     text not null check (char_length(rule) <= 40),
  language text check (language is null or char_length(language) <= 40),

  created_at  timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by text check (reviewed_by is null or char_length(reviewed_by) <= 80),
  note        text check (note is null or char_length(note) <= 500)
);

-- What a reviewer opens: the unreviewed ones, newest first.
create index if not exists chat_safety_flags_unreviewed_idx
  on public.chat_safety_flags (created_at desc) where reviewed_at is null;

-- What `astro-chat` asks on every turn of a conversation: was this thread flagged in the last
-- day? For that long the paywall and the allowance are waived in it.
create index if not exists chat_safety_flags_thread_idx
  on public.chat_safety_flags (thread_id, created_at desc);

alter table public.chat_safety_flags enable row level security;
-- Zero policies, like every table holding user data. Only astro-chat, on service_role, writes it.

comment on table public.chat_safety_flags is
  'One row per chat message that matched the crisis phrase lists in _shared/crisis.ts and was '
  'answered with the fixed helpline reply. For a person to review; carries no message text. '
  'Written only by astro-chat. Not swept by purge_expired.';
