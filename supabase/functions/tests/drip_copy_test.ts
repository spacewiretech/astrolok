import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";

import { DRIP_ROUTES, DRIP_SLOTS, DripSlot, DripState } from "../_shared/notification_campaigns.ts";
import {
  DRIP_COPY,
  DRIP_POOLS,
  DRIP_VARIANT_KEYS,
  dripVariantFor,
  LOCKED_POOL,
  DripVariantKey,
  istWeekday,
  LUCKY_COLOURS,
  luckyDay,
  PLANET_NAMES,
  renderDripCopy,
  WEEKDAY_LORD,
} from "../_shared/drip_copy.ts";
import { COPY_LANGUAGES } from "../_shared/notification_copy.ts";

const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });
const visible = (text: string) => [...segmenter.segment(text)].length;

/** The script each language must be written in, as `notification_copy_test.ts` requires of the rest. */
const SCRIPT: Record<string, RegExp> = {
  hindi: /\p{Script=Devanagari}/u,
  telugu: /\p{Script=Telugu}/u,
  tamil: /\p{Script=Tamil}/u,
  kannada: /\p{Script=Kannada}/u,
  malayalam: /\p{Script=Malayalam}/u,
};

/** A Wednesday, so `{colour}` renders as the longest-ish colour in most languages. */
const WEDNESDAY = new Date("2026-09-23T06:00:00Z"); // 11:30 IST

Deno.test("every variant has copy in all seven languages, fitting a lock screen", () => {
  for (const variant of DRIP_VARIANT_KEYS) {
    for (const language of COPY_LANGUAGES) {
      const copy = DRIP_COPY[variant][language];
      assert(copy, `${variant}/${language}`);
      assert(copy.title.trim().length > 0 && copy.body.trim().length > 0, `${variant}/${language} empty`);

      // Rendered with the longest plausible fillings: a name, and every weekday's colour and lord.
      for (let day = 0; day < 7; day++) {
        const now = new Date(Date.UTC(2026, 8, 20 + day, 6, 0, 0));
        const rendered = renderDripCopy(variant, language, { name: "Aishwarya", now });
        assert(
          visible(rendered.title) <= 48,
          `${variant}/${language} day ${day} title is ${visible(rendered.title)}: "${rendered.title}"`,
        );
        assert(
          visible(rendered.body) <= 150,
          `${variant}/${language} day ${day} body is ${visible(rendered.body)}`,
        );
      }
    }
  }
});

Deno.test("each language is written in its own script; Hinglish and English stay Roman", () => {
  for (const variant of DRIP_VARIANT_KEYS) {
    for (const [language, script] of Object.entries(SCRIPT)) {
      const { title, body } = DRIP_COPY[variant][language as keyof typeof SCRIPT & typeof COPY_LANGUAGES[number]];
      assert(script.test(title + body), `${variant}/${language} is not in its script`);
    }
    for (const language of ["english", "hinglish"] as const) {
      const { title, body, ask } = DRIP_COPY[variant][language];
      assertFalse(/[ऀ-ൿ]/.test(title + body + (ask ?? "")), `${variant}/${language} has Indic script`);
    }
  }
});

Deno.test("only the three known placeholders are used, and they all fill or disappear cleanly", () => {
  for (const variant of DRIP_VARIANT_KEYS) {
    for (const language of COPY_LANGUAGES) {
      const { title, body, ask } = DRIP_COPY[variant][language];
      const raw = title + body + (ask ?? "");
      assertEquals(
        raw.replace(/\{(name|colour|planet)\}/g, "").includes("{"),
        false,
        `${variant}/${language} uses an unknown placeholder`,
      );

      const named = renderDripCopy(variant, language, { name: "Ravi Kumar", now: WEDNESDAY });
      const unnamed = renderDripCopy(variant, language, { name: null, now: WEDNESDAY });
      for (const text of [named.title, named.body, named.ask, unnamed.title, unnamed.body, unnamed.ask]) {
        if (text === undefined) continue;
        assertFalse(/\{(name|colour|planet)\}/.test(text), `${variant}/${language} left a placeholder: "${text}"`);
        assertFalse(/^[,\s]|,\s*[.!?।]|\s,/.test(text), `${variant}/${language}: "${text}"`);
      }
      // Only the first name reaches a lock screen, exactly as the event copy promises.
      if (raw.includes("{name}")) assert((named.title + named.body).includes("Ravi"));
      assertFalse((named.title + named.body).includes("Kumar"));
    }
  }
});

