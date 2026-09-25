import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  birthHourAsks,
  buildUserPrompt,
  CHAT_SCHEMA,
  chatSystemPrompt,
  normaliseChatReply,
  promptVersion,
} from "../_shared/astro_chat.ts";
import { chatTiming } from "../_shared/chat_timing.ts";
import {
  BUILT_IN_LANGUAGES,
  detectLanguageSwitch,
  isSupported,
  languageBlock,
  languageInstruction,
  resolveLanguage,
  supportedLanguages,
} from "../_shared/chat_language.ts";
import { AppConfig } from "../_shared/config.ts";
import { computeChart } from "../_shared/jyotish.ts";
import { panditSystemPrompt } from "../_shared/pandit.ts";

/** The prompt as the handler builds it for a default account. */
const SYSTEM_PROMPT = chatSystemPrompt({ language: "Hinglish" });

const config = (rows: Record<string, string>): AppConfig => new Map(Object.entries(rows));

/**
 * `normaliseChatReply` is the whole correctness surface of the chat: everything a language model
 * can get wrong about a contract arrives here, and the screen renders whatever comes out.
 *
 * The bias under test is the one the reading normalisers already follow — an imperfect reply
 * still ships. A chat that shows an error because one field came back odd is worse than one that
 * shows a slightly thinner answer.
 *
 * The prompt tests at the bottom are not decoration. A free-form chat is the surface where the
 * boundaries will actually be tested — by someone asking whether they will recover, or when they
 * will marry — and a refactor that quietly dropped one would be invisible until it reached them.
 */

function reply(over: Record<string, unknown> = {}) {
  return {
    reply: {
      verdict: "Love comes to you through work you already share with someone.",
      title_emoji: "✨",
      title: "Your Love Reading",
      opening: "Your Chandra sits in Rohini, and Rohini does not give its trust quickly.",
      sections: [
        { emoji: "❤️", heading: "Relationship Energy", body: "A steadier season than the last." },
        { emoji: "💞", heading: "Love Opportunities", body: "Through people you already know." },
      ],
      ...(over.reply as Record<string, unknown> ?? {}),
    },
    options: ["What of my career?", "Tell me of Shani"],
    remember: [{ key: "works_as", value: "a schoolteacher in Pune" }],
    ask_for: "none",
    ...over,
  };
}

// ---------------------------------------------------------------- the happy path

Deno.test("a complete reply survives intact", () => {
  const result = normaliseChatReply(reply())!;

  assert(result !== null);
  assertEquals(result.title, "Your Love Reading");
  assertEquals(result.titleEmoji, "✨");
  assertEquals(result.sections.length, 2);
  assertEquals(result.sections[0].heading, "Relationship Energy");
  assertEquals(result.options.length, 2);
  assertEquals(result.remember, [{ key: "works_as", value: "a schoolteacher in Pune" }]);
  assertEquals(result.askFor, "none");
});

Deno.test("ask_for is carried through when the sage asked for something", () => {
  assertEquals(normaliseChatReply(reply({ ask_for: "birth_time" }))!.askFor, "birth_time");
  assertEquals(normaliseChatReply(reply({ ask_for: "birth_place" }))!.askFor, "birth_place");
});

Deno.test("an unrecognised ask_for falls back to none rather than to a control that cannot open", () => {
  assertEquals(normaliseChatReply(reply({ ask_for: "your_shoe_size" }))!.askFor, "none");
  assertEquals(normaliseChatReply(reply({ ask_for: 42 }))!.askFor, "none");
});

// ---------------------------------------------------------------- degrading, not throwing

Deno.test("a reply with no opening is null — it is the one thing that cannot be missing", () => {
  for (const opening of ["", "   ", null, undefined]) {
    assertEquals(normaliseChatReply(reply({ reply: { opening } })), null);
  }
});

Deno.test("a reply with only an opening is still a reply", () => {
  const result = normaliseChatReply({ reply: { opening: "The hour matters here." } })!;

  assert(result !== null);
  assertEquals(result.opening, "The hour matters here.");
  assertEquals(result.title, "");
  assertEquals(result.sections, []);
  assertEquals(result.options, []);
  assertEquals(result.remember, []);
});

Deno.test("the verdict survives normalisation, which is the whole point of it", () => {
  const result = normaliseChatReply(reply())!;

  assertEquals(
    result.verdict,
    "Love comes to you through work you already share with someone.",
  );
});

Deno.test("a reply that lost its verdict still ships, as replies did before the field", () => {
  // The schema requires it, but this function's contract is that it never throws and degrades to
  // less. This case is also every row written before the field existed.
  const result = normaliseChatReply({
    reply: { title: "The Season Ahead", opening: "Guru turns toward your tenth house." },
  })!;

  assert(result !== null);
  assertEquals(result.verdict, "");
  assertEquals(result.opening, "Guru turns toward your tenth house.");
});

Deno.test("a verdict that runs on is clamped rather than shown whole", () => {
  const result = normaliseChatReply({
    reply: { verdict: "word ".repeat(200), opening: "Rohini does not hurry." },
  })!;

  assert(result !== null);
  assert(result.verdict.length <= 200);
});

