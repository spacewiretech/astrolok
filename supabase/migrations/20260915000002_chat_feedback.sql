-- How the chat is landing, asked once per account.
--
-- One row per user, and the primary key is what makes it once: `chat-history` inserts with
-- `on conflict do nothing`, so a retried request or a second device can neither record a second
-- answer nor fail loudly trying. A dismissal is a row too — `rating` null — or the card would come
-- back on every reply to someone who has already said "not now".
--
-- Beside the score, what produced the conversation it scores: the language, the prompt version and
-- the model, all resolved server-side. A rating that cannot be lined up against
-- `chat_prompt_version` cannot say whether v3 was an improvement, which is most of why it is worth
-- asking.

create table public.chat_feedback (
  user_id uuid primary key references public.users(user_id) on delete cascade,

  -- The conversation it was given in. Set null when that thread is purged; the rating outlives it.
  thread_id uuid references public.chat_threads(id) on delete set null,

  -- 1 (worst) to 5 (best). Null is a dismissal.
  rating smallint check (rating is null or rating between 1 and 5),

  -- Questions asked in that conversation when it was rated.
  turn_count integer check (turn_count is null or turn_count >= 0),

  language       text check (language is null or char_length(language) <= 40),
  prompt_version text check (prompt_version is null or char_length(prompt_version) <= 20),
  model          text,

  created_at timestamptz not null default now()
);

alter table public.chat_feedback enable row level security;
-- Zero policies, matching every other table holding user data: only an Edge Function resolving a
-- session token, on service_role, can read or write a rating.

comment on table public.chat_feedback is
  'One rating of the Astro chat per account, 1-5, or null for a dismissal. Written only by '
  'chat-history. Not swept by purge_expired: it is one row per user and goes with the account.';

insert into public.app_config (key, value, is_public, description) values
  ('chat_rating_after_messages', '5', false,
   'Questions in one conversation before Astro asks, once per account, for a rating.')
on conflict (key) do nothing;