Deno.test("the seeded question is present exactly where the variant opens chat", () => {
  // Routing decides this, not the variant's name: a variant carries a seeded question exactly when
  // every state that can reach it opens `/chat`. A camera, the kundali form and the paywall have
  // nowhere to put a question, and a question that goes nowhere is worse than none.
  const reachedBy = new Map<DripVariantKey, Set<string>>();
  for (const [slot, states] of Object.entries(DRIP_POOLS)) {
    for (const [state, pool] of Object.entries(states)) {
      for (const variant of pool ?? []) {
        if (!reachedBy.has(variant)) reachedBy.set(variant, new Set());
        reachedBy.get(variant)!.add(DRIP_ROUTES[slot as DripSlot][state as DripState]);
      }
    }
  }
  for (const variant of LOCKED_POOL) reachedBy.set(variant, new Set(["/subscribe"]));

  for (const variant of DRIP_VARIANT_KEYS) {
    const routes = reachedBy.get(variant);
    assert(routes?.size, `${variant} is unreachable — no pool draws it`);
    assertEquals(routes.size, 1, `${variant} is drawn by states that route differently: ${[...routes]}`);
    const opensChat = routes.has("/chat");

    for (const language of COPY_LANGUAGES) {
      const { ask } = DRIP_COPY[variant][language];
      if (opensChat) {
        assert(ask && ask.trim().length > 0, `${variant}/${language} opens chat with no question`);
        assert(ask.trim().endsWith("?"), `${variant}/${language} question is not a question: "${ask}"`);
        // It is typed into the composer, so it has to survive a `TextField` and the 200-char guard
        // the app puts on it.
        assert(ask.trim().length <= 200, `${variant}/${language} question is ${ask.trim().length} chars`);
      } else {
        assertEquals(ask, undefined, `${variant}/${language} carries a question it cannot use`);
      }
    }
  }
});

Deno.test("every variant is drawn by exactly one pool, and every pool is covered", () => {
  const drawn = new Set<string>();
  for (const states of Object.values(DRIP_POOLS)) {
    for (const pool of Object.values(states)) for (const v of pool ?? []) drawn.add(v);
  }
  for (const v of LOCKED_POOL) drawn.add(v);

  // Nothing written but unreachable, and nothing reachable but unwritten.
  for (const variant of DRIP_VARIANT_KEYS) assert(drawn.has(variant), `${variant} is written but never sent`);
  assertEquals(drawn.size, DRIP_VARIANT_KEYS.length);

  // Every slot has a `new` pool: it is what `dripVariantFor` falls back to.
  for (const { slot } of DRIP_SLOTS) {
    assert(DRIP_POOLS[slot].new?.length, `slot ${slot} has no 'new' pool to fall back to`);
  }
});

Deno.test("dripVariantFor is total, and spreads across the pool", () => {
  // SQL hands over a hash. Anything that can come out of a hash must pick a real variant.
  for (const { slot } of DRIP_SLOTS) {
    for (const state of ["new", "ask", "locked"] as const) {
      for (const pick of [0, 1, 7, 268435455, -3, 2 ** 31, Number.NaN, 1.9]) {
        const variant = dripVariantFor(slot, state, pick);
        assert(DRIP_COPY[variant], `${slot}/${state}/${pick} gave "${variant}"`);
      }
      // Locked always draws the locked pool, whatever the slot.
      if (state === "locked") {
        assert((LOCKED_POOL as readonly string[]).includes(dripVariantFor(slot, state, 3)));
      }
    }
  }

  // An `ask` on a slot with no `ask` pool falls back to `new` rather than throwing.
  assert((DRIP_POOLS.today.new as readonly string[]).includes(dripVariantFor("today", "ask", 2)));
  assert((DRIP_POOLS.chat.new as readonly string[]).includes(dripVariantFor("chat", "ask", 5)));

  // Consecutive hashes walk the pool, so a user whose hash moves by one gets different words.
  const seen = new Set(Array.from({ length: 6 }, (_, i) => dripVariantFor("palm", "new", i)));
  assertEquals(seen.size, DRIP_POOLS.palm.new!.length);
});

Deno.test("nothing reaches a lock screen starting in lower case", () => {
  // A placeholder can land in the first position — `{colour}` is a plain noun, "red" or "laal" —
  // and the body would otherwise open mid-sentence. Checked across every weekday, because which
  // colour lands there changes daily, and with and without a name, because stripping one moves the
  // first word too.
  for (const variant of DRIP_VARIANT_KEYS) {
    for (const language of ["english", "hinglish"] as const) {
      for (let day = 0; day < 7; day++) {
        const now = new Date(Date.UTC(2026, 8, 20 + day, 6, 0, 0));
        for (const name of ["Ravi", null]) {
          const c = renderDripCopy(variant, language, { name, now, planet: "saturn" });
          for (const [what, text] of [["title", c.title], ["body", c.body], ["ask", c.ask]] as const) {
            if (!text) continue;
            // Start of the string, and after any sentence-ending punctuation: `{colour}` can land
            // on either, and did on both before `sentenceCase` existed.
            assertFalse(
              /(^|[.!?।]\s+)\p{Ll}/u.test(text),
              `${variant}/${language} day ${day} ${what}: "${text}"`,
            );
          }
        }
      }
    }
  }
});