Deno.test("a verdict is generated before anything it would have to justify", () => {
  // Load-bearing rather than cosmetic: structured output is generated in the order given, so this
  // is what stops the answer becoming a summary of reasoning already written — which is the
  // hedging the field exists to end. A refactor that reordered these would silently undo it.
  const ordering = CHAT_SCHEMA.properties.reply.propertyOrdering;

  assertEquals(ordering[0], "verdict");
  assert(ordering.indexOf("verdict") < ordering.indexOf("opening"));
  assert(CHAT_SCHEMA.properties.reply.required.includes("verdict"));
});

Deno.test("the sage is told to answer before it explains", () => {
  assert(SYSTEM_PROMPT.includes("ANSWER FIRST"));
  assert(SYSTEM_PROMPT.includes("Verdict, then reasons"));
});

Deno.test("a question no chart can settle is answered, not deflected", () => {
  // The past-life question is the one this app is actually asked, and a shrug about the soul
  // being unknowable is what it used to return.
  assert(SYSTEM_PROMPT.includes("WHEN THE QUESTION IS NOT ONE A CHART CAN SETTLE"));
  assert(SYSTEM_PROMPT.includes("does not deflect"));

  // And answering confidently must not have cost the boundaries — the block that stops a
  // confident voice turning into a promise about somebody's marriage or health.
  assert(SYSTEM_PROMPT.includes("BOUNDARIES — these are absolute"));
  assert(SYSTEM_PROMPT.includes("Never use deterministic verbs"));
});

Deno.test("a malformed payload yields null rather than throwing", () => {
  for (const raw of [null, undefined, "not an object", 42, [], {}, { reply: "text" }]) {
    assertEquals(normaliseChatReply(raw), null);
  }
});

Deno.test("sections beyond the third are dropped, and blank ones with them", () => {
  const result = normaliseChatReply(reply({
    reply: {
      opening: "An opening.",
      sections: [
        { emoji: "1", heading: "One", body: "a" },
        { emoji: "2", heading: "", body: "dropped: no heading" },
        { emoji: "3", heading: "Three", body: "" },
        { emoji: "4", heading: "Four", body: "b" },
        { emoji: "5", heading: "Five", body: "c" },
        { emoji: "6", heading: "Six", body: "d" },
      ],
    },
  }))!;

  assertEquals(result.sections.map((s) => s.heading), ["One", "Four", "Five"]);
});

Deno.test("options are capped at four, deduplicated, and blanks removed", () => {
  const result = normaliseChatReply(reply({
    options: ["One", "", "One", "Two", "   ", "Three", "Four", "Five"],
  }))!;

  assertEquals(result.options, ["One", "Two", "Three", "Four"]);
});

Deno.test("a non-array where an array belongs is empty rather than fatal", () => {
  const result = normaliseChatReply(reply({
    options: "not an array",
    remember: "also not",
    reply: { opening: "An opening.", sections: "nor this" },
  }))!;

  assert(result !== null);
  assertEquals(result.options, []);
  assertEquals(result.remember, []);
  assertEquals(result.sections, []);
});

// ---------------------------------------------------------------- the memory

Deno.test("a remembered key that is not a slug is dropped", () => {
  // The key is a primary key: it is what makes a fact correct itself rather than accumulate. A
  // sentence in that column would mean the same fact never overwrites, and the prompt would fill
  // with contradictions.
  const result = normaliseChatReply(reply({
    remember: [
      { key: "works_as", value: "a teacher" },
      { key: "They work as a teacher", value: "no" },
      { key: "9_leading_digit", value: "no" },
      { key: "has-hyphen", value: "no" },
      { key: "", value: "no" },
    ],
  }))!;

  assertEquals(result.remember, [{ key: "works_as", value: "a teacher" }]);
});

Deno.test("a key of more than three words is prose, not a key", () => {
  // Slugifying alone would let "They work as a teacher" through as a technically valid key —
  // one that can never be produced identically twice, and so can never overwrite itself.
  for (const key of ["they_work_as_a_teacher", "what_she_said_about_work", "a_b_c_d"]) {
    const result = normaliseChatReply(reply({ remember: [{ key, value: "x" }] }))!;
    assertEquals(result.remember, [], `let "${key}" through`);
  }

  // Three is still a key.
  const ok = normaliseChatReply(reply({
    remember: [{ key: "worries_about_money", value: "x" }],
  }))!;
  assertEquals(ok.remember.length, 1);
});

Deno.test("a key in capitals is lowercased rather than discarded", () => {
  // Case is not a mistake worth losing a fact over; it is the same key shouted.
  const result = normaliseChatReply(reply({
    remember: [{ key: "Works_As", value: "a teacher" }],
  }))!;

  assertEquals(result.remember, [{ key: "works_as", value: "a teacher" }]);
});

Deno.test("a key with spaces is slugified rather than discarded", () => {
  // The model writes "works as" often enough that recovering it is worth more than being strict.
  const result = normaliseChatReply(reply({
    remember: [{ key: "works as", value: "a teacher" }],
  }))!;

  assertEquals(result.remember, [{ key: "works_as", value: "a teacher" }]);
});

Deno.test("a fact with no value is dropped, and duplicate keys are taken once", () => {
  const result = normaliseChatReply(reply({
    remember: [
      { key: "lives_in", value: "" },
      { key: "works_as", value: "a teacher" },
      { key: "works_as", value: "a different answer" },
    ],
  }))!;

  assertEquals(result.remember, [{ key: "works_as", value: "a teacher" }]);
});

