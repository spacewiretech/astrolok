-- The language Astro answers in, and the switch that reverts the prompt without a deploy.

-- Nullable, and null is meaningful: it means "whatever `chat_language_default` says today".
-- Backfilling it with the current default would pin every existing account to the value that
-- happened to be set on the day this ran, so a later change to the default would reach nobody who
-- had ever used the app.
--
-- 40 characters because this string is interpolated into a model prompt. The constraint is not
-- about names — no language is called anything near that long — it is about a dashboard cell
-- being a free text box that writes into the sage's instructions.
alter table public.users
  add column if not exists language text
  check (language is null or char_length(language) between 1 and 40);

comment on column public.users.language is
  'Which language Astro replies in. Null means use app_config.chat_language_default. Validated '
  'by update-profile against app_config.chat_languages, so retiring a language is a dashboard '
  'edit; a user still holding a retired value falls back to the default at read time.';

-- Public: the client draws the picker from this list, so the anon key has to be able to read it.
-- Comma-separated rather than JSON because every value in this table is plain text with no type
-- column, and a comma list is what somebody can actually edit in a dashboard cell at 2am.
--
-- Adding a language is one edit here. The Edge Function has a hand-written instruction for these
-- three and a generic one for anything else, so a new name produces a usable prompt with no
-- redeploy — see `_shared/chat_language.ts`.
insert into public.app_config (key, value, is_public, description) values
  ('chat_languages', 'Hinglish,English,Hindi', true,
   'Comma-separated languages Astro can reply in, in the order the picker lists them. Add one '
   'here and it appears in the app with no release. Blank hides the picker and reverts chat to '
   'the model default — the off switch for the whole feature.'),

  ('chat_language_default', 'Hinglish', true,
   'Which of chat_languages a user who has never chosen gets. Must be one of them; if it is not, '
   'the first entry in the list wins.'),

  -- Private: nothing on the client acts on it, and a version string in the app is a version
  -- string that will be sent back as a request field by the next person who needs it.
  ('chat_prompt_version', 'v2', false,
   'Which Astro chat prompt is live: v2 is current, v1 is the text that shipped before answers '
   'were reworked. The rollback — flip to v1 and the model reverts within the 60s config TTL, '
   'no redeploy. Anything unrecognised is treated as v2.')
on conflict (key) do nothing;
