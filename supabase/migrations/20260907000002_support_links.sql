-- Moves the support and legal links out of the binary and into config.
--
-- Contact us, Help & FAQ, Privacy Policy and Terms & Conditions were `static const` strings on
-- a widget, so correcting a policy URL meant an app release and a store review. These are
-- precisely the links a reviewer opens, which makes them the worst thing in the app to have
-- frozen into a build: the one time you need to fix one is the one time you cannot ship.
--
-- No DDL. `app_config` already has the public/private split and the RLS policy that lets the
-- anon key read public rows, so this is four rows and nothing else. `lib/data/repositories/
-- app_config_repository.dart` ships the same four values as defaults, and the client reads them
-- with `configLink`, which treats a blank row as absent — clearing a cell here cannot leave a
-- dead row in the account menu, it only reverts to what the installed build carries.
--
-- Every value must be a URI the phone can hand to an app. A bare domain will not open.

insert into public.app_config (key, value, is_public, description) values
  ('support_url',
   'mailto:contact@astrolok.app?subject=Astrolok%20support',
   true,
   'What "Contact us" opens, launched exactly as written — any scheme. A mailto: today; set '
   'an https://wa.me/... or a help-desk URL to move support off email without an app release. '
   'Encode the query yourself: a raw space in the subject will not open on some devices.'),

  ('help_url',
   'https://astrolok.app/help',
   true,
   'What "Help & FAQ" opens. Served by the site in lib/website/, which currently redirects '
   '/help to /contact.'),

  ('privacy_url',
   'https://astrolok.app/privacy',
   true,
   'What "Privacy Policy" opens, in the account menu and under the onboarding buttons. Both '
   'stores open this at review time — check it loads before changing it.'),

  ('terms_url',
   'https://astrolok.app/terms',
   true,
   'What "Terms & Conditions" opens, in the account menu and under the onboarding buttons. '
   'Both stores open this at review time — check it loads before changing it.')
on conflict (key) do nothing;