Deno.test("no more than five facts survive one turn", () => {
  const result = normaliseChatReply(reply({
    remember: Array.from({ length: 9 }, (_, i) => ({ key: `fact_${i}`, value: "x" })),
  }))!;

  assertEquals(result.remember.length, 5);
});

// ---------------------------------------------------------------- clamping

Deno.test("over-long text is clamped at a word boundary", () => {
  const long = "word ".repeat(500).trim();
  const result = normaliseChatReply({
    reply: {
      title: long,
      opening: long,
      sections: [{ heading: long, body: long }],
    },
    options: [long],
  })!;

  assert(result.title.length <= 80);
  assert(result.opening.length <= 900);
  assert(result.sections[0].body.length <= 400);
  assert(result.options[0].length <= 60);
  assert(!result.title.endsWith("wor"), "clipped mid-word");
});

Deno.test("an emoji field holding a sentence is cut without splitting a surrogate pair", () => {
  // Most emoji are surrogate pairs, so a naive slice(0, 2) leaves half a character and the
  // screen shows a replacement box.
  const result = normaliseChatReply(reply({
    reply: {
      opening: "An opening.",
      title_emoji: "✨💫🌙 and then some words",
      sections: [{ emoji: "❤️", heading: "H", body: "b" }],
    },
  }))!;

  assert([...result.titleEmoji].length <= 2);
  assert(!result.titleEmoji.includes("�"), "broke a surrogate pair");
  assertEquals(result.sections[0].emoji, "❤️");
});

Deno.test("a missing emoji is empty rather than a placeholder", () => {
  const result = normaliseChatReply({
    reply: { opening: "An opening.", sections: [{ heading: "H", body: "b" }] },
  })!;

  assertEquals(result.titleEmoji, "");
  assertEquals(result.sections[0].emoji, "");
});

// ---------------------------------------------------------------- the prompt

Deno.test("the boundaries the feature depends on are actually in the system prompt", () => {
  // A chat can be asked anything by anyone. These are the lines that stop the answer being a
  // medical opinion or a dated promise.
  for (
    const forbidden of [
      "health",
      "diagnosis",
      "deterministic verbs",
      "gemstone",
      "caste",
      "complexion",
    ]
  ) {
    assert(
      SYSTEM_PROMPT.toLowerCase().includes(forbidden),
      `the system prompt no longer forbids "${forbidden}"`,
    );
  }
});

Deno.test("the grounding rule is the chat one, not the photograph one", () => {
  // `GROUNDING` in pandit.ts is written entirely around an image. If it leaked back in, the sage
  // would be told to describe what it can genuinely see, having been given nothing to look at.
  //
  // Asserted on that block's own distinctive phrases rather than on the word "photograph", which
  // legitimately appears once in the shared PANDIT_VOICE and is a harmless no-op here.
  assert(!SYSTEM_PROMPT.includes("fill in the observation object"));
  assert(!SYSTEM_PROMPT.includes("genuinely see in the photograph"));

  assert(SYSTEM_PROMPT.includes("HOW TO GROUND A READING"));
  assert(SYSTEM_PROMPT.includes("could have been sent to any stranger"));
});

Deno.test("the reply is written in the language the turn asked for", () => {
  for (const language of BUILT_IN_LANGUAGES) {
    const prompt = chatSystemPrompt({ language });
    assert(prompt.includes("THE LANGUAGE YOU WRITE IN"));
    assert(prompt.includes(language), `the prompt never names ${language}`);
  }
});

Deno.test("a language the dashboard invented still produces a usable instruction", () => {
  // The whole point of keeping the list in `app_config` is that adding Marathi is a dashboard
  // edit. That is only true if an unrecognised name reaches the model as an instruction rather
  // than as a gap.
  const prompt = chatSystemPrompt({ language: "Marathi" });
  assert(prompt.includes("Write your whole reply in Marathi"));
  assert(prompt.includes("the script Marathi is normally written in"));
});

Deno.test("the person outranks the setting", () => {
  // Someone who types in English gets English back whatever they picked. Without this the
  // picker becomes a trap for anyone who switches language mid-conversation.
  assert(SYSTEM_PROMPT.includes("answer in the language they wrote in"));
  assert(SYSTEM_PROMPT.includes("the person in front of you outranks the setting"));
});

Deno.test("only Hindi is allowed Devanagari, and only in the chat", () => {
  // The Roman-letters rule exists for the PDF's Latin-only font subset and for a TTS that reads
  // Devanagari as silence. The chat has neither, so it is the one surface that can carry the
  // script — and palm and face must keep the rule they still depend on.
  const hindi = chatSystemPrompt({ language: "Hindi" });
  assert(/[ऀ-ॿ]/.test(hindi), "the Hindi prompt shows no Devanagari to write in");

  for (const language of ["Hinglish", "English"]) {
    const prompt = chatSystemPrompt({ language });
    assert(
      prompt.includes("Never Devanagari") || !/[ऀ-ॿ]/.test(prompt),
      `${language} was not told to stay in Roman letters`,
    );
  }

  const reading = panditSystemPrompt({ craft: "-", lengths: "-" });
  assert(
    reading.includes("Never write in Devanagari"),
    "palm and face lost the rule their PDF and TTS depend on",
  );
});

// ---------------------------------------------------------------- the rollback

