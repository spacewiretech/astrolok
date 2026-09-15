-- A written answer beside the five faces.
--
-- The rating card now carries an optional text box, submitted together with the face. It is stored
-- on the same row because it is the same answer: one per account, written once by `chat-history`
-- with `on conflict do nothing`. A comment that could arrive separately from its score would need a
-- once-only rule of its own.
--
-- Capped at 500 characters, matching the app's field and the server's normaliser. `char_length`
-- counts characters rather than bytes, so a comment in Devanagari gets the same room as one in
-- English. No backfill: every earlier row simply had no box to write in.
alter table public.chat_feedback
  add column if not exists comment text
    check (comment is null or char_length(comment) <= 500);

comment on column public.chat_feedback.comment is
  'Optional free text given with the rating, whitespace-tidied by chat-history. Null when nothing '
  'was written, and always null for a dismissal.';
