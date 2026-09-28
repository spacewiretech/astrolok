import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  acceptChipFor,
  buildUserPromptV5,
  CHAT_SCHEMA_V5,
  ChatContextV5,
  chatSystemPromptV5,
  hasWholeChart,
  isRemedyAccept,
  kundaliLineFor,
  kundaliLineTurn,
  mattersOpeningSoon,
  normaliseChatReplyV5,
  onTopicOptions,
  v5Body,
} from "../_shared/astro_chat_v5.ts";
import { correctionIntent, correctsOwnDate, parseDob, parseHour } from "../_shared/birth_details.ts";
import { FALLBACK_LANGUAGES, fallbackOptions, offTopic, topicsOf } from "../_shared/chat_topics.ts";
import { detectLanguageSwitch, isMarathi } from "../_shared/chat_language.ts";
import { detectCrisis } from "../_shared/crisis.ts";
import { chatTiming, TIMING_TOPICS, V5_TIMING_TOPICS } from "../_shared/chat_timing.ts";
import { describeTransits, nearerSeasons, stays, transitTiming } from "../_shared/chat_transits.ts";
import { chatSystemPrompt } from "../_shared/astro_chat.ts";
import { AppConfig } from "../_shared/config.ts";
import { computeChart, julianDayOf, RASHIS } from "../_shared/jyotish.ts";

/**
 * Chat v5 — the WhatsApp-style chat. Each block below is one rule of the v5 plan, asserted where
 * it lives, so an edit that quietly undid one fails here first.
 */

const PROMPT = chatSystemPromptV5({ language: "Hinglish" });
const flat = (text: string) => text.replace(/\s+/g, " ");
const TODAY = new Date("2026-09-25T00:00:00Z");

// ---------------------------------------------------------------- the prompt

Deno.test("a v5 reply is chat messages: the answer, the reason, then the offer", () => {
  const p = flat(PROMPT);
  assert(p.includes("YOU ARE CHATTING, THE WAY PEOPLE CHAT ON WHATSAPP"));
  assert(p.includes("No headings, no bullet lists"));
  assert(p.includes("Kya main aapko aaj ka upay bataun?"));
  assert(p.includes('in "remedy_bubbles"'));
  assert(p.includes("ANSWER FIRST"));
});

Deno.test("every kab gets a window in the first sentence — from the dasha or from Guru", () => {
  const p = flat(PROMPT);
  assert(p.includes("The first sentence of your reply must contain a time window"));
  assert(p.includes("comes from their dasha"));
  assert(p.includes("comes from Guru's transit"));
  assert(p.includes("Never write that the chart cannot tell them when"));
  assert(p.includes('never "dwar khulega"'));
});

Deno.test("v5 reads santan as a period, gently, and never as fertility", () => {
  const p = flat(PROMPT);
  assert(p.includes("Never say or suggest that they cannot have a child"));
  assert(p.includes("Doctor se salah bhi zaroor lijiye"));
  assert(p.includes("never fertility"));
});

Deno.test("the boundaries allow a window of up to two years, and nothing else", () => {
  const p = flat(PROMPT);
  assert(p.includes("BOUNDARIES — these are absolute"));
  assert(p.includes("window of up to about two years"));
  assert(p.includes("Never an exact date, never a year the block does not give"));
  assert(p.includes("never a time for a death, an illness, an accident or a legal case"));
  assert(!p.includes("Never give a date, a year"), "v4's no-year rule leaked into v5");
  assert(p.includes("Never use deterministic verbs"));
  assert(p.includes("Never a gemstone"));
});

Deno.test("names are refused, one person's mind is never read, doubt gets a narrower window", () => {
  const p = flat(PROMPT);
  assert(p.includes("never invent a name or a letter"));
  assert(!p.includes("letters a name begins with"));
  assert(p.includes("Main unke mann ki baat nahi bata sakta"));
  assert(p.includes("Never promise that the person will call"));
  assert(p.includes("Samajh sakta hoon, seedha jawab chahiye"));
});

Deno.test("a stated rashi is accepted, the DOB is never confirmed from its own chart", () => {
  const p = flat(PROMPT);
  assert(p.includes('Never write "aapki rashi X nahi, Y hai"'));
  assert(p.includes("Never use the kundali to confirm or overrule their date of birth"));
  // Seen live: "Maine sahi janm tithi 3 January 2000 note kar li hai", and nothing saved.
  assert(p.includes("Never say you have noted, saved or changed a date or time of birth unless THE DETAIL THEY JUST GAVE block is there"));
});

Deno.test("the crisis rule stops the reading and gives Tele-MANAS", () => {
  const p = flat(PROMPT);
  assert(p.includes("IF THEY SAY THEY WANT TO DIE"));
  assert(p.includes("stop the reading"));
  assert(p.includes("Tele-MANAS 14416"));
  assert(p.includes("Never say the feeling comes from the planets"));
});

Deno.test("the few-shot examples carry no year the model could copy", () => {
  const examples = PROMPT.slice(PROMPT.indexOf("EXAMPLES"));
  assert(examples.includes("‹window›"));
  assert(!/\b20\d\d\b/.test(examples), "a real year sits in the examples");
});

Deno.test("the language block is plain, and knows ghar can mean family", () => {
  const hindi = flat(chatSystemPromptV5({ language: "Hindi" }));
  assert(hindi.includes("शादी not विवाह"));
  assert(hindi.includes("very often mean the family, not a house"));
  assert(hindi.includes("answer in simple Marathi, never Hindi"));
  assert(hindi.includes("every message bubble"));
});

// ---------------------------------------------------------------- the schema

Deno.test("the schema lists every property it orders, and care is not the model's to write", () => {
  const ordering = CHAT_SCHEMA_V5.propertyOrdering;
  assertEquals([...ordering].sort(), Object.keys(CHAT_SCHEMA_V5.properties).sort());
  assertEquals(ordering[0], "kind");
  assert(!CHAT_SCHEMA_V5.properties.kind.enum.includes("care" as never));
  assertEquals(CHAT_SCHEMA_V5.properties.bubbles.maxItems, 3);
});

// ---------------------------------------------------------------- normalising

const OFFER = {
  kind: "answer",
  topic: "marriage",
  bubbles: ["Aapki kundali ke hisaab se shaadi ka sabse accha samay aa raha hai.", "Is time Shukra.", "Upay bataun?"],
  offer: "remedy",
  remedy_bubbles: ["Har Shukravar mantra 11 baar.", "Kal aaiye.", "Rishta kaun dhoond raha hai?"],
  options: ["Jeevansathi kaisa hoga?", "Birth time batayein"],
  ask_for: "none",
};

Deno.test("an offer always leads with its yes, in their language", () => {
  const reply = normaliseChatReplyV5(OFFER, { language: "Kannada", hourAsked: false })!;
  assertEquals(reply.options[0], acceptChipFor("Kannada"));
  assertEquals(reply.offer, "remedy");
  assertEquals(reply.remedyBubbles.length, 3);
});

Deno.test("an offer with nothing to serve is no offer", () => {
  const reply = normaliseChatReplyV5({ ...OFFER, remedy_bubbles: [] }, {
    language: "Hinglish",
    hourAsked: false,
  })!;
  assertEquals(reply.offer, "none");
  assert(!reply.options.includes(acceptChipFor("Hinglish")));
});

Deno.test("once the hour has been asked, neither a chip nor ask_for asks it again", () => {
  const reply = normaliseChatReplyV5({ ...OFFER, ask_for: "birth_time" }, {
    language: "Hinglish",
    hourAsked: true,
  })!;
  assert(!reply.options.some((o) => /birth time/i.test(o)));
  assertEquals(reply.askFor, "none");
});