Deno.test("v1 is still reachable, and is the text that shipped", () => {
  // The rollback is only worth having if it has been checked. These are phrases unique to each
  // version, so a merge that quietly collapsed the two would fail here rather than in production.
  const v1 = chatSystemPrompt({ version: "v1", language: "Hinglish" });
  assert(v1.includes("only one thing, only when the conversation makes room for it"));
  assert(!v1.includes("EFFORT IS PART OF THE READING"));
  assert(!v1.includes("THE LANGUAGE YOU WRITE IN"));
  // v1 rolls back the voice too, Roman-letters rule included.
  assert(v1.includes("Never write in Devanagari"));

  const v2 = chatSystemPrompt({ version: "v2", language: "Hinglish" });
  assert(v2.includes("EFFORT IS PART OF THE READING"));
  assert(v2.includes('WHEN THEY ASK "WHEN"'));
});

Deno.test("an unset or misspelled version is treated as current", () => {
  // `configSetting` hands over "" for a blank cell, and a dashboard is a text box. Neither may
  // silently strand every user on the old prompt.
  for (const version of ["", "  ", "V4", "v5", "latest"]) {
    assert(
      chatSystemPrompt({ version, language: "English" }).includes("THE TIMING block"),
      `version "${version}" did not fall through to v4`,
    );
  }
});

Deno.test("v2 answers the question v1 dodged", () => {
  // The reply that prompted this: "ky me army ma kab bharti hungi", answered with a remark about
  // looking at your energy rather than estimating a time. Each assertion is one half of that
  // failure — no answer, and no mention of the work. Pinned to v3, which is where this text lives
  // now that v4 answers with a window.
  const prompt = chatSystemPrompt({ version: "v3", language: "Hinglish" });

  assert(prompt.includes("Never write that the chart cannot tell them when"));
  assert(prompt.includes("answer in conditions, not dates"));
  assert(prompt.includes("something they can begin this week"));
  assert(prompt.includes('set "ask_for" to "birth_time"'));

  // And the boundary it must not have crossed to get there.
  assert(prompt.includes("Never give a date, a year"));
});

// ---------------------------------------------------------------- the languages

Deno.test("the language list comes from config, cleaned up", () => {
  const languages = supportedLanguages(config({
    chat_languages: " Hinglish , English ,, Hindi , hindi ,Marathi ",
  }));

  // Blanks dropped, whitespace trimmed, duplicates removed case-insensitively, order kept.
  assertEquals(languages, ["Hinglish", "English", "Hindi", "Marathi"]);
});

Deno.test("a missing or blank language list falls back to the built-ins", () => {
  // Blank is the documented off switch for the picker, but the sage still has to be told
  // something — an unconfigured project must not start answering in whatever it feels like.
  const cases: Record<string, string>[] = [
    {},
    { chat_languages: "" },
    { chat_languages: "  " },
    { chat_languages: "-" },
  ];

  for (const rows of cases) {
    assertEquals(supportedLanguages(config(rows)), [...BUILT_IN_LANGUAGES]);
  }
});

Deno.test("a stored language that has been retired falls back to the default", () => {
  const rows = config({
    chat_languages: "English,Hindi",
    chat_language_default: "Hindi",
  });

  assertEquals(resolveLanguage("English", rows), "English");
  // Hinglish is gone from the list; honouring it would name a language nothing supports.
  assertEquals(resolveLanguage("Hinglish", rows), "Hindi");
  assertEquals(resolveLanguage(null, rows), "Hindi");
  assertEquals(resolveLanguage("  ", rows), "Hindi");
});

Deno.test("a default that is not in the list loses to the first entry", () => {
  // A dashboard can be edited into this state in one keystroke, and the sage still has to be
  // told a language.
  const rows = config({
    chat_languages: "English,Hindi",
    chat_language_default: "Tamil",
  });

  assertEquals(resolveLanguage(null, rows), "English");
});

Deno.test("a stored language is matched however it was typed", () => {
  const rows = config({ chat_languages: "Hinglish,English,Hindi" });

  assertEquals(resolveLanguage("hindi", rows), "Hindi");
  assertEquals(resolveLanguage(" HINDI ", rows), "Hindi");
  assert(isSupported("english", rows));
  assert(!isSupported("Klingon", rows));
});

Deno.test("Hinglish is described as people actually write it", () => {
  // The failing example was Hinglish typed in Roman letters. If this drifts into "Hindi", the
  // reply comes back in a script the person did not write in.
  const hinglish = languageInstruction("Hinglish");
  assert(hinglish.includes("Roman letters"));
  assert(hinglish.includes("Never Devanagari"));
});

Deno.test("the sage is told not to invent planets it was not given", () => {
  // It has the Moon and the Sun. Everything else would be fabrication dressed as computation,
  // which is precisely the failure the computed chart exists to prevent.
  assert(SYSTEM_PROMPT.includes("Never invent a planetary position"));
});

// ---------------------------------------------------------------- the user prompt

Deno.test("the user prompt carries the chart, the facts and the question", () => {
  const prompt = buildUserPrompt("Will I find love?", {
    name: "Asha",
    age: 29,
    chart: computeChart({ dob: "1996-04-12", birthTime: "07:30" }),
    facts: [{ key: "works_as", value: "a teacher" }],
    opening: false,
  });

  assert(prompt.includes("Asha"));
  assert(prompt.includes("29"));
  assert(prompt.includes("Moon (Chandra)"));
  assert(prompt.includes("works_as: a teacher"));
  assert(prompt.includes("Will I find love?"));
});

