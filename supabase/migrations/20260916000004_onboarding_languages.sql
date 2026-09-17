-- Telugu, Tamil, Kannada and Malayalam join the languages Astro answers in.
--
-- The app now asks for the language right after OTP, before the paywall, on a picker of seven
-- cards: English, Hindi, Hinglish, Telugu, Tamil, Kannada and Malayalam. The picker only draws the
-- cards `chat_languages` offers, and `update-profile` refuses any name the list does not have, so
-- the four new languages are invisible until this row carries them.
--
-- No prompt change is needed. `_shared/chat_language.ts` has hand-written instructions for
-- Hinglish, English and Hindi, and a generic one — the language in its own script, in the register
-- an elder would speak it — for any other name.
--
-- Only moves a row still holding the list `20260910000001_chat_language.sql` shipped. A list someone
-- has edited in the dashboard is theirs, and is left exactly as it is; add the four there by hand.
--
-- `chat_language_default` is untouched: someone who never chose keeps getting Hinglish.

update public.app_config
   set value = 'Hinglish,English,Hindi,Telugu,Tamil,Kannada,Malayalam'
 where key = 'chat_languages'
   and value = 'Hinglish,English,Hindi';