Deno.test("no bubbles is no reply; odd fields fall back rather than throw", () => {
  assertEquals(normaliseChatReplyV5({ bubbles: [] }, { language: "Hinglish", hourAsked: false }), null);
  assertEquals(normaliseChatReplyV5(null, { language: "Hinglish", hourAsked: false }), null);

  const odd = normaliseChatReplyV5({ bubbles: ["x".repeat(900)], kind: "essay", topic: "moon" }, {
    language: "Hinglish",
    hourAsked: false,
  })!;
  assertEquals(odd.kind, "answer");
  assertEquals(odd.topic, "general");
  assert(odd.bubbles[0].length <= 320);
});

Deno.test("a reply that gives a helpline is a care reply: no offer, no astrology chip, no top-up", () => {
  // Live, to a message the crisis lists do not know, in a thread no one had flagged: the model
  // followed IF THEY SAY THEY WANT TO DIE, and the top-up put "मेरी शादी कब होगी?" under it.
  const message = "जीने की इच्छा नहीं है, सब खत्म करना चाहती हूँ";
  assertEquals(detectCrisis(message), null);
  const raw = {
    kind: "chat",
    topic: "general",
    offer: "none",
    ask_for: "none",
    bubbles: ["प्रिया, कृपया ऐसा बिल्कुल मत सोचिए।", "प्लीज़ अभी टेली-मानस (Tele-MANAS) हेल्पलाइन 14416 पर कॉल करें।", "अपने किसी करीबी से तुरंत बात कीजिए।"],
    options: ["बात करने की कोशिश करती हूँ"],
  };
  const reply = normaliseChatReplyV5(raw, { language: "Hindi", hourAsked: false, asked: [message] })!;
  assertEquals(reply.kind, "care");
  assertEquals(reply.options, ["बात करने की कोशिश करती हूँ"]);

  // Whatever else the model put under it: no upay, no ask, no chip that goes back to a reading.
  const offered = normaliseChatReplyV5({
    ...OFFER,
    bubbles: ["Aap akele nahi hain.", "Abhi Tele-MANAS ko 14416 par call kijiye — free hai, 24 ghante."],
    options: ["Meri shaadi kab hogi?", "Kisi apne se baat karti hoon"],
    ask_for: "birth_time",
  }, { language: "Hinglish", hourAsked: false })!;
  assertEquals(offered.kind, "care");
  assertEquals(offered.offer, "none");
  assertEquals(offered.remedyBubbles, []);
  assertEquals(offered.options, ["Kisi apne se baat karti hoon"]);
  assertEquals(offered.askFor, "none");
  assert(!("remedy_bubbles" in v5Body(offered, { version: "v5" })));
  assertEquals(v5Body(offered, { version: "v5" }).kind, "care");

  // A number that only contains 14416, or 112 on its own, is not a helpline.
  assertEquals(normaliseChatReplyV5({ ...OFFER, bubbles: ["Order 1441612 aaya.", "112 din."] }, { language: "Hinglish", hourAsked: false })!.kind, "answer");
});

Deno.test("a stored v5 reply still renders in an old build, and hides nothing it should show", () => {
  const reply = normaliseChatReplyV5(OFFER, { language: "Hinglish", hourAsked: false })!;
  const body = v5Body(reply, { version: "v5", remedyHook: true });

  assertEquals(body.verdict, reply.bubbles[0]);
  assert((body.opening as string).length > 0);
  assertEquals(body.sections, []);
  assertEquals(body.remedy_bubbles, reply.remedyBubbles);
  assertEquals(body.remedy_hook, true);
  assertEquals(body.v, "v5");

  const plain = v5Body({ ...reply, offer: "none" }, { version: "v5" });
  assert(!("remedy_bubbles" in plain));
});

// ---------------------------------------------------------------- accepting the upay

Deno.test("a yes is heard in every language, and a new question is not a yes", () => {
  for (const said of ["Haan, upay batao 🙏", "haan", "ha ji", "yes please", "हाँ", "ಹೌದು", "சரி", "అవును", "ശരി"]) {
    assert(isRemedyAccept(said), `missed: ${said}`);
  }
  for (const said of ["haan par pehle ye batao ki shaadi kab hogi", "nahi", "mera career?", ""]) {
    assert(!isRemedyAccept(said), `accepted: ${said}`);
  }
});

// ---------------------------------------------------------------- the user prompt

function context(over: Partial<ChatContextV5> = {}): ChatContextV5 {
  return {
    chart: computeChart({ dob: "1999-10-17", birthTime: "23:55", asOf: TODAY }),
    timing: null,
    transits: null,
    birthHourAsks: { asked: 0, declined: false },
    facts: [],
    firstReply: false,
    remediesGiven: [],
    hookGiven: false,
    planEnabled: false,
    care: false,
    ...over,
  };
}

Deno.test("with the hour the timing is the dasha; without, Guru's transit; else unknown", () => {
  const dob = "1999-10-17";
  const chart = computeChart({ dob, birthTime: "23:55", asOf: TODAY });
  const dasha = buildUserPromptV5("shaadi kab?", context({ chart, timing: chatTiming(chart, { dob, asOf: TODAY, v5: true }) }));
  assert(dasha.includes("computed from their Vimshottari dasha"));
  assert(dasha.includes("month-year range"));

  const noHour = computeChart({ dob: "1996-04-12", asOf: TODAY });
  const transit = buildUserPromptV5("shaadi kab?", context({
    chart: noHour,
    transits: transitTiming(noHour!.moonRashi, TODAY),
  }));
  assert(transit.includes("from Guru's transit over their rashi"));

  const unknown = buildUserPromptV5("shaadi kab?", context({ chart: null }));
  assert(unknown.includes("THE TIMING: UNKNOWN"));
});

Deno.test("a detail just given is thanked for, said back, and the earlier question answered", () => {
  const prompt = buildUserPromptV5("15 August 1998", context({
    captured: { field: "dob", said: "15 August 1998", question: "meri date galat hai, shaadi kab?" },
  }));
  assert(prompt.includes("THE DETAIL THEY JUST GAVE: their date of birth, 15 August 1998"));
  assert(prompt.includes("«meri date galat hai, shaadi kab?»"));

  // Given unasked, it answers nothing said before it.
  const unasked = flat(buildUserPromptV5("meri DOB galat hai, sahi 3 January 2000", context({
    captured: { field: "dob", said: "3 January 2000", question: null },
  })));
  assert(unasked.includes("answer anything else they ask in this message."));
  assert(!unasked.includes("the question they asked before it"));

  const failed = buildUserPromptV5("pata nahi 15 ya 16", context({ captureFailed: "dob" }));
  assert(failed.includes("could not be read as one"));
  assert(failed.includes('"ask_for" to "dob"'));
});

Deno.test("a stated rashi is accepted without the hour, and reconciled gently with it", () => {
  const noHour = computeChart({ dob: "2004-09-24", asOf: TODAY });
  const accepted = buildUserPromptV5("ನಂದು ಕುಂಬ ರಾಶಿ", context({ chart: noHour, statedRashi: "Kumbha" }));
  assert(accepted.includes("accept Kumbha and speak of it as theirs"));
  assert(accepted.includes("never tell them theirs is wrong"));

  const known = buildUserPromptV5("meri rashi dhanu hai", context({ statedRashi: "Dhanu" }));
  assert(known.includes("Say so once, gently"));
});

