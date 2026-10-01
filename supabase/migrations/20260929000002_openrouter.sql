-- Gemini through OpenRouter.
--
-- The direct Google account caps spend at its tier, and running out takes chat, palm, face and
-- the kundali worker down together (402 "prepayment credits are depleted" on 29 Sep, a 429
-- spending cap on 28 Sep). OpenRouter serves the same Gemini models on a separate bill.
--
-- One switch moves every model call; nothing else changes. `_shared/gemini.ts` sends OpenRouter
-- the same prompt, schema (translated to JSON Schema, property order kept), temperature, top_p
-- and token caps it sends Google, keeps the same retry and fallback rules, and raises the same
-- errors — a safety block still gets the chat's crisis-aware reply.
--
-- All private. `openrouter_api_key` matches the secret guard's `_key$` either way; the others
-- are private because nothing on a device has any use for them.

insert into public.app_config (key, value, is_public, description) values
  ('openrouter_use', 'false', false,
   'When true, every Gemini call (chat, palm, face, kundali) goes through OpenRouter with '
   'openrouter_api_key instead of straight to Google with gemini_api_key. Same models, prompts '
   'and settings. Takes effect within the 60s config TTL; false switches straight back.'),

  ('openrouter_api_key', '', false,
   'OpenRouter API key (sk-or-...). Read only by the Edge Functions, and only while '
   'openrouter_use is true.'),

  -- 3.8 rather than the direct route's current 3.5: half the price on OpenRouter ($0.75 / $3.75
  -- per 1M tokens against $1.50 / $9.00), and the model the direct route itself used before it
  -- was moved to 3.5. Emptied, the row mirrors gemini_model instead.
  ('openrouter_model', 'google/gemini-3.8-flash', false,
   'OpenRouter model id. Empty uses google/<gemini_model>, the model the direct route uses.'),

  ('openrouter_model_fallback', 'google/gemini-3.5-flash', false,
   'Tried once when the primary answers 408, 429 or 5xx. Empty uses '
   'google/<gemini_model_fallback>, or no retry if that is empty too.')
on conflict (key) do nothing;
