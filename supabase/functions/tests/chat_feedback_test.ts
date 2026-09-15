import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  MAX_FEEDBACK_COMMENT_CHARS,
  normaliseFeedbackComment,
} from "../_shared/chat_feedback.ts";

Deno.test("anything that is not text stores no comment", () => {
  for (const raw of [undefined, null, 42, true, {}, ["loved it"]]) {
    assertEquals(normaliseFeedbackComment(raw), null, `input ${JSON.stringify(raw)}`);
  }
});

Deno.test("a blank box stores no comment", () => {
  assertEquals(normaliseFeedbackComment(""), null);
  assertEquals(normaliseFeedbackComment("   \n\t  "), null);
});

Deno.test("whitespace is tidied and the words are kept", () => {
  assertEquals(
    normaliseFeedbackComment("  Very accurate\n\nabout my   career  "),
    "Very accurate about my career",
  );
});

Deno.test("a long comment is cut at the column's limit", () => {
  const stored = normaliseFeedbackComment("a".repeat(MAX_FEEDBACK_COMMENT_CHARS + 50));
  assertEquals(stored?.length, MAX_FEEDBACK_COMMENT_CHARS);
});

Deno.test("the cut never splits an emoji", () => {
  // The 500th character is the first emoji, which must survive whole. A UTF-16 slice would keep
  // half of it and store a broken character.
  const stored = normaliseFeedbackComment("a".repeat(MAX_FEEDBACK_COMMENT_CHARS - 1) + "🙏🙏");

  assert(stored !== null);
  assertEquals(Array.from(stored).length, MAX_FEEDBACK_COMMENT_CHARS);
  assert(stored.endsWith("🙏"));
});