Deno.test("the hook follows the flag, and is given once a session", () => {
  assert(buildUserPromptV5("x", context()).includes("never promise one"));
  assert(buildUserPromptV5("x", context({ planEnabled: true })).includes("3-month plan"));
  assert(buildUserPromptV5("x", context({ hookGiven: true })).includes("already given this session"));
});

Deno.test("an upay offered and passed over is not asked about again, and stays one tap away", () => {
  const offered = flat(buildUserPromptV5("jeevansathi kaisa hoga?", context({ upaysOffered: ["marriage"] })));
  assert(offered.includes("THE UPAY ALREADY OFFERED, not taken yet: marriage"));
  assert(offered.includes("do not write the offer line again"));
  assert(offered.includes('Keep "offer" as "remedy"'));

  assert(!buildUserPromptV5("x", context()).includes("ALREADY OFFERED"));
  assert(!buildUserPromptV5("x", context({ upaysOffered: [] })).includes("ALREADY OFFERED"));
});

Deno.test("a flagged conversation stays gentle and offers nothing", () => {
  const prompt = buildUserPromptV5("x", context({ care: true }));
  assert(prompt.includes("THEY SAID THEY WANTED TO DIE"));
  assert(prompt.includes('"offer" is "none"'));
  assert(prompt.includes("14416"));
});

Deno.test("an app button's English is answered in their language; Marathi in Marathi", () => {
  assert(buildUserPromptV5("I want to know about my love life.", context({ appOpener: "Hindi" }))
    .includes("Reply in Hindi"));
  assert(buildUserPromptV5("माझं लग्न कधी होईल", context({ marathi: true })).includes("simple Marathi"));
});

Deno.test("the first reply names the rashi and does not greet; later ones do neither", () => {
  assert(buildUserPromptV5("x", context({ firstReply: true })).includes("do not greet"));
  assert(buildUserPromptV5("x", context()).includes("do not name or explain their rashi again"));
});

// ---------------------------------------------------------------- reading birth details

Deno.test("a date of birth is read however it is typed, and never invented", () => {
  const cases: Array<[string, string | null]> = [
    ["15/08/1998", "1998-08-15"],
    ["15-8-98", "1998-08-15"],
    ["15 August 1998", "1998-08-15"],
    ["15th aug 98", "1998-08-15"],
    ["August 15, 1998", "1998-08-15"],
    ["१५/०८/१९९८", "1998-08-15"],
    ["12 मार्च 2001", "2001-03-12"],
    ["ಜನ್ಮ ದಿನಾಂಕ 15 ಆಗಸ್ಟ್ 1998", "1998-08-15"],
    ["31/02/1998", null],
    ["15/08/2030", null],
    ["meri umar 25 saal", null],
  ];
  for (const [said, dob] of cases) assertEquals(parseDob(said, TODAY)?.dob ?? null, dob, said);
});

Deno.test("an hour is read with or without minutes, and morning or night is never guessed", () => {
  const cases: Array<[string, string | null, boolean]> = [
    ["7 baje subah", "07:00", false],
    ["7pm", "19:00", false],
    ["shaam 7", "19:00", false],
    ["raat 2 baje", "02:00", false],
    ["ಸಂಜೆ 7 ಗಂಟೆ", "19:00", false],
    ["0630 ಸಂಜೆ", "18:30", false],
    ["12 pm 9 minit", "12:09", false],
    ["4 बजकर 20 मिनट शाम", "16:20", false],
    ["15.08.1998 7:30 pm", "19:30", false],
    ["I was born at 6:45 PM.", "18:45", false],
    ["7:30", null, true],
    ["7 baje", null, true],
    ["25 saal", null, false],
    ["Sham ko", null, false],
  ];
  for (const [said, time, ambiguous] of cases) {
    assertEquals(parseHour(said, TODAY), { time, ambiguous }, said);
  }
});

Deno.test("a correction is heard in every script, and a question is not one", () => {
  for (const said of ["meri date galat hai", "Aadhaar mein galat likha hai", "मेरी जन्मतिथि गलत है", "ನನ್ನ ದಿನಾಂಕ ತಪ್ಪು"]) {
    assert(correctionIntent(said), said);
  }
  assert(!correctionIntent("shaadi kab hogi"));
});

Deno.test("a date is read unasked only when they say theirs on file is wrong, and nobody else's", () => {
  for (
    const said of [
      // Live, the first message of a thread: the model said it had noted it, and nothing was saved.
      "meri date of birth galat save ho gayi hai app mein, sahi wali 3 January 2000 hai",
      "Meri DOB galat he, sahi 03/01/2000",
      "my date of birth is wrong, it is 3 Jan 2000",
      "मेरी जन्मतिथि गलत है, सही 3 जनवरी 2000 है",
      "ನನ್ನ ಜನ್ಮ ದಿನಾಂಕ ತಪ್ಪು, 3 ಜನವರಿ 2000",
    ]
  ) {
    assert(correctsOwnDate(said), said);
    assertEquals(parseDob(said, TODAY)?.dob, "2000-01-03", said);
  }
  for (
    const said of [
      "meri beti ki DOB galat hai, sahi 12/3/2015",
      "mere husband ki dob galat hai 4/5/1995",
      "uski date of birth 12/3/1999 hai, sahi match hai kya?",
      // No word that the saved one is wrong, or none that it is theirs: asked for in the chat.
      "meri shaadi kab hogi? DOB 3 Jan 2000",
      "meri dob sahi hai 3 jan 2000, shaadi kab?",
      "dob galat hai sahi 3 jan 2000",
    ]
  ) {
    assert(!correctsOwnDate(said), said);
  }
});

// ---------------------------------------------------------------- transits

Deno.test("Guru and Shani change sign when the ephemeris says they do (±1 month)", () => {
  const from = julianDayOf(new Date("2026-09-01T00:00:00Z"));
  const find = (planet: "jupiter" | "saturn", rashi: string, afterJd: number) =>
    stays(planet, from, from + 730).find((s) => RASHIS[s.rashiIndex] === rashi && s.startJd > afterJd);

  // Shani into Mesha around June 2027; Guru into Simha around November 2026.
  const shani = find("saturn", "Mesha", from)!;
  assert(Math.abs(shani.startJd - julianDayOf(new Date("2027-06-03T00:00:00Z"))) < 31);
  const guru = find("jupiter", "Simha", from)!;
  assert(Math.abs(guru.startJd - julianDayOf(new Date("2026-10-31T00:00:00Z"))) < 31);
});

Deno.test("no stay but the first and the last is shorter than two months", () => {
  const from = julianDayOf(TODAY);
  const all = stays("jupiter", from, from + 730);
  for (const stay of all.slice(1, -1)) assert(stay.endJd - stay.startJd >= 60);
});

Deno.test("a transit window is always inside two years, and Shani is named only as relief", () => {
  for (const rashi of RASHIS) {
    const timing = transitTiming(rashi, TODAY)!;
    for (const { window } of timing.topics) {
      if (!window) continue;
      assert(window.endJd - julianDayOf(TODAY) <= 24 * 30.44 + 1, rashi);
    }
    const text = describeTransits(timing);
    assert(!/sade sati.*(?:begins|starts|heavy ahead)/i.test(text));
  }
  assertEquals(transitTiming(null, TODAY), null);
  assertEquals(transitTiming("Klingon", TODAY), null);
});

// ---------------------------------------------------------------- v5 timing topics