Deno.test("an unknown birth time tells the sage to ask rather than to invent a nakshatra", () => {
  const prompt = buildUserPrompt("Tell me of the year ahead.", {
    name: "Asha",
    chart: computeChart({ dob: "1996-04-12" }),
    facts: [],
    opening: false,
  });

  assert(prompt.includes("UNKNOWN"));
  assert(prompt.includes("Do not name one"));
});

Deno.test("a user with no date of birth gets no invented chart", () => {
  const prompt = buildUserPrompt("Hello.", {
    name: "Asha",
    chart: null,
    facts: [],
    opening: false,
  });

  assert(prompt.includes("unavailable"));
  assert(prompt.includes("do not pretend to a chart you do not have"));
});

Deno.test("an unnamed user is not given an invented name", () => {
  const prompt = buildUserPrompt("Hello.", {
    name: null,
    chart: null,
    facts: [],
    opening: true,
  });

  assert(prompt.includes("Do not invent one"));
});

Deno.test("the first turn is marked as a greeting, and later ones are not", () => {
  const first = buildUserPrompt("Hello.", {
    name: "Asha",
    chart: null,
    facts: [],
    opening: true,
  });
  const later = buildUserPrompt("Hello.", {
    name: "Asha",
    chart: null,
    facts: [],
    opening: false,
  });

  assert(first.includes("first thing you have ever said"));
  assert(!later.includes("first thing you have ever said"));
});

Deno.test("a reading the user has had is offered to the sage", () => {
  const prompt = buildUserPrompt("What does my hand say?", {
    name: "Asha",
    chart: null,
    facts: [],
    palmSummary: "Their palm reading said: A grounded, loyal hand.",
    opening: false,
  });

  assert(prompt.includes("THEIR READINGS SO FAR"));
  assert(prompt.includes("A grounded, loyal hand"));
});

Deno.test("an empty memory says so, rather than leaving the sage to assume", () => {
  const prompt = buildUserPrompt("Hello.", {
    name: "Asha",
    chart: null,
    facts: [],
    opening: false,
  });

  assert(prompt.includes("You know nothing about their life yet"));
});

Deno.test("a chart corrected since the sage last saw it is named, so the sage can say so", () => {
  const prompt = buildUserPrompt("Meri shaadi kab hogi?", {
    name: "Prashant",
    chart: computeChart({ dob: "1999-10-17", birthTime: "23:55" }),
    chartCorrection: { from: "Dhanu", to: "Makara" },
    facts: [],
    opening: false,
  });

  assert(prompt.includes("THE CHART HAS CHANGED"));
  assert(prompt.includes("placed Chandra in Dhanu"));
  assert(prompt.includes("read from Makara"));
});

Deno.test("a rashi they already know is reconciled with the chart, not argued with", () => {
  const chart = computeChart({ dob: "1999-10-17", birthTime: "23:55" });

  const agrees = buildUserPrompt("Hello.", { chart, statedRashi: "Makar", facts: [], opening: false });
  assert(agrees.includes("agrees with the chart"));

  const differs = buildUserPrompt("Hello.", { chart, statedRashi: "Dhanu", facts: [], opening: false });
  assert(differs.includes("naam rashi"));
  assert(differs.includes("read from Makara"));
});

Deno.test("a birth time without morning or night is asked about, not used", () => {
  const prompt = buildUserPrompt("Hello.", {
    chart: computeChart({ dob: "1999-10-17" }),
    unsettledBirthTime: "11:55",
    facts: [],
    opening: false,
  });

  assert(prompt.includes('A BIRTH TIME OF "11:55" WITHOUT SAYING MORNING OR NIGHT'));
  assert(prompt.includes('set "ask_for" to\n"birth_time"') || prompt.includes('"ask_for" to "birth_time"'));
});

Deno.test("the dasha reaches the user prompt only when asked for", () => {
  const chart = computeChart({
    dob: "1999-10-17",
    birthTime: "23:55",
    asOf: new Date("2026-09-14T00:00:00Z"),
  });

  assert(buildUserPrompt("Hello.", { chart, dasha: true, facts: [], opening: false }).includes("Mahadasha"));
  assert(!buildUserPrompt("Hello.", { chart, facts: [], opening: false }).includes("Mahadasha"));
});

Deno.test("a rashi they state is remembered under one key, spelled one way", () => {
  const normalised = normaliseChatReply(reply({
    remember: [
      { key: "moon_sign", value: "Makar rashi" },
      { key: "naam_rashi", value: "मीन" },
    ],
  }))!;

  assertEquals(normalised.remember, [
    { key: "rashi", value: "Makara" },
    { key: "naam_rashi", value: "Meena" },
  ]);
});

Deno.test("a rashi nobody can read is kept as they said it", () => {
  const normalised = normaliseChatReply(reply({
    remember: [{ key: "rashi", value: "the one my grandmother told me" }],
  }))!;

  assertEquals(normalised.remember, [{ key: "rashi", value: "the one my grandmother told me" }]);
});

// ---------------------------------------------------------------- v3