Deno.test("the weekday table covers every day in every language", () => {
  assertEquals(WEEKDAY_LORD.length, 7);
  for (const language of COPY_LANGUAGES) {
    assertEquals(LUCKY_COLOURS[language].length, 7, `${language} is missing a colour`);
    for (const colour of LUCKY_COLOURS[language]) assert(colour.trim().length > 0);
    // Every graha a kundali can name must be nameable, not just the seven weekday lords: the evening
    // push pulls a planet out of the reader's own chart, and that includes Rahu and Ketu.
    for (const planet of ["sun", "moon", "mars", "mercury", "jupiter", "venus", "saturn", "rahu", "ketu"]) {
      assert(PLANET_NAMES[language][planet]?.trim(), `${language} cannot name ${planet}`);
    }
  }
});

Deno.test("the colour follows the IST date, not the server's", () => {
  // 19:00 UTC on a Tuesday is already Wednesday in IST (00:30), and Wednesday is Mercury's green.
  const lateTuesdayUtc = new Date("2026-09-22T19:00:00Z");
  assertEquals(istWeekday(lateTuesdayUtc), 3);
  assertEquals(luckyDay("english", lateTuesdayUtc), { planet: "Mercury", colour: "green" });

  // …while 18:00 UTC the same day is still Tuesday in IST (23:30), which is Mars and red.
  const tuesdayUtc = new Date("2026-09-22T18:00:00Z");
  assertEquals(istWeekday(tuesdayUtc), 2);
  assertEquals(luckyDay("english", tuesdayUtc), { planet: "Mars", colour: "red" });
});

Deno.test("a chart's own planet overrides the weekday's, and a bad one falls back", () => {
  const saturn = renderDripCopy("evening_ask_0", "english", { name: "Ravi", now: WEDNESDAY, planet: "saturn" });
  assert(saturn.title.includes("Saturn"), saturn.title);
  assert(saturn.ask?.includes("Saturn"), saturn.ask);

  // Wednesday's lord is Mercury, and that is what a missing or nonsense planet falls back to.
  for (const planet of [null, undefined, "", "  ", "nibiru"]) {
    const fallback = renderDripCopy("evening_ask_0", "english", { name: "Ravi", now: WEDNESDAY, planet });
    assert(fallback.title.includes("Mercury"), `${planet}: ${fallback.title}`);
  }

  // Case and padding come from a jsonb param, so they are normalised rather than trusted.
  assert(renderDripCopy("evening_ask_0", "english", { name: null, now: WEDNESDAY, planet: " KETU " }).title.includes("Ketu"));
});

Deno.test("an unknown language falls back to English rather than throwing", () => {
  const copy = renderDripCopy("today_0", "Klingon", { name: "Ravi", now: WEDNESDAY });
  assertEquals(copy.language, "english");
  assert(copy.body.includes("Mercury"));

  assertEquals(renderDripCopy("today_0", null, { name: null, now: WEDNESDAY }).language, "english");
  // The app stores languages capitalised ("Hinglish"); the renderer lowercases before matching.
  assertEquals(renderDripCopy("today_0", "Hinglish", { name: null, now: WEDNESDAY }).language, "hinglish");
});

Deno.test("every slot's variant pool is contiguous from zero", () => {
  // `drip_variant()` in SQL returns `hash % p_count`, so a pool must be 0..n-1 with no gaps — a
  // missing index would render nothing and a gap would send a stale variant.
  const pools = new Map<string, Set<number>>();
  for (const variant of DRIP_VARIANT_KEYS) {
    const match = variant.match(/^(.*)_(\d+)$/);
    assert(match, `${variant} does not end in an index`);
    const [, pool, index] = match;
    if (!pools.has(pool)) pools.set(pool, new Set());
    pools.get(pool)!.add(Number(index));
  }

  for (const [pool, indexes] of pools) {
    const sorted = [...indexes].sort((a, b) => a - b);
    assertEquals(sorted, sorted.map((_, i) => i), `pool ${pool} has a gap: ${sorted.join(",")}`);
  }

  // And every slot in the registry has at least one pool named after it.
  for (const { slot } of DRIP_SLOTS) {
    assert([...pools.keys()].some((pool) => pool === slot || pool.startsWith(`${slot}_`)), `slot ${slot} has no copy`);
  }
});
