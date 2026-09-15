/**
 * The free text a user may write beside their chat rating.
 *
 * Pure, so the rules live somewhere a test can reach without a database: `chat-history` stores
 * whatever [normaliseFeedbackComment] returns straight into `chat_feedback.comment`.
 */

/** Matches the column's check constraint and the app's own field limit. */
export const MAX_FEEDBACK_COMMENT_CHARS = 500;

/**
 * A comment ready to store, or null when there is nothing worth storing.
 *
 * Never throws and never refuses. A comment is an extra on top of a rating, and a malformed one
 * must cost the user their comment, not their score.
 *
 * The cap counts code points with `Array.from` rather than UTF-16 units with `slice`, for two
 * reasons: Postgres `char_length` counts the same way, so a comment that passes here always passes
 * the check constraint; and a slice through the middle of an emoji would store half a character.
 */
export function normaliseFeedbackComment(raw: unknown): string | null {
  if (typeof raw !== "string") return null;

  const text = raw.replace(/\s+/g, " ").trim();
  if (!text) return null;

  const chars = Array.from(text);
  if (chars.length <= MAX_FEEDBACK_COMMENT_CHARS) return text;
  return chars.slice(0, MAX_FEEDBACK_COMMENT_CHARS).join("").trimEnd();
}