Deno.test("v3 reads the dasha, and v2 was never told what one is", () => {
  const v3 = chatSystemPrompt({ version: "v3", language: "Hinglish" });
  assert(v3.includes("THE DASHA."));
  assert(v3.includes("The chart outranks anything said about it earlier"));
  assert(v3.includes("THE RASHI THEY ALREADY KNOW"));

  const v2 = chatSystemPrompt({ version: "v2", language: "Hinglish" });
  assert(!v2.includes("THE DASHA."));
  assert(v2.includes("you have the Moon and the Sun, and nothing else"));
});

Deno.test("v3 and v4 permit a narrow remedy, and still forbid the gemstone", () => {
  for (const version of ["v3", "v4"]) {
    const prompt = chatSystemPrompt({ version, language: "Hinglish" });

    assert(prompt.includes("A remedy is allowed within narrow limits"), version);
    assert(prompt.includes("Never a gemstone"), version);
    assert(prompt.includes("Never a fast without food or water"), version);
    assert(!prompt.includes("never a remedy, gemstone, ritual, fast or charm"), version);
  }
});

Deno.test("rolling back to v2 withdraws the remedies with it", () => {
  const v2 = chatSystemPrompt({ version: "v2", language: "Hinglish" });

  assert(v2.includes("never a remedy, gemstone, ritual, fast or charm"));
  assert(!v2.includes("A remedy is allowed"));
});

Deno.test("the version cell is read forgivingly, and lands on v4", () => {
  for (const raw of [undefined, null, "", "  ", "V4", "v5", "latest"]) {
    assertEquals(promptVersion(raw), "v4", `"${raw}" did not land on v4`);
  }
  assertEquals(promptVersion(" V3 "), "v3");
  assertEquals(promptVersion(" V2 "), "v2");
  assertEquals(promptVersion("v1"), "v1");
});

// ---------------------------------------------------------------- v4

/**
 * v4 exists because of a review of one-star conversations on v3. Each test below is one of its
 * findings, asserted where it lives, so a later edit that quietly undid one fails here first.
 */

const V4 = chatSystemPrompt({ version: "v4", language: "Hinglish" });
const V3 = chatSystemPrompt({ version: "v3", language: "Hinglish" });

Deno.test("v4 answers 'when' with a window, and only with one the dasha computed", () => {
  assert(V4.includes('WHEN THEY ASK "WHEN"'));
  assert(V4.includes("Put the window in the verdict"));
  assert(V4.includes("Give the same window every time they ask"));
  assert(V4.includes("Never a year the block does not give"));

  // The gate that answered "shaadi kab hogi" with "the door opens once you are settled" is gone.
  assert(!V4.includes("answer in conditions, not dates"));
  assert(!V4.includes("Name the gate, and the timing has been answered honestly"));
});

Deno.test("v4 swaps the no-years bullet for a narrow one, and keeps the rest of BOUNDARIES", () => {
  assert(V4.includes("A window of years may be named only when THE TIMING block"));
  assert(V4.includes("never as a promise"));
  assert(V4.includes("Never give a date or an age"));
  assert(!V4.includes("Never give a date, a year"));

  // Everything else in the safety layer is where it was.
  for (
    const kept of [
      "Never guarantee an outcome",
      "Never mention health, illness, diagnosis, recovery, fertility, pregnancy",
      "Never use deterministic verbs",
      "caste",
      "Never a gemstone",
    ]
  ) {
    assert(V4.includes(kept), `v4 lost "${kept}"`);
  }
});

Deno.test("palm, face and v3 still name no year at all", () => {
  // They carry no computed timing, so any year they named would be invented.
  const reading = panditSystemPrompt({ craft: "-", lengths: "-" });
  assert(reading.includes("Never give a date, a year"));
  assert(!reading.includes("THE TIMING block"));

  assert(V3.includes("Never give a date, a year"));
  assert(!V3.includes("THE TIMING block"));
});

Deno.test("v4 leads with hope, and never frightens", () => {
  assert(V4.includes("THEY CAME FOR AN ANSWER AND FOR HOPE"));
  assert(V4.includes("Lead with what is good in the chart"));
  assert(V4.includes("A difficulty is a season, never a sentence"));
  assert(V4.includes("Never frighten"));
  // And hope stays on the right side of a promise.
  assert(V4.includes("Hope is not a promise"));
});

Deno.test("v4 says each thing once, and shortens everything but the verdict", () => {
  assert(V4.includes("SAY EACH THING ONCE"));
  assert(V4.includes("The verdict is said once"));
  assert(V4.replace(/\s+/g, " ").includes("do not describe it again"));

  // The verdict budget is v3's, untouched; everything below it is smaller.
  assert(V4.includes("verdict: at most 25 words"));
  assert(V4.includes("opening: 20-35 words"));
  assert(V4.includes("At most two sections"));
  assert(V3.includes("opening: 45-75 words"), "the rollback's budgets moved");
});

Deno.test("v4 glosses a term once per conversation, not once per section", () => {
  assert(V4.includes("the first time it\n  appears in this conversation, and never again"));
  assert(!V4.includes("ONCE per section"));
  assert(V3.includes("ONCE per section"), "the rollback's voice moved");
});

Deno.test("v4 neither argues with a doubter nor tells anyone their rashi is wrong", () => {
  assert(V4.includes("WHEN THEY DOUBT YOU"));
  assert(V4.includes("Do not defend jyotish"));
  assert(V4.includes('never write "X, not Y"'));
});

