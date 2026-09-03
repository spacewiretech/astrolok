-- Corrects the model ids seeded by 0004_palm.
--
-- `gemini-2.5-flash` was retired between this feature being designed and being built: the API
-- answers 404 with "no longer available to new users". A separate migration rather than an edit
-- to the previous one, because that one has already run — and because this is the file to copy
-- the next time Google retires a model.
--
-- Both ids below were checked against the live API with the exact request this app sends
-- (inline image + responseSchema + thinkingBudget 0). That combination is not universally
-- supported, which is why they are pinned to models known to accept it rather than to an alias:
--
--   gemini-3.8-flash        primary, ~9-11s for a full eight-line reading
--   gemini-3.5-flash        fallback, ~10s
--   gemini-3.6-flash        400s on this request shape — do not use
--   *-flash-lite            400 INVALID_ARGUMENT on this request shape — do not use
--
-- A fallback that cannot serve the request is worse than none, since an overload would spend
-- its one retry on a guaranteed failure. Verify any replacement end to end before setting it.

update public.app_config
   set value = 'gemini-3.8-flash'
 where key = 'gemini_model';

update public.app_config
   set value = 'gemini-3.5-flash'
 where key = 'gemini_model_fallback';

update public.app_config
   set description = 'Model for palm readings. Must accept an inline image with a '
                     'responseSchema and thinkingBudget 0 — check before changing.'
 where key = 'gemini_model';

update public.app_config
   set description = 'Tried once when the primary answers 429 or 503. Empty disables the '
                     'retry. Must accept the same request shape as gemini_model.'
 where key = 'gemini_model_fallback';
