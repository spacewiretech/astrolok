-- Facebook Ads conversion reporting.
--
-- The app is bought through Facebook Ads, and until now nothing told Facebook which of those
-- installs went on to pay. These rows are what the client needs to report that.

-- The prices as numbers, beside the labels they already mirror.
--
-- Facebook's Purchase event bids against a value and an ISO currency code. The paywall only ever
-- held display copy — '₹3', '₹249' — and deriving a number from that means parsing a currency
-- symbol off marketing text, which breaks the first time a label reads '₹3 only'.
--
-- Emphatically not the billing amount: what is charged comes from the Cashfree plan and from the
-- private config rows. A wrong value here misreports return on ad spend to Facebook. It cannot
-- charge anybody anything.
insert into public.app_config (key, value, is_public, description) values
  ('trial_price_amount', '3', true,
   'Trial charge as a bare number, for ad-network conversion values. Must track '
   'trial_price_label. Not authoritative for billing — the Cashfree plan is.'),
  ('plan_price_amount', '499', true,
   'Monthly charge as a bare number, for ad-network conversion values. Must track '
   'plan_price_label. Not authoritative for billing — the Cashfree plan is.'),
  ('currency_code', 'INR', true,
   'ISO 4217 code sent with every ad-network conversion event.')
on conflict (key) do nothing;

-- The Facebook app, and the off switch.
--
-- Note what is *not* here. Both native SDKs read the App ID and the Client Token out of
-- AndroidManifest.xml and Info.plist at process start, before Dart runs and long before this
-- table is fetched — so this row is not what the SDK initialises from. It exists so that
-- reporting can be silenced, or pointed at a different Facebook app mid-campaign, without
-- shipping a release: blank app id, or facebook_events_enabled = false, and the client's Facebook
-- sink never starts. Same reasoning as mixpanel_token in 20260908000002.
--
-- The Facebook **app secret** must never be added to this table. It is a server-side Conversions
-- API credential, this app has no Conversions API, and the client SDK has no use for it.
-- app_config_secrets_stay_private would refuse it as public in any case, which is correct.
--
-- The Client Token is likewise absent, and would fail that same constraint on `_token$`. Unlike
-- mixpanel_token it needs no named exception, because it does not belong here at all — the SDK
-- can only read it from the manifest and plist.
insert into public.app_config (key, value, is_public, description) values
  ('facebook_app_id', '', true,
   'Facebook App ID. Public by design — it ships inside every installed app. Blank disables '
   'conversion reporting entirely. The SDK initialises from the manifest/plist, not from here; '
   'this row is the off switch. Never store the app secret in this table.'),
  ('facebook_events_enabled', 'true', true,
   'Master switch for Facebook conversion events. False stops the client reporting without '
   'requiring a release or clearing the app id.')
on conflict (key) do nothing;