Deno.test("v5 times love, children and debt; v4 still times exactly its five", () => {
  const dob = "1999-10-17";
  const chart = computeChart({ dob, birthTime: "23:55", asOf: TODAY });
  const v5 = chatTiming(chart, { dob, asOf: TODAY, v5: true })!;
  assertEquals(v5.topics.map((t) => t.topic), [...V5_TIMING_TOPICS]);
  for (const topic of v5.topics) {
    for (const window of topic.windows) assert(window.endJd - window.startJd <= 24 * 30.44 + 1);
  }

  const v4 = chatTiming(chart, { dob, asOf: TODAY })!;
  assertEquals(v4.topics.map((t) => t.topic), [...TIMING_TOPICS]);
});

Deno.test("a dasha window years off gives way to Guru's nearer season, and says what comes later", () => {
  // Seen on the emulator: 26, hour known, told "September 2031 se September 2033".
  const dob = "2000-01-01";
  const chart = computeChart({ dob, birthTime: "05:30", asOf: TODAY });
  const timing = chatTiming(chart, { dob, asOf: TODAY, v5: true })!;
  const transits = transitTiming(chart!.moonRashi, TODAY)!;
  const nearer = nearerSeasons(timing, transits);

  assert(nearer.marriage, "marriage should be answered from Guru");
  const horizon = julianDayOf(TODAY) + 24 * 30.44;
  for (const topic of timing.topics) {
    const first = topic.windows[0];
    // A dasha window inside two years is never replaced.
    if (first && first.startJd <= horizon) assertEquals(nearer[topic.topic], undefined, topic.topic);
  }

  const block = flat(buildUserPromptV5("shaadi kab?", context({ chart, timing, transits })));
  assert(block.includes("from Guru's transit over their rashi. This is the window to give."));
  assert(block.includes("comes later — from about September 2031"));
  assert(block.includes("name it only if they ask what comes after"));
});

Deno.test("Guru's season never opens before 21 for marriage, and a general stay never counts", () => {
  const asOfJd = julianDayOf(TODAY);
  const far = { lords: ["Shukra"], level: "antardasha" as const, mahadasha: "Shani", antardashas: ["Shukra"], startJd: asOfJd + 5 * 365.25, endJd: asOfJd + 7 * 365.25, now: false };
  const timing = (opensJd: number) => ({
    asOfJd,
    periods: [],
    topics: [{ topic: "marriage" as const, label: "Marriage", reasons: {}, windows: [far], withheld: false, opensJd }],
  });
  const transits = (how: "aspects" | "general", startJd: number) => ({
    asOfJd,
    rashi: "Tula",
    shaniEasing: null,
    topics: [{ topic: "marriage" as const, window: { startJd, endJd: startJd + 300, now: startJd <= asOfJd, guruHouse: 11, favours: how === "general" ? null : 7, how } }],
  });

  assert(nearerSeasons(timing(asOfJd), transits("aspects", asOfJd + 60)).marriage);
  // 20 today, 21 in a year: a season opening in two months is too soon.
  assertEquals(nearerSeasons(timing(asOfJd + 365), transits("aspects", asOfJd + 60)), {});
  assertEquals(nearerSeasons(timing(asOfJd), transits("general", asOfJd + 60)), {});
  // Withheld is withheld, whatever Guru does.
  const young = timing(asOfJd);
  young.topics[0].withheld = true;
  assertEquals(nearerSeasons(young, transits("aspects", asOfJd + 60)), {});
});

Deno.test("children, like marriage, are not timed for anyone under 18", () => {
  const dob = "2010-06-01";
  const chart = computeChart({ dob, birthTime: "10:00", asOf: TODAY });
  const timing = chatTiming(chart, { dob, asOf: TODAY, v5: true })!;
  const children = timing.topics.find((t) => t.topic === "children")!;
  assertEquals(children.withheld, true);
  assertEquals(children.windows, []);
});

// ---------------------------------------------------------------- languages

const OFFERED: AppConfig = new Map([["chat_languages", "Hinglish,Hindi,English,Tamil,Kannada,Malayalam,Telugu"]]);

const V5 = { v5: true };

Deno.test("a message in a southern script moves the conversation into that language", () => {
  assertEquals(detectLanguageSwitch("ನನ್ನ ಮದುವೆ ಯಾವಾಗ ಆಗಲಿದೆ", OFFERED, V5)?.language, "Kannada");
  assertEquals(detectLanguageSwitch("నాకు పెళ్లి ఎప్పుడు", OFFERED, V5)?.language, "Telugu");
  assertEquals(detectLanguageSwitch("kannada mein bolo", OFFERED, V5), { language: "Kannada", explicit: true });
});

Deno.test("Marathi in Devanagari is never switched to Hindi", () => {
  assert(isMarathi("माझं लग्न कधी होईल"));
  assertEquals(detectLanguageSwitch("माझं लग्न कधी होईल", OFFERED, V5), null);
  assertEquals(detectLanguageSwitch("मेरी शादी कब होगी?", OFFERED, V5)?.language, "Hindi");
});

Deno.test("v4 switches languages exactly as it shipped: no southern scripts, Devanagari is Hindi", () => {
  // The build on the Play Store gets v4, and its saved language must move only as it always did.
  for (const said of ["ನನ್ನ ಮದುವೆ ಯಾವಾಗ ಆಗಲಿದೆ", "నాకు పెళ్లి ఎప్పుడు", "என் திருமணம் எப்போது", "എന്റെ വിവാഹം എപ്പോൾ", "kannada mein bolo", "tamil me batao"]) {
    assertEquals(detectLanguageSwitch(said, OFFERED), null, said);
  }
  assertEquals(detectLanguageSwitch("माझं लग्न कधी होईल", OFFERED), { language: "Hindi", explicit: false });
  assertEquals(detectLanguageSwitch("Hindi me bat kre", OFFERED), { language: "Hindi", explicit: true });
});

// ---------------------------------------------------------------- options stay on the topic

Deno.test("the options rule keeps every chip on the reply's topic, with a menu for each", () => {
  const p = flat(PROMPT);
  assert(p.includes("EVERY OPTION IS ON THE TOPIC OF THIS REPLY"));
  assert(p.includes("never naukri, paisa, ghar or bachcha under it, not even one"));
  assert(!p.includes("At most one about work, money or business"), "v5's one-work-chip allowance is back");
  assert(!p.includes("then children, home, work, money"), "the cross-topic ordering is back");
  for (const topic of ["marriage", "love", "children", "career", "money", "debt", "home", "studies", "general"]) {
    assert(p.includes(`- ${topic}: `), `no menu for ${topic}`);
  }
  assert(p.includes("Never an option they already asked or tapped in this conversation"));
});

Deno.test("every example carries options, and none of them leaves its own topic", () => {
  const examples = PROMPT.slice(PROMPT.indexOf("EXAMPLES"));
  const topics = ["marriage", "marriage", "career", "marriage", "love", "children", "love", "marriage"] as const;
  const lists = [...examples.matchAll(/options: (\[[^\]]*\])/g)].map((m) => JSON.parse(m[1]) as string[]);
  assertEquals(lists.length, topics.length);
  lists.forEach((options, i) => {
    for (const option of options) assert(!offTopic(option, topics[i]), `example ${i + 1}: ${option}`);
  });
});

