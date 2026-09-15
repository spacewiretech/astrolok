-- Zero-tap OTP autofill on Android, off until the SMS can support it.
--
-- The OTP sheet reads the code in one of two ways. The default, SMS User Consent, works with any
-- OTP SMS: Android asks once, and one tap fills and submits the code. SMS Retriever needs no tap
-- at all, but only fires for a message that ends with this app's 11-character signing hash — and
-- the SMS text is the Fast2SMS template behind `fast2sms_otp_id`, not something code can add to.
--
-- So this ships false. Turn it on only after the template ends with the hash of the Play App
-- Signing key; switched on any earlier, an SMS without the hash autofills nothing at all.
--
-- Public, because the app picks the mode on the OTP sheet, before any session exists.
insert into public.app_config (key, value, is_public, description) values
  ('sms_retriever_enabled', 'false', true,
   'true reads the OTP with Android SMS Retriever (zero tap). Needs the Fast2SMS template to end '
   'with the Play App Signing hash. false uses the one-tap SMS User Consent sheet.')
on conflict (key) do nothing;
