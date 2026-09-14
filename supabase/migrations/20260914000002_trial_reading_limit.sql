-- The trial allowance for readings: one palm reading and one face reading per trial.
--
-- Enforced by `palm-reading` and `face-reading` through `_shared/trial_reading_limit.ts`, before
-- the daily quota. It counts differently from that quota on purpose: the daily ceiling defends the
-- Gemini bill, so it counts every attempt; this is a product rule, so it counts only readings the
-- user actually received. A photo that was not a palm does not spend it.
--
-- No schema change. The count is taken from the existing reading tables, scoped by
-- `users.trial_started_at`, which the subscription sync already sets on authorisation.

-- ---------------------------------------------------------------- config rows

-- Public, like `palm_readings_per_day`, so the app can refuse at the tap on Home rather than after
-- a photo has been taken. The server reads the same rows, so raising one in the dashboard moves
-- both without a release.
insert into public.app_config (key, value, is_public, description) values
  ('trial_palm_readings', '1', true,
   'Successful palm readings allowed during the trial. Missing or invalid means 1.'),

  ('trial_face_readings', '1', true,
   'Successful face readings allowed during the trial. Counted separately from palm readings.')
on conflict (key) do nothing;
