-- Mixpanel, served as a config row rather than compiled into the app.
--
-- The token is deliberately not a --dart-define and not a value in assets/env/app.env. Keeping it
-- here means tracking can be turned off server-side without shipping a release: clearing this
-- cell is the off switch, for the client and the Edge Functions at once.

-- `app_config_secrets_stay_private` refuses `is_public = true` for anything matching `_token$`,
-- which is exactly right for every other token this table will ever hold and exactly wrong for
-- this one. A Mixpanel project token is write-only by design and already ships inside every
-- installed app, so publishing it costs nothing — it is the ingestion key, not a credential that
-- can read anything back.
--
-- Named exception rather than a loosened pattern: `mixpanel_token` is spelled out so that the
-- next `_token$` key added here still fails closed.
alter table public.app_config
  drop constraint app_config_secrets_stay_private;

alter table public.app_config
  add constraint app_config_secrets_stay_private
  check (
    is_public = false
    or key = 'mixpanel_token'
    or key !~ '(^fast2sms|_key$|_secret$|_token$|password|credential)'
  );

comment on constraint app_config_secrets_stay_private on public.app_config is
  'Secret-looking keys cannot be marked public. The anon key that reads public rows ships '
  'inside the app, so a public credential is a published credential. mixpanel_token is the one '
  'exception: it is write-only ingestion, useless for reading anything back.';

-- Seeded blank on purpose. No token means the client runs on NoopAnalytics and the Edge
-- Functions make zero outbound calls, which is the correct behaviour for any deployment that
-- has not been pointed at a Mixpanel project yet. Paste the real token in to switch it on.
insert into public.app_config (key, value, is_public, description) values
  ('mixpanel_token', '', true,
   'Mixpanel project token. Public by design — it is write-only and ships in the client. '
   'Blank disables analytics entirely; clearing it is the off switch, no release required.')
on conflict (key) do nothing;
