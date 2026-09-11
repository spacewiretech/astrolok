import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  buildUserPrompt,
  FACE_KEYS,
  faceSystemPrompt,
  focusMismatch,
  normaliseFaceReading,
  SYSTEM_PROMPT,
  TRAIT_KEYS,
} from "../_shared/face_reading.ts";

/**
 * `normaliseFaceReading` is the whole correctness surface of the face feature: everything a
 * language model can get wrong about a contract arrives here, and the screen renders whatever
 * comes out. It is pure, so all of it is testable without a key or a network.
 *
 * The bias under test throughout is the same one the palm tests assert: an imperfect reading
 * still ships. After a twenty-second wait, five good sections beat an error page.
 *
 * The prompt tests at the bottom are not decoration. The boundaries are the reason this feature
 * is safe to ship, and a refactor that quietly drops one of them would otherwise be invisible
 * until it reached a user.
 */

function part(key: string, over: Record<string, unknown> = {}) {
  return {
    key,
    title: `${key} title`,
    sanskrit: "Netra",
    status: "Strong",
    summary: "A short summary.",
    detail: "A detailed paragraph about this feature, grounded in what is visible.",
    meaning: ["First bullet.", "Second bullet.", "Third bullet."],
    tip: "A small kind nudge.",
    blessing: "May your sight stay clear.",
    ...over,
  };
}

function validPayload(over: Record<string, unknown> = {}) {
  return {
    is_face: true,
    reject_reason: "none",
    face: {
      face_shape: "oval",
      eye_set: "balanced",
      expression: "calm",
      observations: ["The gaze is steady.", "The forehead is high and open."],
    },
    focus_echo: "love",
    invocation: "Let us sit with what your face is holding.",
    headline: "A calm and watchful face.",
    core_trait: {
      title: "Naturally Intuitive",
      summary: "You sense things deeply and trust your instincts.",
      detail: "A longer paragraph about the trait.",
    },
    traits: ["independent", "observant", "warm", "determined"],
    parts: FACE_KEYS.map((key) => part(key)),
    blessing: "May your calm keep finding you good company.",
    ...over,
  };
}

// ---------------------------------------------------------------- the happy path

Deno.test("a complete payload survives intact and in display order", () => {
  const result = normaliseFaceReading(validPayload(), "love");

  assertEquals(result.rejected, null);
  assertEquals(result.parts.length, 6);
  assertEquals(result.parts.map((p) => p.key), [...FACE_KEYS]);
  assertEquals(result.headline, "A calm and watchful face.");
  assertEquals(result.coreTrait.title, "Naturally Intuitive");
  assertEquals(result.traits, ["independent", "observant", "warm", "determined"]);
  assertEquals(result.parts[0].meaning.length, 3);
});

Deno.test("the invocation and the blessing are carried through", () => {
  const result = normaliseFaceReading(validPayload(), "love");

  assertEquals(result.invocation, "Let us sit with what your face is holding.");
  assertEquals(result.blessing, "May your calm keep finding you good company.");
  assertEquals(result.parts[0].blessing, "May your sight stay clear.");
});

Deno.test("parts are reordered to the display order regardless of what the model emitted", () => {
  const shuffled = validPayload({
    parts: ["eyebrows", "lips", "eyes", "forehead", "nose", "face_shape"]
      .map((key) => part(key)),
  });

  const result = normaliseFaceReading(shuffled, "love");

  // Eyes, face shape, nose, lips first — the four the results screen leads with.
  assertEquals(result.parts.map((p) => p.key), [...FACE_KEYS]);
});

Deno.test("the server's focus wins over the one the model echoed", () => {
  const result = normaliseFaceReading(validPayload({ focus_echo: "money" }), "career");

  assertEquals(result.focus, "career");
  assert(focusMismatch(validPayload({ focus_echo: "money" }), "career"));
  assert(!focusMismatch(validPayload(), "love"));
});

// ---------------------------------------------------------------- degrading, not throwing

Deno.test("an unknown part key is dropped rather than defaulted", () => {
  // Rendering an "Eyes" row for something the model called `cheekbones` would be a reading of
  // the wrong thing. Five correct rows beat six where one lies about its subject.
  const result = normaliseFaceReading(
    validPayload({ parts: [...FACE_KEYS.slice(0, 5), "cheekbones"].map((key) => part(key)) }),
    "love",
  );

  assertEquals(result.rejected, null);
  assertEquals(result.parts.length, 5);
  assert(!result.parts.some((p) => p.key === ("cheekbones" as never)));
});

