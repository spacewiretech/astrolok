import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";

import { EVENT_CAMPAIGN_KEYS } from "../_shared/notification_campaigns.ts";
import { COPY, COPY_LANGUAGES, renderCopy } from "../_shared/notification_copy.ts";

const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });
const visible = (text: string) => [...segmenter.segment(text)].length;

/** The script each language must be written in, as `chat_language.ts` instructs the sage. */
const SCRIPT: Record<string, RegExp> = {
  hindi: /\p{Script=Devanagari}/u,
  telugu: /\p{Script=Telugu}/u,
  tamil: /\p{Script=Tamil}/u,
  kannada: /\p{Script=Kannada}/u,
  malayalam: /\p{Script=Malayalam}/u,
};

Deno.test("every campaign has copy in all seven languages, fitting a lock screen", () => {
  for (const campaign of EVENT_CAMPAIGN_KEYS) {
    for (const language of COPY_LANGUAGES) {
      const copy = COPY[campaign][language];
      assert(copy, `${campaign}/${language}`);
      assert(copy.title.trim().length > 0 && copy.body.trim().length > 0, `${campaign}/${language} empty`);
      const rendered = renderCopy(campaign, language, { name: "Aishwarya" });
      assert(visible(rendered.title) <= 48, `${campaign}/${language} title is ${visible(rendered.title)} long`);
      assert(visible(rendered.body) <= 150, `${campaign}/${language} body is ${visible(rendered.body)} long`);
    }
  }
});

Deno.test("each language is written in its own script; Hinglish and English stay Roman", () => {
  for (const campaign of EVENT_CAMPAIGN_KEYS) {
    for (const [language, script] of Object.entries(SCRIPT)) {
      const { title, body } = COPY[campaign][language as keyof typeof SCRIPT & typeof COPY_LANGUAGES[number]];
      assert(script.test(title + body), `${campaign}/${language} is not in its script`);
    }
    for (const language of ["english", "hinglish"] as const) {
      const { title, body } = COPY[campaign][language];
      assertFalse(/[ऀ-ൿ]/.test(title + body), `${campaign}/${language} has Indic script`);
    }
  }
});

Deno.test("only the {name} placeholder is used, and it always fills or disappears cleanly", () => {
  for (const campaign of EVENT_CAMPAIGN_KEYS) {
    for (const language of COPY_LANGUAGES) {
      const { title, body } = COPY[campaign][language];
      assertEquals((title + body).replace(/\{name\}/g, "").includes("{"), false, `${campaign}/${language}`);

      const named = renderCopy(campaign, language, { name: "Ravi Kumar" });
      const unnamed = renderCopy(campaign, language, { name: null });
      for (const text of [named.title, named.body, unnamed.title, unnamed.body]) {
        assertFalse(text.includes("{name}"), `${campaign}/${language}`);
        assertFalse(/^[,\s]|,\s*[.!?।]|\s,/.test(text), `${campaign}/${language}: "${text}"`);
      }
      if ((title + body).includes("{name}")) assert((named.title + named.body).includes("Ravi"));
      assertFalse((named.title + named.body).includes("Kumar"));
    }
  }
});

Deno.test("a sentence that opened with the name is recapitalised without it", () => {
  assertEquals(
    renderCopy("kundali_ready", "English", {}).body,
    "Your stars have been mapped. Tap to reveal your birth chart and life insights.",
  );
  assertEquals(renderCopy("winback_paid", "english", { name: "" }).title, "We miss you");
});

Deno.test("an unknown or missing language falls back to English and says so", () => {
  assertEquals(renderCopy("dormant", "Marathi", { name: "Asha" }).language, "english");
  assertEquals(renderCopy("dormant", null).language, "english");
  assertEquals(renderCopy("dormant", "  TAMIL ").language, "tamil");
});
