import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  buildUserPrompt,
  focusMismatch,
  geminiSettings,
  LINE_KEYS,
  normalisePalmReading,
} from "../_shared/gemini.ts";

/**
 * `normalisePalmReading` is the whole correctness surface of the palm feature: everything a
 * language model can get wrong about a contract arrives here, and the screen renders whatever
 * comes out. It is pure, so all of it is testable without a key or a network.
 *
 * The bias under test throughout is that an imperfect reading still ships. After a
 * twenty-second wait, seven good lines beat an error page.
 */

function line(key: string, over: Record<string, unknown> = {}) {
  return {
    key,
    title: `${key} line`,
    status: "Strong",
    summary: "A short summary.",
    detail: "A detailed paragraph about this line, grounded in the hand.",
    meaning: ["First bullet.", "Second bullet.", "Third bullet."],
    tip: "A small kind nudge.",
    ...over,
  };
}

function validPayload(over: Record<string, unknown> = {}) {
  return {
    is_palm: true,
    reject_reason: "none",
    hand: {
      which_hand: "right",
      skin_texture: "smooth",
      firmness: "soft",
      observations: ["The skin is smooth.", "The palm is broad."],
    },
    focus_echo: "love",
    headline: "A warm and curious hand.",
    strongest_trait: {
      title: "Independent & Intuitive",
      summary: "You trust your own read of a situation.",
      detail: "A longer paragraph about the trait.",
    },
    lines: LINE_KEYS.map((key) => line(key)),
    ...over,
  };
}

Deno.test("a complete payload survives intact and in display order", () => {
  const result = normalisePalmReading(validPayload(), "love");

  assertEquals(result.rejected, null);
  assertEquals(result.lines.length, 8);
  assertEquals(result.lines.map((l) => l.key), [...LINE_KEYS]);
  assertEquals(result.headline, "A warm and curious hand.");
  assertEquals(result.strongestTrait.title, "Independent & Intuitive");
  assertEquals(result.lines[0].meaning.length, 3);
});

Deno.test("lines are reordered to the display order regardless of what the model emitted", () => {
  const shuffled = validPayload({
    lines: ["mars", "sun", "heart", "marriage", "life", "mercury", "head", "fate"]
      .map((key) => line(key)),
  });

  const result = normalisePalmReading(shuffled, "love");

  // Heart, life, head, fate first — the four the results screen leads with.
  assertEquals(result.lines.map((l) => l.key), [...LINE_KEYS]);
});

Deno.test("is_palm false short-circuits and carries the reason", () => {
  const result = normalisePalmReading(
    { is_palm: false, reject_reason: "too_dark" },
    "career",
  );

  assertEquals(result.rejected, "too_dark");
  assertEquals(result.lines.length, 0);
});

Deno.test("an unrecognised reject reason falls back rather than leaking through", () => {
  const result = normalisePalmReading(
    { is_palm: false, reject_reason: "it_was_a_cat" },
    "career",
  );

  assertEquals(result.rejected, "not_a_palm");
});

Deno.test("is_palm true alongside a real reject reason is treated as a rejection", () => {
  // A contradiction. The reason is the more specific signal, so it wins — otherwise a reading
  // written about a photo the model itself flagged as unreadable would be shown as genuine.
  const result = normalisePalmReading(validPayload({ reject_reason: "too_blurry" }), "love");

  assertEquals(result.rejected, "too_blurry");
});

Deno.test("an unknown line key is dropped and the rest are kept", () => {
  const payload = validPayload({
    lines: [...LINE_KEYS.slice(0, 7).map((key) => line(key)), line("girdle_of_venus")],
  });

  const result = normalisePalmReading(payload, "love");

  assertEquals(result.rejected, null);
  assertEquals(result.lines.length, 7);
  assert(!result.lines.some((l) => (l.key as string) === "girdle_of_venus"));
});

Deno.test("a duplicated line key keeps only the first", () => {
  const payload = validPayload({
    lines: [...LINE_KEYS.map((key) => line(key)), line("heart", { title: "Impostor" })],
  });

  const result = normalisePalmReading(payload, "love");

  assertEquals(result.lines.length, 8);
  assertEquals(result.lines[0].title, "heart line");
});

Deno.test("fewer than six usable lines is rejected as incomplete", () => {
  const payload = validPayload({ lines: LINE_KEYS.slice(0, 5).map((key) => line(key)) });

  assertEquals(normalisePalmReading(payload, "love").rejected, "incomplete");
});

Deno.test("exactly six usable lines still ships", () => {
  // The deliberate boundary: after a long wait, six solid lines beat an error.
  const payload = validPayload({ lines: LINE_KEYS.slice(0, 6).map((key) => line(key)) });
  const result = normalisePalmReading(payload, "love");

  assertEquals(result.rejected, null);
  assertEquals(result.lines.length, 6);
});

