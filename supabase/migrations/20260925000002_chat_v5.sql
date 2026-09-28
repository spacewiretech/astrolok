-- Astro Chat, part five: the WhatsApp-style chat.
--
-- v5 answers in short messages, offers the day's upay after the answer and serves it on a yes,
-- names a window for every "kab" (from the dasha, or from Guru's transit when the hour is not
-- known), and asks for birth details in the conversation. See `_shared/astro_chat_v5.ts`.
--
-- It reaches only the new chat screen, which sends `chat_ui: 2`. Every earlier build keeps v4, so
-- moving the row now changes nothing for anyone until that build ships — and older server code
-- reads `v5` as unrecognised, which there means v4. Moves only a project on v4, so a deliberate
-- rollback stays put.
update public.app_config
   set value = 'v5'
 where key = 'chat_prompt_version'
   and value = 'v4';

update public.app_config
   set description = 'Which Astro chat prompt is live. v5 is current for the WhatsApp-style chat '
                     '(chat_ui 2): short messages, the upay offered then served, a window for every '
                     '"kab", birth details asked in the chat. Every older build gets v4. v3, v2 and '
                     'v1 are rollbacks for everyone. Flip it and the model follows within the 60s '
                     'config TTL, no redeploy. Anything unrecognised is treated as v4.'
 where key = 'chat_prompt_version';

-- The v5 plan's hook — "come back tomorrow, we'll make your 3-month plan" — promises a feature that
-- does not exist yet. Off until it does; while off, the hook invites them back to see how the upay
-- worked instead.
insert into public.app_config (key, value, is_public, description) values
  ('chat_plan_3m_enabled', 'false', false,
   'Whether Astro v5 may promise a 3-month plan when inviting someone back. Turn on only once the '
   'plan feature exists.')
on conflict (key) do nothing;