Deno.test("v4 asks for a missing detail once, and not for the place at all", () => {
  assert(V4.includes("at most once in a conversation"));
  assert(V4.includes("never as a section of its own"));
  assert(V4.includes("Do not ask where they were born"));
});

Deno.test("v4 Hindi and Hinglish name the plain word to use", () => {
  const hindi = chatSystemPrompt({ version: "v4", language: "Hindi" });
  assert(hindi.includes("शादी not विवाह"));
  assert(hindi.includes("if they wrote शादी or shaadi, write शादी"));

  assert(V4.includes("shaadi not vivah"));
  assert(V4.includes("Never Devanagari"), "plain Hinglish lost its script rule");

  // v3 and the readings keep the instruction they shipped with.
  assert(!chatSystemPrompt({ version: "v3", language: "Hindi" }).includes("शादी not विवाह"));
  assert(!languageBlock("Hindi").includes("शादी not विवाह"));
});

Deno.test("every v4 language is told to use everyday words, a dashboard one included", () => {
  for (const language of [...BUILT_IN_LANGUAGES, "Marathi"]) {
    const prompt = chatSystemPrompt({ version: "v4", language });
    assert(prompt.includes("everyday words of someone chatting on a phone"), language);
  }

  const marathi = chatSystemPrompt({ version: "v4", language: "Marathi" });
  assert(marathi.includes("Write your whole reply in Marathi"));
});

// ---------------------------------------------------------------- v4, the user prompt

const V4_AS_OF = new Date("2026-09-24T10:00:00Z");

Deno.test("a v4 prompt with the hour carries THE TIMING, with years in it", () => {
  const dob = "1999-10-17";
  const chart = computeChart({ dob, birthTime: "23:55", asOf: V4_AS_OF });
  const prompt = buildUserPrompt("Meri shaadi kab hogi?", {
    chart,
    dasha: true,
    version: "v4",
    timing: chatTiming(chart, { dob, asOf: V4_AS_OF }),
    birthHourAsks: { asked: 0, declined: false },
    facts: [],
    opening: false,
  });

  assert(prompt.includes("THE TIMING (computed from their Vimshottari dasha"));
  assert(prompt.includes("today is September 2026"));
  assert(/Marriage[^\n]*\b20\d\d\b/.test(prompt), "no year reached the marriage line");
  assert(!prompt.includes("Never give the year"), "the chart line still forbids the years");
  // The hour is known, so nothing about asking for it.
  assert(!prompt.includes("THE HOUR OF BIRTH"));
});

Deno.test("a v4 prompt without the hour says the timing is unknown, rather than saying nothing", () => {
  const prompt = buildUserPrompt("Meri shaadi kab hogi?", {
    chart: computeChart({ dob: "1996-04-12", asOf: V4_AS_OF }),
    dasha: true,
    version: "v4",
    timing: null,
    birthHourAsks: { asked: 0, declined: false },
    facts: [],
    opening: false,
  });

  assert(prompt.includes("THE TIMING: UNKNOWN"));
  assert(prompt.includes("Name no year"));
  assert(prompt.includes("you have not asked for it in this conversation. You may ask once"));
});

Deno.test("a v4 prompt never asks for the hour a second time", () => {
  const base = {
    chart: computeChart({ dob: "1996-04-12", asOf: V4_AS_OF }),
    version: "v4",
    timing: null,
    facts: [],
    opening: false,
  };

  const asked = buildUserPrompt("Naukri kab lagegi?", {
    ...base,
    birthHourAsks: { asked: 1, declined: false },
  });
  assert(asked.includes("You have already asked for it in this conversation"));
  assert(asked.includes("Do not ask again"));
  assert(!asked.includes("You may ask once"));

  const declined = buildUserPrompt("Naukri kab lagegi?", {
    ...base,
    birthHourAsks: { asked: 1, declined: true },
  });
  assert(declined.includes("they have told you they do not know it"));

  // Nor may a half-given time be chased once they have said they do not know.
  const unsettled = buildUserPrompt("Hello.", {
    ...base,
    unsettledBirthTime: "11:55",
    birthHourAsks: { asked: 1, declined: true },
  });
  assert(!unsettled.includes("WITHOUT SAYING MORNING OR NIGHT"));

  // But the one follow-up that settles a time they did give is still allowed.
  const followUp = buildUserPrompt("Hello.", {
    ...base,
    unsettledBirthTime: "11:55",
    birthHourAsks: { asked: 1, declined: false },
  });
  assert(followUp.includes("WITHOUT SAYING MORNING OR NIGHT"));
});

Deno.test("v4 does not ask where they were born", () => {
  const prompt = buildUserPrompt("Hello.", {
    chart: null,
    version: "v4",
    timing: null,
    facts: [],
    opening: false,
  });

  assert(prompt.includes("the place changes nothing in it, so do not ask for it"));
  assert(!prompt.includes('"ask_for" to "birth_place"'));
});

Deno.test("a prompt that names no version gets none of v4's blocks", () => {
  // The rollback must not be handed a timing block its craft was never told how to read.
  const chart = computeChart({ dob: "1999-10-17", birthTime: "23:55", asOf: V4_AS_OF });
  const prompt = buildUserPrompt("Meri shaadi kab hogi?", {
    chart,
    dasha: true,
    facts: [],
    opening: false,
  });

  assert(!prompt.includes("THE TIMING"));
  assert(!prompt.includes("THE HOUR OF BIRTH"));
  assert(prompt.includes("Never give the year"));
});

