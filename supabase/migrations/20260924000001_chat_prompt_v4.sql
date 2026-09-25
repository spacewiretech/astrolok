-- Astro Chat, part four: the prompt that answers "kab" with a window.
--
-- v4 came out of a review of every one-star chat rating over three days of v3. Those people asked
-- when — shaadi, naukri, paisa, ghar — and were told "the door opens once you are settled"; they
-- were asked for their birth hour turn after turn; and they were answered in textbook Hindi. v4
-- names a window computed from the dasha (`_shared/chat_timing.ts`), asks for the hour once,
-- writes the Hindi people actually type, and roughly halves everything below the verdict.
--
-- No schema change. Safe in either order against the functions deploy: code from before v4 reads
-- 'v4' as unrecognised, and unrecognised read as v3 there. Moves only a project still on v3, so
-- one that has deliberately rolled back to v2 or v1 stays put.
update public.app_config
   set value = 'v4'
 where key = 'chat_prompt_version'
   and value = 'v3';

update public.app_config
   set description = 'Which Astro chat prompt is live: v4 is current (a "when" answered with a '
                     'window computed from the dasha, the birth hour asked for once, plain Hindi, '
                     'a shorter body), v3 is the rollback, then v2 and v1. Flip it and the model '
                     'follows within the 60s config TTL, no redeploy. Anything unrecognised is '
                     'treated as v4.'
 where key = 'chat_prompt_version';