Deno.test("a line with no detail is dropped, since there is nothing to show", () => {
  const payload = validPayload({
    lines: [...LINE_KEYS.slice(0, 7).map((key) => line(key)), line("mars", { detail: "  " })],
  });

  assertEquals(normalisePalmReading(payload, "love").lines.length, 7);
});

Deno.test("extra bullets are clamped to three and empty ones removed", () => {
  const payload = validPayload({
    lines: LINE_KEYS.map((key) =>
      line(key, { meaning: ["one", "", "two", "three", "four", "five"] })
    ),
  });

  const result = normalisePalmReading(payload, "love");

  assertEquals(result.lines[0].meaning, ["one", "two", "three"]);
});

Deno.test("a missing title falls back to the canonical label", () => {
  const payload = validPayload({
    lines: LINE_KEYS.map((key) => line(key, { title: "" })),
  });

  const result = normalisePalmReading(payload, "love");

  assertEquals(result.lines[0].title, "Heart Line");
  // Never "Health Line" — the reading must not carry a medical framing.
  assertEquals(result.lines.find((l) => l.key === "mercury")?.title, "Mercury Line");
});

Deno.test("an unknown status falls back rather than costing the line", () => {
  const payload = validPayload({
    lines: LINE_KEYS.map((key) => line(key, { status: "Sparkling" })),
  });

  const result = normalisePalmReading(payload, "love");

  assertEquals(result.lines.length, 8);
  assertEquals(result.lines[0].status, "Balanced");
});

Deno.test("overlong text is clamped at a word boundary", () => {
  const payload = validPayload({ headline: `${"word ".repeat(60)}end` });

  const headline = normalisePalmReading(payload, "love").headline;

  assert(headline.length <= 120);
  assert(!headline.endsWith(" "));
  // Clipped at a space, so the last word is whole rather than a fragment.
  assert(headline.endsWith("word"));
});

Deno.test("whitespace and newlines collapse", () => {
  const payload = validPayload({ headline: "A  warm\n\nand   curious hand." });

  assertEquals(normalisePalmReading(payload, "love").headline, "A warm and curious hand.");
});

Deno.test("the server's focus always wins over the model's echo", () => {
  const result = normalisePalmReading(validPayload({ focus_echo: "money" }), "career");

  assertEquals(result.focus, "career");
  assert(focusMismatch(validPayload({ focus_echo: "money" }), "career"));
  assert(!focusMismatch(validPayload({ focus_echo: "career" }), "career"));
});

Deno.test("garbage of every shape is rejected rather than thrown on", () => {
  for (const raw of [null, undefined, "a string", 42, [], {}, { is_palm: "yes" }]) {
    assert(normalisePalmReading(raw, "love").rejected !== null, `failed on ${JSON.stringify(raw)}`);
  }
});

Deno.test("a missing strongest_trait or hand degrades to empty, not a throw", () => {
  const payload = validPayload();
  delete (payload as Record<string, unknown>).strongest_trait;
  delete (payload as Record<string, unknown>).hand;

  const result = normalisePalmReading(payload, "love");

  assertEquals(result.rejected, null);
  assertEquals(result.strongestTrait.title, "");
  assertEquals(result.hand, {});
});

Deno.test("the key is read under either spelling, lowercase preferred", () => {
  const both = geminiSettings(
    new Map([["gemini_api_key", "lower"], ["GEMINI_AI_KEY", "upper"]]),
  );
  assertEquals(both.apiKey, "lower");

  // The row the user created by hand still works.
  assertEquals(geminiSettings(new Map([["GEMINI_AI_KEY", "upper"]])).apiKey, "upper");

  // A placeholder like "-" or "tbd" collapses to empty, so the function fails closed with a
  // configuration log rather than sending a nonsense credential to Google.
  assertEquals(geminiSettings(new Map([["gemini_api_key", "tbd"]])).apiKey, "");

  // Only the backstop for an empty config row — the live value comes from app_config.
  assertEquals(geminiSettings(new Map()).model, "gemini-3.8-flash");
});

Deno.test("the prompt carries the focus and never invents a name", () => {
  const named = buildUserPrompt({ name: "Asha", age: 31, focus: "love" });
  assert(named.includes("Asha"));
  assert(named.includes("31"));
  assert(named.includes("Love & Relationships"));

  const anonymous = buildUserPrompt({ name: null, age: null, focus: "money" });
  assert(anonymous.includes("do not invent one"));
  assert(anonymous.includes("Money & Abundance"));
});