Deno.test("chips are read for their subject in every script, and look-alikes are not", () => {
  const cases: Array<[string, string[]]> = [
    ["Naukri kab pakki hogi?", ["career"]],
    ["Paison ki sthiti kab sudhregi?", ["money"]],
    ["Santan ka yog kab ban raha hai?", ["children"]],
    ["Love ya arrange?", ["marriage", "love"]],
    ["Shaadi-shuda zindagi kaisi rahegi?", ["marriage"]],
    ["करियर में तरक्की कब?", ["career"]],
    ["मेरे काम के बारे में बताएं", ["career"]],
    ["ನನ್ನ ವೃತ್ತಿ ಹೇಗಿರಲಿದೆ?", ["career"]],
    ["ಹಣಕಾಸಿನ ಸ್ಥಿತಿ ಹೇಗಿದೆ?", ["money"]],
    ["ಮದುವೆಯ ಯೋಗ ಯಾವಾಗ?", ["marriage"]],
    ["ಸ್ವಂತ ಮನೆ ಯೋಗ ಯಾವಾಗ?", ["home"]],
    ["பண வரவு எப்போது உயரும்?", ["money"]],
    ["திருமணம் எப்போது நடக்கும்?", ["marriage"]],
    ["నా పెళ్లి ఎప్పుడు?", ["marriage"]],
    ["അപ്പോൾ ജോലി കിട്ടുമോ?", ["career"]],
    ["സാമ്പത്തിക വളർച്ച എപ്പോൾ വരും?", ["money"]],
    // The one they will marry, however a chip names them.
    ["Kaisi ladki milegi?", ["marriage"]],
    ["लड़का क्या करता होगा?", ["marriage"]],
    ["Meri hone wali kaisi hogi?", ["marriage"]],
    ["ಹುಡುಗಿ ಉದ್ಯೋಗ ಮಾಡುತ್ತಾರಾ?", ["marriage", "career"]],
    ["மாப்பிள்ளை எப்படி இருப்பார்?", ["marriage"]],
    ["అమ్మాయి ఎలా ఉంటుంది?", ["marriage"]],
    // Look-alikes: the family, not a house; the upay working, not work; exam, not ex; Dhanu, not
    // dhan; a forehead, not money; pasand, not paisa; "what is going to happen", not a fiancée;
    // bahut, not bahu; വരുമാനം (income), not വരൻ (the groom).
    ["Ghar wale maanenge?", []],
    ["ಮನೆಯವರನ್ನು ಒಪ್ಪಿಸುವುದು ಹೇಗೆ?", []],
    ["Upay kaam karega?", []],
    ["उपाय काम करेगा?", []],
    ["Exam kab clear hoga?", ["studies"]],
    ["Dhanu rashi ka swabhav?", []],
    ["ಹಣೆಬರಹ ಏನು?", []],
    ["Pasand ki cheez kab milegi?", []],
    ["Kaunsa mahina sabse accha?", []],
    ["Aage kya hone wala hai?", []],
    ["Bahut accha samay kab hai?", []],
    ["വരുമാനം എപ്പോൾ കൂടും?", ["money"]],
    // English "work" is work — the commonest English chips under v4's love answers — unless it is
    // the upay or a rashi that works, or things working out.
    ["What of my work?", ["career"]],
    ["Tell me of work", ["career"]],
    ["Will I work abroad?", ["career"]],
    ["How to manage workplace stress?", ["career"]],
    ["How does this affect work?", ["career"]],
    ["Will the remedy work?", []],
    ["Will this upay work?", []],
    ["How does Ashlesha work?", []],
    ["How does my mind work?", []],
    ["Will it work out?", []],
    ["Will this work for me?", []],
    // Sick, and how someone is keeping, are health — never a chip, never under the kundali line.
    ["Papa bimar hain", ["health"]],
    ["बेटे की तबीयत कैसी रहेगी?", ["health"]],
    // Pay, in the loan-word or the language's own, is both work and money.
    ["Pehli salary kab milegi?", ["career", "money"]],
    ["वेतन वृद्धि के आसार?", ["career", "money"]],
    ["तनख़्वाह कब बढ़ेगी?", ["career", "money"]],
    ["ಸಂಬಳದ ನಿರೀಕ್ಷೆ ಹೇಗಿರಬಹುದು?", ["career", "money"]],
    ["சம்பளம் திருப்தியாக இருக்குமா?", ["career", "money"]],
    ["జీతం ఎప్పుడు పెరుగుతుంది?", ["career", "money"]],
    ["ശമ്പളം എപ്പോൾ കൂടും?", ["career", "money"]],
    // വേദന is pain, not വേതന.
    ["വേദന കുറയുമോ?", []],
  ];
  for (const [chip, subjects] of cases) assertEquals([...topicsOf(chip)].sort(), subjects.sort(), chip);
});

Deno.test("under a marriage answer, work, money and children chips go; love and neutral stay", () => {
  // The v5 chips from production, 25 Sep, under "Meri shaadi kab hogi?", and v4's commonest.
  for (
    const chip of [
      "Naukri kab pakki hogi?",
      "Paison ki sthiti aage kaisi rahegi?",
      "Naukri aur paisa kaisa rahega?",
      "Santan ka yog kab ban raha hai?",
      "करियर में तरक्की कब होगी?",
      "ಹಣಕಾಸಿನ ಸ್ಥಿತಿ ಹೇಗಿದೆ?",
    ]
  ) {
    assert(offTopic(chip, "marriage"), chip);
  }
  for (const chip of ["Jeevansathi kaisa hoga?", "Love ya arrange?", "Rishte mein aage kya hai?", "Aapas mein ladai kam kab hogi?", "Ghar wale maanenge?", "Shaadi ke baad naukri karun?"]) {
    assert(!offTopic(chip, "marriage"), chip);
  }
});

Deno.test("English work chips go under love and marriage; a raise in any word stays under work", () => {
  // Production, the 14 days to 25 Sep: under "I want to know about my love life." and the like.
  for (const topic of ["love", "marriage"] as const) {
    for (const chip of ["What of my work?", "What about my work?", "Tell me of work", "When will work settle?"]) {
      assertEquals(onTopicOptions([chip], { topic }), [], `${topic}: ${chip}`);
    }
  }
  // The same period's raise chips under career answers, 13 of 16 once dropped as money.
  for (
    const chip of [
      "वेतन वृद्धि के आसार?",
      "वेतन में सुधार कब?",
      "ಸಂಬಳದ ನಿರೀಕ್ಷೆ ಹೇಗಿರಬಹುದು?",
      "ನನ್ನ ಸಂಬಳ ಹೇಗಿರಬಹುದು?",
      "சம்பளம் திருப்தியாக இருக்குமா?",
      "జీతం ఎప్పుడు పెరుగుతుంది?",
      "ശമ്പളം എപ്പോൾ കൂടും?",
    ]
  ) {
    assertEquals(onTopicOptions([chip], { topic: "career" }), [chip], chip);
    assertEquals(onTopicOptions([chip], { topic: "money" }), [chip], chip);
    assertEquals(onTopicOptions([chip], { topic: "marriage" }), [], chip);
  }
});

Deno.test("a chip about the partner's work stays under marriage or love, and nowhere else", () => {
  // The chips the guard would have dropped wrongly on v4's marriage answers.
  for (
    const chip of [
      "ಹುಡುಗಿ ಉದ್ಯೋಗ ಮಾಡುತ್ತಾರಾ?",
      "Ladke ki naukri kaisi hogi?",
      "Unka profession kaisa hoga?",
      "उनका करियर कैसा होगा?",
      "उनकी पढ़ाई कैसी होगी?",
      "ಅವರ ವೃತ್ತಿ ಹೇಗಿರಬಹುದು?",
      "அவர் என்ன வேலை செய்வார்?",
      "What field will they work in?",
    ]
  ) {
    assert(!offTopic(chip, "marriage"), chip);
    assert(!offTopic(chip, "love"), chip);
  }
  // "Uske baad" is "after that", not the partner; and "them" means nothing under a money answer.
  assert(offTopic("Uske baad naukri kab lagegi?", "marriage"));
  assert(offTopic("उसके बाद नौकरी कब लगेगी?", "marriage"));
  assert(offTopic("Mera career kaisa rahega?", "marriage"));
  assert(offTopic("Unka career kaisa hoga?", "money"));
});