// ---------------------------------------------------------------- counting the asks

/** A thread as the handler reads it: newest first. */
function thread(...turns: Array<["user", string] | ["astro", string]>) {
  return turns
    .map(([role, value]) =>
      role === "user" ? { role, body: { text: value } } : { role, body: { ask_for: value } }
    )
    .reverse();
}

Deno.test("each reply that asked for the hour is counted", () => {
  const recent = thread(
    ["user", "Meri shaadi kab hogi?"],
    ["astro", "birth_time"],
    ["user", "Aur naukri?"],
    ["astro", "birth_time"],
    ["user", "Paisa?"],
    ["astro", "none"],
  );

  assertEquals(birthHourAsks(recent, "Ghar kab?"), { asked: 2, declined: false });
});

Deno.test("an 'I do not know' after an ask is a decline, however it is typed", () => {
  for (
    const said of [
      "I do not know",
      "i dont know",
      "time pata nahi",
      "janam tithi yaad nahi ha",
      "मुझे नहीं पता",
      "ಟೈಮ್ ಗೊತ್ತಿಲ್ಲ ಗುರುಗಳೇ",
      "నాకు పుట్టిన సమయం తెలీదు",
    ]
  ) {
    const recent = thread(["user", "Shaadi kab?"], ["astro", "birth_time"], ["user", said], [
      "astro",
      "none",
    ]);
    assertEquals(birthHourAsks(recent, "Aur?").declined, true, `"${said}" was not a decline`);
  }
});

Deno.test("the message being answered can be the decline", () => {
  const recent = thread(["user", "Shaadi kab?"], ["astro", "birth_time"]);
  assertEquals(birthHourAsks(recent, "I do not know"), { asked: 1, declined: true });
});

Deno.test("not knowing something else is not declining the hour", () => {
  // Only an answer to an ask counts; "pata nahi kya karu" on its own is a feeling, not a reply.
  const recent = thread(["user", "Pata nahi kya karu"], ["astro", "none"]);
  assertEquals(birthHourAsks(recent, "pata nahi"), { asked: 0, declined: false });
});

// ---------------------------------------------------------------- noticing a switch

const OFFERED = config({ chat_languages: "Hinglish,English,Hindi" });

Deno.test("a message written in Devanagari moves the conversation into Hindi", () => {
  // The exchange that prompted this: Devanagari in, Hinglish out, three turns running.
  assertEquals(detectLanguageSwitch("मेरी शादी कब होगी?", OFFERED), {
    language: "Hindi",
    explicit: false,
  });
});

Deno.test("asking for Hindi in words is heard, in either script", () => {
  for (
    const said of [
      "Hindi me bat kre",
      "hindi mein baat karo please",
      "हिंदी में बताए",
      "हिन्दी",
      "Hindi please",
    ]
  ) {
    assertEquals(
      detectLanguageSwitch(said, OFFERED),
      { language: "Hindi", explicit: true },
      `"${said}" was not heard as a request`,
    );
  }
});

Deno.test("asking for English is heard too, and the later of two requests wins", () => {
  assertEquals(detectLanguageSwitch("Please reply in English", OFFERED)?.language, "English");
  assertEquals(
    detectLanguageSwitch("hindi me bataya tha, ab english me baat karo", OFFERED)?.language,
    "English",
  );
});

Deno.test("Roman letters decide nothing, and one Devanagari word does not either", () => {
  for (const said of ["When will I get a job?", "meri shaadi kab hogi", "meri shaadi kab hogi भाई"]) {
    assertEquals(detectLanguageSwitch(said, OFFERED), null, `"${said}" switched the language`);
  }
});

Deno.test("naming a language is not asking for it", () => {
  for (
    const said of [
      "mera hindi me result kharab aaya, kya karu",
      "Hindi me mat bolo",
      "I teach English at a school in Pune",
    ]
  ) {
    assertEquals(detectLanguageSwitch(said, OFFERED), null, `"${said}" switched the language`);
  }
});

Deno.test("a language the dashboard does not offer is never switched to", () => {
  const noHindi = config({ chat_languages: "Hinglish,English" });

  assertEquals(detectLanguageSwitch("मेरी शादी कब होगी?", noHindi), null);
  assertEquals(detectLanguageSwitch("Hindi me bat kre", noHindi), null);
});

Deno.test("a switch is spelled the way the dashboard spells it", () => {
  const lower = config({ chat_languages: "hinglish,english,hindi" });
  assertEquals(detectLanguageSwitch("हिंदी में बताए", lower)?.language, "hindi");
});

Deno.test("earlier replies in another language are not a precedent", () => {
  const prompt = chatSystemPrompt({ language: "Hindi" });

  assert(prompt.includes("That is not a precedent"));
  assert(prompt.includes("Hindi typed in Roman letters is not a different language"));
  assert(prompt.includes("If they ask you to write in another language, do it"));
});

Deno.test("a reading keeps the language block it shipped with", () => {
  // Palm and face have no earlier replies to be misled by, and no keyboard.
  const reading = languageBlock("Hindi");

  assert(!reading.includes("precedent"));
  assert(reading.includes("someone who types in English"));
});
