-- `none`: the state of an account that has never authorised a mandate.
--
-- Until now `trial` meant two different things. A row created by verify-otp carried
-- `payment_type = 'trial'` with a null `trial_ends_at`, and so did an account that had actually
-- paid the ₹3 — the only thing separating them was a date column. That ambiguity is what made
-- "has this user already used their trial" unanswerable without reasoning about nulls, and it is
-- why a returning subscriber could be sold the ₹3 trial a second time.
--
-- After this, `trial` is a statement that the authorisation was captured and the clock is running.
--
-- Appended rather than positioned. Nothing orders by this column: `users_payment_type_idx` and
-- `users_trial_ends_at_idx` are both equality-only, and every read in the Edge Functions is a
-- `switch` on the value rather than a comparison against it.
--
-- Alone in its own migration because Postgres refuses to *use* an enum value added in the same
-- transaction, and the Supabase CLI wraps each migration file in one. The default, the backfill
-- and the config correction all live in the next file for exactly that reason.

alter type public.payment_status add value if not exists 'none';