Deno.test("love and marriage, work and studies, money and debt lead into each other; nothing else", () => {
  assert(!offTopic("Shaadi kab hogi?", "love"));
  assert(!offTopic("Exam kab clear hoga?", "career"));
  assert(!offTopic("Karz kab utrega?", "money"));
  assert(offTopic("Naukri kab lagegi?", "love"));
  assert(offTopic("Shaadi kab hogi?", "career"));
  assert(offTopic("Paisa kab aayega?", "home"));
  // Kept strict on purpose: work and money do not cross.
  assert(offTopic("Paisa kab badhega?", "career"));
  assert(offTopic("Naukri kab lagegi?", "money"));
  // A general reply may go anywhere but health; health is never a chip.
  assert(!offTopic("Naukri kab lagegi?", "general"));
  assert(offTopic("Sehat kaisi rahegi?", "general"));
  assert(offTopic("सेहत कैसी रहेगी?", "marriage"));
});

const MARRIAGE = {
  kind: "answer",
  topic: "marriage",
  bubbles: ["‹window› shaadi ka sabse accha samay hai.", "Is time Shukra ki dasha chalegi.", "Aaj ka upay bataun?"],
  offer: "remedy",
  remedy_bubbles: ["Har Shukravar mantra 11 baar.", "Kal aaiye.", "Rishta kaun dhoond raha hai?"],
  options: ["Haan, upay batao 🙏", "Jeevansathi kaisa hoga?", "Naukri kab pakki hogi?"],
  ask_for: "none",
};

Deno.test("an off-topic chip is dropped and the topic's own follow-up takes its place", () => {
  const reply = normaliseChatReplyV5(MARRIAGE, { language: "Hinglish", hourAsked: false })!;
  assertEquals(reply.options, ["Haan, upay batao 🙏", "Jeevansathi kaisa hoga?", "Love ya arrange?"]);

  // A yes the model wrote under no offer would be a yes to nothing.
  const none = normaliseChatReplyV5(
    { ...MARRIAGE, offer: "none", options: ["Haan, upay batao 🙏", "Love ya arrange?", "Jeevansathi kaisa hoga?"] },
    { language: "Hinglish", hourAsked: false },
  )!;
  assertEquals(none.options, ["Love ya arrange?", "Jeevansathi kaisa hoga?"]);
});

Deno.test("nothing they already asked or passed over is offered back, in any spelling of it", () => {
  const reply = normaliseChatReplyV5(
    { ...MARRIAGE, options: ["Love ya arrange?", "jeevansathi kaisa hoga", "Ghar wale maanenge?"] },
    { language: "Hinglish", hourAsked: false, asked: ["Meri shaadi kab hogi?", "Jeevansathi kaisa hoga?"] },
  )!;
  assertEquals(reply.options, ["Haan, upay batao 🙏", "Love ya arrange?", "Ghar wale maanenge?"]);

  const topUp = normaliseChatReplyV5(
    { ...MARRIAGE, options: ["Naukri kab pakki hogi?"] },
    { language: "Hinglish", hourAsked: false, asked: ["Jeevansathi kaisa hoga?"] },
  )!;
  assertEquals(topUp.options, ["Haan, upay batao 🙏", "Love ya arrange?", "Shaadi mein deri kyun?"]);

  // The last reply's chips, untapped, come back in [asked] — and are not offered twice running.
  const next = normaliseChatReplyV5(
    { ...MARRIAGE, offer: "none", options: ["Jeevansathi kaisa hoga?", "Love ya arrange?", "Ghar wale maanenge?"] },
    {
      language: "Hinglish",
      hourAsked: false,
      asked: ["Kab tak hogi?", "Meri shaadi kab hogi?", "Haan, upay batao 🙏", "Jeevansathi kaisa hoga?", "Love ya arrange?"],
    },
  )!;
  assertEquals(next.options, ["Ghar wale maanenge?", "Shaadi mein deri kyun?"]);

  // In the same words or inside longer ones. Seen live: the model repeated its untapped "Love
  // marriage ya arrange?", and the top-up put its own "Love ya arrange?" in its place.
  const live = normaliseChatReplyV5(
    { ...MARRIAGE, options: ["Haan, upay batao 🙏", "Love marriage ya arrange?", "Rishta kab tak aayega?"] },
    {
      language: "Hinglish",
      hourAsked: false,
      asked: ["Jeevansathi kaisa hoga?", "Meri shaadi kab hogi?", "Haan, upay batao 🙏", "Jeevansathi kaisa hoga?", "Love marriage ya arrange?"],
    },
  )!;
  assertEquals(live.options, ["Haan, upay batao 🙏", "Rishta kab tak aayega?", "Shaadi mein deri kyun?"]);
  assertEquals(onTopicOptions(["Shaadi kab hogi?"], { topic: "marriage", asked: ["meri shaadi kab hogi"] }), []);
  // The longer after the shorter is a new chip, and a word they merely used is not a question asked.
  assertEquals(onTopicOptions(["Love marriage ya arrange?"], { topic: "marriage", asked: ["Love ya arrange?"] }), ["Love marriage ya arrange?"]);
  assertEquals(onTopicOptions(["Shaadi mein deri kyun?"], { topic: "marriage", asked: ["shaadi"] }), ["Shaadi mein deri kyun?"]);
});

Deno.test("the top-up is in their language, Marathi too, and never on an ask or after a crisis", () => {
  const kannada = normaliseChatReplyV5(
    { ...MARRIAGE, topic: "career", offer: "none", options: ["ಮದುವೆ ಯಾವಾಗ?"] },
    { language: "Kannada", hourAsked: false },
  )!;
  assertEquals(kannada.options, ["ಸರ್ಕಾರಿ ಅಥವಾ ಖಾಸಗಿ ಕೆಲಸ?", "ಬಡ್ತಿ ಯಾವಾಗ ಸಿಗುತ್ತದೆ?"]);

  const marathi = normaliseChatReplyV5({ ...MARRIAGE, options: ["नोकरी कधी मिळेल?"] }, { language: "Marathi", hourAsked: false })!;
  assertEquals(marathi.options, [acceptChipFor("Marathi"), "जोडीदार कसा असेल?", "लव्ह की अरेंज लग्न?"]);

  const ask = normaliseChatReplyV5({ ...MARRIAGE, kind: "ask", offer: "none", options: [] }, { language: "Hinglish", hourAsked: false })!;
  assertEquals(ask.options, []);
  const care = normaliseChatReplyV5({ ...MARRIAGE, kind: "chat", offer: "none", options: [] }, { language: "Hinglish", hourAsked: false, care: true })!;
  assertEquals(care.options, []);
});

Deno.test("the upay turn reuses its offer's chips through the same guard, without the yes", () => {
  // As `serveRemedy` calls it, on an offer stored before the guard existed.
  const stored = ["Haan, upay batao 🙏", "Jeevansathi kaisa hoga?", "Naukri kab pakki hogi?"];
  assertEquals(
    onTopicOptions(stored, { topic: "marriage", asked: ["Meri shaadi kab hogi?", "Haan, upay batao 🙏"] }),
    ["Jeevansathi kaisa hoga?"],
  );
  // A topic the row does not know is general; a list that is not one is no chips.
  assertEquals(onTopicOptions(stored, { topic: "moon" }), ["Jeevansathi kaisa hoga?", "Naukri kab pakki hogi?"]);
  assertEquals(onTopicOptions("Love ya arrange?", { topic: "marriage", asked: [null, 7] }), []);
});