Deno.test("a duplicated part key is taken once", () => {
  const result = normaliseFaceReading(
    validPayload({ parts: [...FACE_KEYS, "eyes"].map((key) => part(key)) }),
    "love",
  );

  assertEquals(result.parts.length, 6);
});

Deno.test("an unrecognised status defaults rather than costing the section", () => {
  // Losing a whole paragraph the user waited for, over an unfamiliar chip label, would be
  // absurd.
  const result = normaliseFaceReading(
    validPayload({ parts: FACE_KEYS.map((key) => part(key, { status: "Luminous" })) }),
    "love",
  );

  assertEquals(result.parts.length, 6);
  assertEquals(result.parts[0].status, "Balanced");
});

Deno.test("a part with no detail is dropped, and a missing title falls back", () => {
  const result = normaliseFaceReading(
    validPayload({
      parts: [
        part("eyes", { detail: "   " }),
        ...FACE_KEYS.slice(1).map((key) => part(key, { title: "" })),
      ],
    }),
    "love",
  );

  assertEquals(result.parts.length, 5);
  assertEquals(result.parts[0].key, "face_shape");
  assertEquals(result.parts[0].title, "Face Shape");
});

Deno.test("fewer than four readable parts gives up as incomplete", () => {
  // Below four the results screen looks broken rather than short, so this is where the
  // degrade-don't-throw rule stops and a retry is the better answer.
  const result = normaliseFaceReading(
    validPayload({ parts: FACE_KEYS.slice(0, 3).map((key) => part(key)) }),
    "love",
  );

  assertEquals(result.rejected, "incomplete");
  assertEquals(result.parts.length, 0);
});

Deno.test("four readable parts is still a reading", () => {
  const result = normaliseFaceReading(
    validPayload({ parts: FACE_KEYS.slice(0, 4).map((key) => part(key)) }),
    "love",
  );

  assertEquals(result.rejected, null);
  assertEquals(result.parts.length, 4);
});

Deno.test("a malformed payload yields a rejection rather than throwing", () => {
  for (const raw of [null, undefined, "not an object", 42, [], {}]) {
    const result = normaliseFaceReading(raw, "love");
    assertEquals(result.rejected, "not_a_face");
    assertEquals(result.parts.length, 0);
  }
});

Deno.test("bullets beyond the fourth are dropped and blanks removed", () => {
  const result = normaliseFaceReading(
    validPayload({
      parts: FACE_KEYS.map((key) =>
        part(key, { meaning: ["One.", "", "Two.", "Three.", "Four.", "Five."] })
      ),
    }),
    "love",
  );

  assertEquals(result.parts[0].meaning, ["One.", "Two.", "Three.", "Four."]);
});

// ---------------------------------------------------------------- the trait chips

Deno.test("unknown trait words are dropped, because the app draws an icon per trait", () => {
  const result = normaliseFaceReading(
    validPayload({ traits: ["observant", "radiant", "warm", "magnetic"] }),
    "love",
  );

  assertEquals(result.traits, ["observant", "warm"]);
});

Deno.test("duplicate traits are taken once", () => {
  const result = normaliseFaceReading(
    validPayload({ traits: ["warm", "warm", "loyal", "loyal"] }),
    "love",
  );

  assertEquals(result.traits, ["warm", "loyal"]);
});

Deno.test("trait matching is case- and whitespace-tolerant", () => {
  const result = normaliseFaceReading(
    validPayload({ traits: [" Warm ", "OBSERVANT", "Curious", "grounded"] }),
    "love",
  );

  assertEquals(result.traits, ["warm", "observant", "curious", "grounded"]);
});

Deno.test("no more than four traits survive", () => {
  const result = normaliseFaceReading(
    validPayload({ traits: [...TRAIT_KEYS] }),
    "love",
  );

  assertEquals(result.traits.length, 4);
});

Deno.test("a missing traits array is empty rather than fatal", () => {
  const result = normaliseFaceReading(validPayload({ traits: undefined }), "love");

  assertEquals(result.rejected, null);
  assertEquals(result.traits, []);
});

// ---------------------------------------------------------------- rejection

Deno.test("is_face false is a rejection carrying the model's own reason", () => {
  const result = normaliseFaceReading(
    { is_face: false, reject_reason: "too_dark" },
    "love",
  );

  assertEquals(result.rejected, "too_dark");
});

