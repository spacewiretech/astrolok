-- Point the Facebook off switch at the real app.
--
-- 20260908000003_facebook.sql seeded `facebook_app_id` as '' and used `on conflict do nothing`, so
-- re-running it can never populate the row. Blank is the documented kill switch, and it was doing
-- its job: `facebook_analytics.dart` returns early on a blank id, so the Dart sink never started
-- and not one conversion was reported during the first campaign.
--
-- Worth knowing why the value shipping in assets/env/app.env did not cover for this. The config
-- merge is `{...shippedAppConfig, ...remote}` and `configString` falls back with `??`, which only
-- catches a *missing* key. A row that exists and is blank is a value, so it wins over the shipped
-- default. (`configLink` has the blank-aware fallback; `configString` deliberately does not,
-- because blank has to keep meaning "off" for exactly this row.)
--
-- Not a secret: the App ID ships inside every installed app and is visible in any ad the campaign
-- runs. The Client Token stays in the manifest and the app secret stays out of this repo entirely.
--
-- Clearing this cell is still how reporting gets switched off without a release, and
-- `facebook_events_enabled` remains the other way round.
update public.app_config
   set value = '1096382490017106'
 where key = 'facebook_app_id'
   and coalesce(trim(value), '') = '';