Deno.test("every fallback chip, in every language, names its own topic and is short", () => {
  const topics = ["marriage", "love", "children", "career", "money", "debt", "home", "studies"] as const;
  for (const language of FALLBACK_LANGUAGES) {
    for (const topic of topics) {
      const chips = fallbackOptions(topic, language);
      assert(chips.length >= 2, `${language}/${topic}`);
      for (const chip of chips) {
        assert(topicsOf(chip).size > 0 && !offTopic(chip, topic), `${language}/${topic}: ${chip}`);
        assert(chip.split(/\s+/).length <= 6 && chip.length <= 60, `${language}/${topic}: ${chip}`);
        assert(!isRemedyAccept(chip), `${language}/${topic}: ${chip}`);
      }
    }
    assert(fallbackOptions("general", language).length >= 2, `${language}/general`);
  }
  // Every language the yes chip is written in has its follow-ups too.
  for (const language of ["Hinglish", "Hindi", "English", "Kannada", "Tamil", "Telugu", "Malayalam", "Marathi"]) {
    assert(FALLBACK_LANGUAGES.includes(language.toLowerCase()), language);
  }
});

Deno.test("a chip about seeing a doctor is medical timing, and never offered", () => {
  assert(offTopic("Doctor se salah lene ka sahi samay?", "children"));
  assert(offTopic("डॉक्टर को कब दिखाएँ?", "children"));
});

// ---------------------------------------------------------------- the kundali line

/** The emulator's review account: 26, hour known, Tula rashi, Swati nakshatra. */
const WHOLE = { dob: "2000-01-01", birthTime: "05:30" };

function kundaliContext(
  { dob, birthTime }: { dob: string; birthTime: string | null },
  question: string,
  { place = null as string | null, first = true } = {},
) {
  const chart = computeChart({ dob, birthTime, asOf: TODAY });
  const timing = chatTiming(chart, { dob, asOf: TODAY, v5: true });
  const transits = chart ? transitTiming(chart.moonRashi, TODAY) : null;
  const kundaliLine = kundaliLineFor(chart, { timing, transits, birthPlace: place, question });
  return context({ chart, timing, transits, firstReply: first, kundaliLine });
}

Deno.test("the first reply with the whole chart opens with the kundali line, rashi and nakshatra", () => {
  assert(kundaliLineTurn([], { chart: computeChart({ ...WHOLE, asOf: TODAY }), completed: false, care: false }));

  const prompt = flat(buildUserPromptV5("Meri shaadi kab hogi?", kundaliContext(WHOLE, "Meri shaadi kab hogi?")));
  assert(prompt.includes("THE KUNDALI LINE: you have all their birth details now"));
  assert(prompt.includes("aapki Tula rashi aur Swati nakshatra hai, aur aane wala samay aapke liye accha dikh raha hai"));
  assert(prompt.includes("the answer is the second message — its window in its first sentence"));
  // It replaces the first reply's own "name their rashi", so the rashi is said once.
  assert(prompt.includes("THE KUNDALI LINE names their rashi; do not name it again"));
  assert(!prompt.includes("Name their rashi once, if the chart gives it"));

  const system = flat(PROMPT);
  assert(system.includes("This is the one exception to ANSWER FIRST"));
  assert(system.includes("in the first reply of a conversation, and in THE KUNDALI LINE"));
});

Deno.test("no kundali line without the hour, even when one is handed in", () => {
  const noHour = computeChart({ dob: WHOLE.dob, asOf: TODAY });
  assert(!hasWholeChart(noHour));
  assertEquals(kundaliLineFor(noHour, { timing: null, transits: transitTiming(noHour!.moonRashi, TODAY), question: "shaadi kab?" }), null);
  assert(!kundaliLineTurn([], { chart: noHour, completed: false, care: false }));

  const prompt = buildUserPromptV5("Meri shaadi kab hogi?", kundaliContext({ dob: WHOLE.dob, birthTime: null }, "Meri shaadi kab hogi?"));
  assert(!prompt.includes("THE KUNDALI LINE"));
  assert(prompt.includes("Name their rashi once, if the chart gives it"));

  // Handed a line anyway, a chart without the hour still gets none.
  const forced = buildUserPromptV5("x", context({ chart: noHour, firstReply: true, kundaliLine: { place: true, hopeful: true, matter: null } }));
  assert(!forced.includes("THE KUNDALI LINE"));
  assertEquals(kundaliLineFor(null, { timing: null, transits: null, question: null }), null);
});

Deno.test("the place of birth is named only when it is on file", () => {
  const withPlace = flat(buildUserPromptV5("x", kundaliContext(WHOLE, "x", { place: "Jaipur, Rajasthan" })));
  assert(withPlace.includes("Maine aapki janm tithi, samay aur sthan se kundali dekhi"));
  assert(withPlace.includes("their date, time and place of birth"));

  for (const place of [null, "", "   "]) {
    const without = flat(buildUserPromptV5("x", kundaliContext(WHOLE, "x", { place })));
    assert(without.includes("Maine aapki janm tithi aur samay se kundali dekhi"), JSON.stringify(place));
    assert(!without.includes("sthan"), JSON.stringify(place));
    assert(without.includes("never say or suggest the kundali used it"));
  }
});

Deno.test("the turn a captured hour completes the chart gets the line; one that does not, doesn't", () => {
  const whole = computeChart({ ...WHOLE, asOf: TODAY });
  const before = computeChart({ dob: WHOLE.dob, birthTime: null });
  // As `astro-chat` works it out: a detail captured, on a chart that was not whole before it.
  const completed = !hasWholeChart(before);
  const thread = [
    { role: "astro", body: { kind: "ask", ask_for: "birth_time", bubbles: ["Aap kis samay paida hue the?"] } },
    { role: "user", body: { text: "Meri shaadi kab hogi?" } },
  ];
  assert(kundaliLineTurn(thread, { chart: whole, completed, care: false }));
  // A later turn, nothing captured; or a corrected hour on a chart that was whole already.
  assert(!kundaliLineTurn(thread, { chart: whole, completed: false, care: false }));

  // On that turn the thanks come first, and the rashi is not "again".
  const captured = { field: "birth_time" as const, said: "5:30 AM", question: "Meri shaadi kab hogi?" };
  const prompt = flat(buildUserPromptV5("subah 5:30", { ...kundaliContext(WHOLE, "Meri shaadi kab hogi?", { first: false }), captured }));
  assert(prompt.includes("THE DETAIL THEY JUST GAVE: their hour of birth, 5:30 AM"));
  assert(prompt.includes("your thanks, and the detail said back, open this same message"));
  assert(prompt.includes("THE KUNDALI LINE is the one place it is named"));
  assert(!prompt.includes("do not name or explain their rashi again"));
});

