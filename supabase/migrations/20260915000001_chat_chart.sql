-- Astro Chat, part three: the chart the sage was last given, and the prompt that reads a dasha.
--
-- `users.chart` is a snapshot, not a source. The chart itself is arithmetic over `dob` and
-- `birth_time`, recomputed on every read — Profile gets it fresh inside every user payload. What
-- cannot be recomputed is what the sage was *told* last time, and that is what this column holds:
-- `astro-chat` compares the chart it is about to give against it, and when the Moon's rashi has
-- moved — because the hour of birth has arrived — tells the sage to say so, rather than silently
-- contradict a reply still sitting in the transcript.
--
-- The case that prompted it: an account was told Chandra sat in Dhanu, and a few conversations
-- later that it sat in Makara. Its first chart was built without the hour, on a day the Moon
-- changed sign.
--
-- Nullable and never backfilled: a null snapshot only means no correction is owed, which is true of
-- every account on the day this runs.
alter table public.users
  add column if not exists chart jsonb;

comment on column public.users.chart is
  'The chart astro-chat last gave the sage, as chartToJson() writes it. Used only to notice that '
  'the Moon''s rashi has changed since; the live chart is always recomputed from dob and birth_time.';

-- v3 reads the dasha, permits a narrow set of remedies and handles a rashi the person already
-- knows. Moves only a project still on v2, so one that has deliberately rolled back to v1 stays put.
update public.app_config
   set value = 'v3'
 where key = 'chat_prompt_version'
   and value = 'v2';

update public.app_config
   set description = 'Which Astro chat prompt is live: v3 is current (the dasha, narrow remedies, '
                     'the rashi they already know), v2 is the rollback, v1 is the text that first '
                     'shipped. Flip it and the model follows within the 60s config TTL, no redeploy. '
                     'Anything unrecognised is treated as v3.'
 where key = 'chat_prompt_version';
