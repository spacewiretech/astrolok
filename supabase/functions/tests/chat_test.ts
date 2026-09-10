import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  buildUserPrompt,
  CHAT_SCHEMA,
  chatSystemPrompt,
  normaliseChatReply,
} from "../_shared/astro_chat.ts";
import {
  BUILT_IN_LANGUAGES,
  isSupported,
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
  assert(SYSTEM_PROMPT.includes("answer in the language\nthey wrote in"));
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
  for (const version of ["", "  ", "V2", "v3", "latest"]) {
    assert(
      chatSystemPrompt({ version, language: "English" }).includes("EFFORT IS PART OF THE READING"),
      `version "${version}" did not fall through to v2`,
    );
  }
});

Deno.test("v2 answers the question v1 dodged", () => {
  // The reply that prompted this: "ky me army ma kab bharti hungi", answered with a remark about
  // looking at your energy rather than estimating a time. Each assertion is one half of that
  // failure — no answer, and no mention of the work.
  const prompt = chatSystemPrompt({ language: "Hinglish" });

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