Deno.test("the kundali line is said once in a thread, and never after a crisis", () => {
  const whole = computeChart({ ...WHOLE, asOf: TODAY });
  const body = v5Body(
    { kind: "answer", topic: "marriage", bubbles: ["a", "b"], offer: "none", options: [], askFor: "none" },
    { version: "v5", kundaliLine: true },
  );
  assertEquals(body.kundali_line, true);
  assert(!("kundali_line" in v5Body({ kind: "chat", topic: "general", bubbles: ["a"], offer: "none", options: [], askFor: "none" }, { version: "v5" })));

  const said = [{ role: "astro", body }, { role: "user", body: { text: "Meri shaadi kab hogi?" } }];
  assert(!kundaliLineTurn(said, { chart: whole, completed: false, care: false }), "a second turn");
  assert(!kundaliLineTurn(said, { chart: whole, completed: true, care: false }), "a second capture");
  assert(!kundaliLineTurn([], { chart: whole, completed: false, care: true }), "a flagged thread");
});

Deno.test("the time ahead is called good only when a window opens within the year", () => {
  const chart = computeChart({ ...WHOLE, asOf: TODAY });
  const timing = chatTiming(chart, { dob: WHOLE.dob, asOf: TODAY, v5: true })!;
  const transits = transitTiming(chart!.moonRashi, TODAY)!;
  assert(mattersOpeningSoon(timing, transits).includes("marriage"), "Guru's nearer season counts");
  const good = kundaliLineFor(chart, { timing, transits, question: "Meri shaadi kab hogi?" })!;
  assertEquals(good, { place: false, hopeful: true, matter: "marriage" });
  const goodBlock = flat(buildUserPromptV5("x", context({ chart, timing, transits, firstReply: true, kundaliLine: good })));
  assert(goodBlock.includes("good for marriage too — what they asked about. Name no other matter."));

  // Every window more than a year off: the softer, still true line, and no matter named.
  const startJd = timing.asOfJd + 400;
  const far = {
    ...timing,
    topics: timing.topics.map((topic) => ({
      ...topic,
      windows: topic.windows.map((w) => ({ ...w, now: false, startJd, endJd: startJd + 200 })),
    })),
  };
  assertEquals(mattersOpeningSoon(far, null), []);
  const soft = kundaliLineFor(chart, { timing: far, transits: null, question: "Meri shaadi kab hogi?" })!;
  assertEquals(soft, { place: false, hopeful: false, matter: null });
  const softBlock = flat(buildUserPromptV5("x", context({ chart, timing: far, firstReply: true, kundaliLine: soft })));
  assert(softBlock.includes("aur aapki kundali mein aage acche yog ban rahe hain"));
  assert(softBlock.includes("do not say the time ahead is good"));
  assert(!softBlock.includes("aane wala samay aapke liye accha"));
  assert(softBlock.includes("Name no matter in it"));

  // A withheld matter is never what makes the time ahead good.
  const withheld = { ...timing, topics: timing.topics.map((topic) => ({ ...topic, withheld: true })) };
  assertEquals(mattersOpeningSoon(withheld, transits), []);
});

Deno.test("the kundali line names only the matter they asked about, or none", () => {
  const chart = computeChart({ ...WHOLE, asOf: TODAY });
  const timing = chatTiming(chart, { dob: WHOLE.dob, asOf: TODAY, v5: true });
  const transits = transitTiming(chart!.moonRashi, TODAY);
  const matter = (question: string | null) => kundaliLineFor(chart, { timing, transits, question })!.matter;
  assertEquals(matter("naukri kab lagegi"), "career");
  assertEquals(matter("hi"), null);
  assertEquals(matter(null), null);

  // Their matter not opening within the year: the line praises the time ahead, and names nothing.
  const marriageLater = {
    ...timing!,
    topics: timing!.topics.map((topic) =>
      topic.topic === "marriage" ? { ...topic, windows: [] } : topic
    ),
  };
  const line = kundaliLineFor(chart, { timing: marriageLater, transits: null, question: "Meri shaadi kab hogi?" })!;
  assertEquals(line.hopeful, true);
  assertEquals(line.matter, null);
});

Deno.test("no kundali line above a death, an illness or despair; it waits for their next question", () => {
  const chart = computeChart({ ...WHOLE, asOf: TODAY });
  const timing = chatTiming(chart, { dob: WHOLE.dob, asOf: TODAY, v5: true });
  const transits = transitTiming(chart!.moonRashi, TODAY);
  const line = (question: string) =>
    kundaliLineFor(chart, { timing, transits, birthPlace: "Delhi", question });
  // Both seen live, with the whole chart: the line, then "main beemari nahi dekhta".
  for (
    const question of [
      "meri maa hospital mein admit hain, bahut dar lag raha hai, kya sab theek hoga?",
      "papa ka dehant pichle mahine ho gaya, ab ghar kaise chalega?",
      "Sehat kaisi rahegi?",
      // Live, with the block given: the model held the line back itself. Now the code does.
      "mere bete ki tabiyat bahut kharab hai, darr lag raha hai, kya wo theek ho jayega?",
      "पापा गुज़र गए, अब क्या होगा?",
      "mera accident hua tha, naukri milegi?",
      "ಅಪ್ಪ ನಿಧನರಾದರು, ಮುಂದೆ ಹೇಗೆ?",
      "அம்மா இறந்த பிறகு என்ன செய்வது?",
      // The words `detectCrisis` does not know.
      "जीने की इच्छा नहीं है, सब खत्म करना चाहती हूँ",
      "neend ki goliyan kha lun kya, ab aur nahi seh sakti",
    ]
  ) {
    assertEquals(line(question), null, question);
  }
  // A worry is not one: hope is what it asks for.
  for (const question of ["Shaadi ko lekar bahut pareshan hoon, kab hogi?", "naukri ki tension hai", "hi"]) {
    assert(line(question) !== null, question);
  }

  // Held back, it is marked owed; the next question on a matter gets it, a "thank you" does not.
  const held = v5Body(
    { kind: "chat", topic: "general", bubbles: ["Bahut dukh hua sunkar."], offer: "none", options: [], askFor: "none" },
    { version: "v5", kundaliLineOwed: true },
  );
  assertEquals(held.kundali_line_owed, true);
  assert(!("kundali_line" in held));
  const thread = [{ role: "astro", body: held }, { role: "user", body: { text: "papa ka dehant ho gaya" } }];
  const turn = (question: string, rows = thread) =>
    kundaliLineTurn(rows, { chart, completed: false, care: false, question });
  assert(turn("Aur meri naukri kab lagegi?"));
  assert(!turn("shukriya"));
  assert(!turn("Sehat kaisi rahegi?"));
  // Never twice, never after a care reply, and a thread nobody held it back in gets no late one.
  const said = [{ role: "astro", body: { ...held, kundali_line: true } }, ...thread];
  assert(!turn("Aur meri naukri kab lagegi?", said));
  const care = [{ role: "astro", body: { kind: "care", bubbles: ["Tele-MANAS 14416"] } }, ...thread];
  assert(!turn("Aur meri naukri kab lagegi?", care));
  const plain = [{ role: "astro", body: { kind: "answer", bubbles: ["a"] } }, { role: "user", body: { text: "x" } }];
  assert(!turn("Aur meri naukri kab lagegi?", plain));

  // The prompt holds it back too, for a fear the words above miss.
  const prompt = flat(buildUserPromptV5("x", kundaliContext(WHOLE, "x")));
  assert(prompt.includes("Never before sympathy. If they tell you of a loss, an illness, an accident or a fear, leave the line out"));
});

Deno.test("the kundali line leaves v4 alone: the v4 prompt carries none of it", () => {
  for (const language of ["Hinglish", "Hindi", "Kannada"]) {
    const v4 = chatSystemPrompt({ version: "v4", language });
    assert(!v4.includes("KUNDALI LINE"), language);
    assert(!v4.includes("‹rashi›"), language);
  }
});
