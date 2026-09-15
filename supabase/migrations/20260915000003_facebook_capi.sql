-- Meta Conversions API, so the ₹499 renewal reaches the ad network.
--
-- 20260908000003 gave the *client* what it needs to report the ₹3 trial. It cannot report
-- anything else: the recurring debit is taken on Cashfree's schedule with no app running, and
-- `FacebookAnalytics` latches a flag on disk after its one purchase in any case. So Meta has been
-- optimising against a trial fee while the revenue it should be buying was invisible to it.
--
-- These rows are what the *server* needs to close that gap. See functions/_shared/facebook_capi.ts.

-- The credentials.
--
-- Note what these are, because they are not the pair 20260908000003 talks about. That migration
-- forbids the Facebook **app secret** in this table, and that rule is untouched — the app secret
-- belongs to an older `/{app_id}/activities` endpoint we do not call. The modern app-event path
-- authenticates with a token generated against a **Dataset** in Events Manager and addresses that
-- dataset by id. The dataset must be linked to the app before it will accept anything (Events
-- Manager -> Data Sources -> the app -> Link to dataset); only one app can be linked to a dataset.
--
-- Seeded blank and private, the same way the Cashfree and Fast2SMS credentials are: a migration
-- must never carry a credential into git history, and the function fails closed while unset.
--
-- `facebook_capi_access_token` ends in `_token`, so app_config_secrets_stay_private *forces* it
-- private. That is the intended behaviour and not something to work around with an exception —
-- unlike mixpanel_token, nothing on the client ever reads this.
insert into public.app_config (key, value, is_public, description) values
  ('facebook_dataset_id', '', false,
   'Meta Events Manager dataset id, linked to the mobile app. Server-only; the client SDK '
   'initialises from the manifest/plist and has no use for this. Blank disables renewal '
   'reporting.'),
  ('facebook_capi_access_token', '', false,
   'Access token generated against facebook_dataset_id. Never the Facebook app secret, which '
   'this integration does not use and which must never enter this table.')
on conflict (key) do nothing;

-- The switches.
--
-- Ships **off**. Every other row here can be pasted into the dashboard in any order without
-- half-configured credentials producing rejected calls; flipping this last is what makes the
-- integration go live, and flipping it back is what stops it without a deploy.
insert into public.app_config (key, value, is_public, description) values
  ('facebook_capi_enabled', 'false', false,
   'Master switch for server-side Meta conversion reporting. Ships false: turn on only once the '
   'dataset id and access token are set and a test event has been seen in Events Manager.'),
  ('facebook_graph_api_version', 'v26.0', false,
   'Graph API version for Conversions API calls. Pinned deliberately — a version is supported '
   'for about two years, and tracking "latest" is how a working integration breaks on a schedule '
   'nobody chose. Bump it on purpose, after reading Meta''s changelog.'),
  ('facebook_capi_test_event_code', '', false,
   'Temporary code from Events Manager -> Test Events, for validating the payload end to end. '
   'MUST be cleared afterwards: left set, real conversions keep arriving in test mode, where '
   'they optimise nothing.')
on conflict (key) do nothing;