Deno.test("an unrecognised reject reason falls back to not_a_face", () => {
  const result = normaliseFaceReading(
    { is_face: false, reject_reason: "wearing_sunglasses" },
    "love",
  );

  assertEquals(result.rejected, "not_a_face");
});

Deno.test("is_face true alongside a real reason trusts the reason", () => {
  // A contradiction. Believing `is_face` would mean rendering a reading the model itself said
  // it could not give.
  const result = normaliseFaceReading(
    validPayload({ reject_reason: "obstructed" }),
    "love",
  );

  assertEquals(result.rejected, "obstructed");
  assertEquals(result.parts.length, 0);
});

// ---------------------------------------------------------------- clamping

Deno.test("over-long text is clamped at a word boundary", () => {
  const long = "word ".repeat(400).trim();
  const result = normaliseFaceReading(
    validPayload({
      headline: long,
      parts: FACE_KEYS.map((key) => part(key, { detail: long })),
    }),
    "love",
  );

  assert(result.headline.length <= 120);
  assert(result.parts[0].detail.length <= 900);
  // Clamped between words, so nothing ends mid-word.
  assert(!result.headline.endsWith("wor"));
});

Deno.test("a model that answers sanskrit with a whole shloka is cut short", () => {
  // The term renders beside the title on one line. An unbounded value would wrap the row.
  const result = normaliseFaceReading(
    validPayload({
      parts: FACE_KEYS.map((key) => part(key, { sanskrit: "Netra ".repeat(40) })),
    }),
    "love",
  );

  assert(result.parts[0].sanskrit.length <= 32);
});

// ---------------------------------------------------------------- the prompt

Deno.test("the boundaries the feature depends on are actually in the system prompt", () => {
  for (
    const forbidden of [
      "complexion",
      "attractiveness",
      "disability",
      "gemstone",
      "diagnosis",
      "deterministic verbs",
    ]
  ) {
    assert(
      SYSTEM_PROMPT.toLowerCase().includes(forbidden),
      `the system prompt no longer forbids "${forbidden}"`,
    );
  }
});

Deno.test("an English reading still asks for transliteration and not Devanagari", () => {
  // The no-language prompt is what shipped, and it keeps the original rule: a reading written
  // for a Latin-script language must stay in Roman letters so the PDF's real text path is used
  // rather than the rasteriser.
  assert(SYSTEM_PROMPT.includes("Devanagari"));
  assert(!/[ऀ-ॿ]/.test(SYSTEM_PROMPT), "the system prompt contains Devanagari");
});

Deno.test("a reading in another language is told to write in it, script and all", () => {
  // The rule above is a *rendering* constraint, not a stylistic one, and both things it
  // protected are now answered on the client: the export rasterises what the PDF engine cannot
  // shape, and the Listen control hides itself when the device has no voice. So a Hindi reading
  // is written in Hindi rather than transliterated at it.
  const hindi = faceSystemPrompt("Hindi");

  assert(hindi.includes("THE LANGUAGE YOU WRITE IN"));
  assert(hindi.includes("Hindi"));
  assert(
    !hindi.includes("Never write in Devanagari"),
    "the Roman-letters rule survived into a Hindi reading",
  );

  // And the safety layer is untouched by any of it — that is the thing a voice override must
  // never be able to reach.
  assert(hindi.includes("BOUNDARIES — these are absolute"));
  assert(hindi.includes("Never use deterministic verbs"));
});

Deno.test("the user prompt names the focus and every feature to read", () => {
  const prompt = buildUserPrompt({ name: "Asha", age: 31, focus: "career" });

  assert(prompt.includes("Asha"));
  assert(prompt.includes("31"));
  assert(prompt.includes("Career & Purpose"));
  for (const key of FACE_KEYS) assert(prompt.includes(key), `missing ${key}`);
});

Deno.test("an unnamed user is not given an invented name", () => {
  const prompt = buildUserPrompt({ name: null, age: null, focus: "love" });

  assert(prompt.includes("do not invent one"));
});

Deno.test("the rejection policy lists what must not cause a refusal", () => {
  // The list matters more here than for palms: a reader that quietly refuses some faces and not
  // others is a far worse failure than a mediocre reading.
  const prompt = buildUserPrompt({ name: null, age: null, focus: "love" });

  for (const allowed of ["turban", "hijab", "beard", "Spectacles", "bindi"]) {
    assert(prompt.includes(allowed), `the rejection policy no longer excuses "${allowed}"`);
  }
});
