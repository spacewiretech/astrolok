import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  answersIn,
  answersSinceUpay,
  asksForUpay,
  describeUpay,
  indiaDay,
  onlyAsksForUpay,
  remediesGiven,
  topicsAnswered,
  turnTopic,
  UPAY_BY_THEN,
  UPAY_WITH_CONTEXT,
  upayDue,
  upayFor,
  upaysGiven,
  WEEKDAYS,
} from "../_shared/chat_upay.ts";
import { answersPlaceAsk } from "../_shared/chat_birth_place.ts";
import { asksFor, describeSawal, isGreeting, sawalFor, SawalContext, sawalsAsked } from "../_shared/chat_sawal.ts";
import {
  buildUserPromptV5,
  ChatContextV5,
  goodInChart,
  isRemedyAccept,
  MAX_BUBBLES,
  MAX_WORDS,
  normaliseChatReplyV5,
  notTheMoment,
  onTopicOptions,
  oneQuestion,
  REPLY_TOPICS,
  v5Body,
} from "../_shared/astro_chat_v5.ts";
import { changedDetails, saysOwnDetailWrong } from "../_shared/birth_details.ts";
import { chatTiming } from "../_shared/chat_timing.ts";
import { transitTiming } from "../_shared/chat_transits.ts";
import { chatSystemPrompt } from "../_shared/astro_chat.ts";
import { computeChart } from "../_shared/jyotish.ts";

/**
 * The v5 answer turn's arc (28 Sep): seedha jawab, kyun, the upay when it is due, one question.
 * The upay (`chat_upay.ts`) and the question (`chat_sawal.ts`) are decided in code, and the reply's
 * shape is assembled in code (`normaliseChatReplyV5`) — each rule asserted where it lives.
 */

const flat = (text: string) => text.replace(/\s+/g, " ");

/** 10:00 in India on each day of the week of 27 Sep 2026, Sunday first. */
const WEEK = [0, 1, 2, 3, 4, 5, 6].map((d) => new Date(Date.UTC(2026, 8, 27 + d, 4, 30)));
const MONDAY = WEEK[1];
const TUESDAY = WEEK[2];

// ---------------------------------------------------------------- the day in India

Deno.test("today is India's day, across midnight UTC and at India's midnight", () => {
  // 20:00 UTC on Sunday is 01:30 on Monday in India; 18:29 UTC is still Sunday, 23:59.
  assertEquals(indiaDay(new Date("2026-09-27T20:00:00Z")), { weekday: 1, hour: 1 });
  assertEquals(indiaDay(new Date("2026-09-27T18:29:00Z")), { weekday: 0, hour: 23 });
  assertEquals(indiaDay(new Date("2026-09-27T18:30:00Z")), { weekday: 1, hour: 0 });
  // 00:30 UTC on Monday is 06:00 on Monday; 23:00 UTC on Saturday is 04:30 on Sunday.
  assertEquals(indiaDay(new Date("2026-09-28T00:30:00Z")), { weekday: 1, hour: 6 });
  assertEquals(indiaDay(new Date("2026-10-03T23:00:00Z")).weekday, 0);
  WEEK.forEach((now, day) => assertEquals(indiaDay(now).weekday, day));
  assertEquals(WEEKDAYS[1].name, "Somvar");
  assertEquals(WEEKDAYS[2].graha, "Mangal");
});

Deno.test("an upay picked across India's midnight is the new day's", () => {
  // Late Sunday night UTC, already Monday in India: Monday's Shiv ji, not Sunday's.
  assertEquals(upayFor("marriage", { now: new Date("2026-09-27T20:00:00Z") }).id, "shiv_jal");
  assertEquals(upayFor("marriage", { now: new Date("2026-09-27T12:00:00Z") }).today, 0);
});

// ---------------------------------------------------------------- choosing one

const COSTLY = /gem|ratna|stone|yantra|amulet|taveez|tabeez|kavach|booking|paid|pandit ko|dakshina|vrat|fast|upvas|nirjala/i;

Deno.test("every topic, every day: one concrete upay with a day, a count and a length", () => {
  for (const topic of REPLY_TOPICS) {
    WEEK.forEach((now, day) => {
      const upay = upayFor(topic, { now });
      const label = `${topic} on ${WEEKDAYS[day].name}`;
      assertEquals(upay.topic, topic, label);
      assertEquals(upay.today, day, label);
      assert(upay.day >= 0 && upay.day <= 6, label);
      assert(upay.what && upay.times && upay.length && upay.why, label);
      assert(/\d|ek |roz/.test(upay.times), `${label}: how many times — ${upay.times}`);
      assert(/\d+ (?:hafte|din|Somvar)/.test(upay.length), `${label}: for how long — ${upay.length}`);
      assert(!COSTLY.test(`${upay.what} ${upay.times} ${upay.why}`), `${label}: ${upay.what}`);
      // "Today" means today, and a later start names the day it starts.
      if (upay.start === "today") assertEquals(upay.day, day, label);
      if (upay.start === "tomorrow") assertEquals(upay.day, (day + 1) % 7, label);

      const block = describeUpay(upay, { hook: null });
      assert(block.includes(`Today is ${WEEKDAYS[day].name}`), label);
      assert(block.includes(upay.times) && block.includes(upay.length), label);
    });
  }
});

Deno.test("they start today whenever the topic or today's deity allows it", () => {
  // The product team's own example: Tuesday, Hanuman Chalisa — for work and for debt alike.
  assertEquals(upayFor("career", { now: TUESDAY }).id, "hanuman_mangalvar");
  assertEquals(upayFor("debt", { now: TUESDAY }).id, "rin_mochan");
  // Monday, a shaadi question: none of shaadi's own falls on a Monday, so Shiv ji's 16 Somvar.
  const monday = upayFor("marriage", { now: MONDAY });
  assertEquals([monday.id, monday.start, monday.from, monday.length], ["shiv_jal", "today", "deity_today", "16 Somvar"]);
  // Friday is shaadi's own day; Thursday is kele ke ped mein jal.
  assertEquals(upayFor("marriage", { now: WEEK[5] }).id, "katyayani_mantra");
  assertEquals(upayFor("marriage", { now: WEEK[4] }).id, "kele_jal");
  // A general question gets the day's own deity.
  assertEquals(WEEK.map((now) => upayFor("general", { now }).id), [
    "surya_jal", "shiv_jal", "hanuman_mangalvar", "ganesh_durva", "kele_jal", "lakshmi_diya", "peepal_diya",
  ]);
});

Deno.test("with nothing for today, the topic's own upay names the day it starts", () => {
  // Monday, a debt: Rin Mochan on Mangalvar, which is tomorrow.
  const debt = upayFor("debt", { now: MONDAY });
  assertEquals([debt.id, debt.start, debt.day], ["rin_mochan", "tomorrow", 2]);
  assert(describeUpay(debt, { hook: null }).includes('"Kal Mangalvar hai — kal se shuru kijiye"'));
  // Monday, children: Santan Gopal is begun on a Guruvar.
  const children = upayFor("children", { now: MONDAY });
  assertEquals([children.id, children.start, children.day], ["santan_gopal", "next", 4]);
  assert(describeUpay(children, { hook: null }).includes('"Agle Guruvar se shuru kijiye"'));
  assert(describeUpay(children, { hook: null }).includes("every day, begun on a Guruvar"));
});

Deno.test("a morning upay asked for in the afternoon starts the next morning", () => {
  const afternoon = new Date("2026-09-28T10:30:00Z"); // 16:00 on Monday in India
  const career = upayFor("career", { now: afternoon });
  assertEquals([career.id, career.start, career.day], ["surya_jal", "tomorrow", 2]);
  assert(describeUpay(career, { hook: null }).includes('"Kal subah se shuru kijiye"'));
  // A Thursday afternoon's kele ke ped mein jal would wait a week, so Friday's mantra, tomorrow;
  // a daan is not a morning practice, and is still today's.
  const thursday = new Date("2026-10-01T11:30:00Z");
  const marriage = upayFor("marriage", { now: thursday });
  assertEquals([marriage.id, marriage.start], ["katyayani_mantra", "tomorrow"]);
  assertEquals(upayFor("marriage", { now: thursday, given: ["katyayani_mantra", "safed_mithai"] }).start, "next");
  assertEquals(upayFor("money", { now: thursday }).id, "peeli_daan");
});

Deno.test("a health worry gets Hanuman Chalisa and a doctor, and nothing else, any day", () => {
  for (const now of WEEK) {
    const upay = upayFor("health", { now });
    assertEquals([upay.id, upay.doctor, upay.length], ["hanuman_roz", true, "40 din"]);
    assert(describeUpay(upay, { hook: null }).includes('"Doctor se zaroor milein."'));
  }
  assertEquals(upayFor("health", { now: MONDAY, given: ["hanuman_roz"] }).id, "hanuman_roz");
  assertEquals(upayFor("marriage", { now: MONDAY }).doctor, false);
});

Deno.test("a government job reads the exam row first", () => {
  assertEquals(upayFor("career", { now: WEEK[3], said: "sarkari naukri kab lagegi" }).id, "ganesh_durva");
  assertEquals(upayFor("career", { now: WEEK[3], said: "naukri kab lagegi" }).id, "surya_jal");
  assertEquals(upayFor("studies", { now: WEEK[3] }).id, "ganesh_durva");
});

Deno.test("no remedy twice in a thread, until every one that suits the topic is used", () => {
  for (const topic of REPLY_TOPICS.filter((t) => t !== "health")) {
    for (const now of WEEK) {
      const given: string[] = [];
      for (let i = 0; i < 4; i++) {
        const upay = upayFor(topic, { now, given });
        if (upay.from === "repeat") break;
        assert(!given.includes(upay.id), `${topic}: ${upay.id} twice`);
        given.push(upay.id);
      }
      assert(given.length >= 2, `${topic}: only ${given}`);
    }
  }
  // The same remedy under two topics is still the same remedy: Hanuman Chalisa for work on a
  // Tuesday, and then Rin Mochan — not Hanuman Chalisa again — for the debt.
  assertEquals(upayFor("debt", { now: TUESDAY, given: ["hanuman_mangalvar"] }).id, "rin_mochan");
  assertEquals(upayFor("career", { now: TUESDAY, given: ["hanuman_mangalvar"] }).id, "surya_jal");
});

Deno.test("the running dasha breaks a tie, and the why says so only when it does", () => {
  const now = MONDAY;
  const chart = computeChart({ dob: "1999-10-17", birthTime: "23:55", asOf: now })!; // Rahu–Shani
  assertEquals([chart.dasha!.mahadasha, chart.dasha!.antardasha], ["Rahu", "Shani"]);
  // Two for later, a Thursday's and a Friday's: nothing favours either, so the sooner.
  assertEquals(upayFor("money", { now, chart }).id, "peeli_daan");
  // A mini kundli's weak Shukra, when there is one, favours Friday's.
  const weak = upayFor("money", { now, chart, weakGrahas: ["Shukra"] });
  assertEquals(weak.id, "lakshmi_diya");
  assertEquals(weak.strengthens, { graha: "Shukra", because: "kundali" });
  assert(describeUpay(weak, { hook: null }).includes("it strengthens Shukra, which their kundali wants stronger"));
  // Shani's own day, in Shani's Antardasha: the why names it; on a day that is not his, it does not.
  const saturday = upayFor("career", { now: WEEK[6], chart: computeChart({ dob: "1999-10-17", birthTime: "23:55", asOf: WEEK[6] }) });
  assertEquals(saturday.id, "shani_tel");
  assert(describeUpay(saturday, { hook: null }).includes("it pleases Shani, whose Antardasha runs now"));
  assertEquals(upayFor("career", { now, chart }).strengthens, null);
});

Deno.test("the upay block gives the facts, forbids changing them, and carries the hook once", () => {
  const block = flat(describeUpay(upayFor("marriage", { now: MONDAY }), { hook: "return" }));
  assert(block.includes("Today is Somvar (Monday) in India"));
  assert(block.includes("- What: Shiv ji ko jal chadhaiye."));
  assert(block.includes('Today is Somvar, so they start today: "Aaj Somvar hai — aaj se shuru kijiye"'));
  assert(block.includes("- How many times, for how long: ek lota, 16 Somvar."));
  assert(block.includes("Never another day, count or length, never a second upay"));
  assert(block.includes("never promise one"));
  assert(flat(describeUpay(upayFor("marriage", { now: MONDAY }), { hook: "plan" })).includes("agle 3 mahine ka poora plan"));
  assert(flat(describeUpay(upayFor("marriage", { now: MONDAY }), { hook: null })).includes("already given this session"));
});

// ---------------------------------------------------------------- asking for one

Deno.test("an upay asked for is heard in every script", () => {
  for (
    const said of [
      "upay batao", "Koi upaay hai?", "shaadi ke liye upaye", "koi totka batao", "any remedy for marriage?",
      "Haan, upay batao 🙏", "koi mantra batao", "koi samadhan?",
      "कोई उपाय बताइए", "शादी का टोटका", "ಪರಿಹಾರ ಹೇಳಿ", "ನನಗೆ ಉಪಾಯ ಬೇಕು", "பரிகாரம் சொல்லுங்கள்",
      "పరిహారం చెప్పండి", "പരിഹാരം പറയൂ", "लग्नासाठी उपाय सांगा",
    ]
  ) {
    assert(asksForUpay(said), said);
  }
  for (const said of ["meri shaadi kab hogi?", "haan", "upayog", "totally", "ಮದುವೆ ಯಾವಾಗ", "ok thank you", ""]) {
    assert(!asksForUpay(said), said);
  }
});

Deno.test("after an upay, a question about it is not a wish for another; asking for another is", () => {
  for (const said of ["upay kaise karun?", "upay kab tak karna hai?", "kya ye upay kaam karega?", "उपाय कैसे करूँ?", "Will the remedy work?"]) {
    assert(!asksForUpay(said, { given: true }), said);
    // Before one is given, a question about upays still asks for one.
    assert(asksForUpay(said), said);
  }
  for (const said of ["aur koi upay batao", "dusra upay?", "one more remedy please", "ಇನ್ನೊಂದು ಪರಿಹಾರ", "और उपाय कैसे करूँ"]) {
    assert(asksForUpay(said, { given: true }), said);
  }
  assert(asksForUpay("shaadi ka upay batao", { given: true }));
});

// ---------------------------------------------------------------- when one is due

const ENOUGH = { dob: true, hour: true, place: true };
const due = (over: Partial<Parameters<typeof upayDue>[0]> = {}) =>
  upayDue({ topic: "marriage", message: "shaadi kab hogi?", answers: 0, care: false, context: ENOUGH, ...over });

Deno.test("the upay comes on the third answer with enough to go on, and the fourth anyway", () => {
  assertEquals([UPAY_WITH_CONTEXT, UPAY_BY_THEN], [3, 4]);
  assertEquals(due({ answers: 0 }), null);
  assertEquals(due({ answers: 1 }), null);
  assertEquals(due({ answers: 2 }), { because: "enough" });
  // The third without enough: not yet — the fourth, whatever is missing.
  for (const missing of ["dob", "hour", "place"] as const) {
    assertEquals(due({ answers: 2, context: { ...ENOUGH, [missing]: false } }), null, missing);
    assertEquals(due({ answers: 3, context: { ...ENOUGH, [missing]: false } }), { because: "fourth" }, missing);
  }
  assertEquals(due({ answers: 7, context: { dob: false, hour: false, place: false } }), { because: "fourth" });
});

Deno.test("asked for, it comes now; never in a care thread, above a loss, or twice on a topic", () => {
  assertEquals(due({ message: "shaadi ka upay batao" }), { because: "asked" });
  assertEquals(due({ message: "koi upay batao", topic: "general" }), { because: "asked" });
  assertEquals(due({ care: true, message: "upay batao", answers: 5 }), null);
  assertEquals(due({ sorrow: true, message: "upay batao", answers: 5 }), null);
  // A topic whose upay was given: only when they ask for another.
  assertEquals(due({ answers: 5, given: ["marriage"] }), null);
  assertEquals(due({ answers: 5, given: ["marriage"], message: "upay kaise karun?" }), null);
  assertEquals(due({ answers: 5, given: ["marriage"], message: "aur koi upay?" }), { because: "asked" });
  // Another topic's upay does not count against this one.
  assertEquals(due({ answers: 5, given: ["career"] }), { because: "fourth" });
  // A general chat is never given one unasked.
  assertEquals(due({ topic: "general", answers: 5 }), null);
  assert(notTheMoment("papa ka dehant ho gaya, koi upay?"));
  assert(!notTheMoment("shaadi ki tension hai, koi upay?"));
});

const astro = (body: Record<string, unknown>) => ({ role: "astro", body });
const user = (text: string) => ({ role: "user", body: { text } });

Deno.test("the thread remembers answers, upays given — old remedy turns too — and questions asked", () => {
  const rows = [
    astro({ kind: "answer", topic: "career", upay_topic: "career", upay_id: "surya_jal", sawal_id: "career.field" }),
    user("naukri kab lagegi"),
    astro({ kind: "remedy", topic: "marriage" }), // served from an offer, before 28 Sep
    user("Haan, upay batao 🙏"),
    astro({ kind: "answer", topic: "marriage", offer: "remedy", remedy_bubbles: ["x"], ask_for: "birth_place" }),
    astro({ kind: "chat", topic: "general", ask_for: "dob" }),
    astro({ kind: "care", topic: "general" }),
    astro({ kind: "answer", upay_id: "not-a-remedy" }),
  ];
  assertEquals(answersIn(rows), 3);
  assertEquals(remediesGiven(rows).sort(), ["career", "marriage"]);
  assertEquals(upaysGiven(rows), ["surya_jal"]);
  assertEquals(sawalsAsked(rows), ["career.field"]);
  assertEquals([asksFor(rows, "birth_place"), asksFor(rows, "dob")], [1, 1]);
});

Deno.test("a turn is about what it names, or the thread's subject when it names nothing", () => {
  const thread = [astro({ kind: "answer", topic: "marriage" }), user("meri shaadi kab hogi?")];
  assertEquals(turnTopic("naukri kab lagegi", []), "career");
  assertEquals(turnTopic("kab tak?", thread), "marriage");
  assertEquals(turnTopic("Ghar wale dhoond rahe hain", thread), "marriage");
  assertEquals(turnTopic("hi", []), "general");
  assertEquals(turnTopic("upay batao", []), "general");
  // Two subjects: the thread's own when it is one of them, else marriage before work.
  assertEquals(turnTopic("Shaadi ke baad naukri karun?", [astro({ topic: "career" })]), "career");
  assertEquals(turnTopic("Shaadi ke baad naukri karun?", []), "marriage");
  assertEquals(turnTopic("ನನ್ನ ಮದುವೆ ಯಾವಾಗ", []), "marriage");
});

// ---------------------------------------------------------------- the sawal

const SAWAL: SawalContext = {
  topic: "marriage",
  message: "meri shaadi kab hogi?",
  care: false,
  dob: true,
  hour: true,
  place: true,
  hourAsks: { asked: 0, declined: false },
  dobAsks: 0,
  placeAsks: 0,
  asked: [],
};
const sawal = (over: Partial<SawalContext> = {}) => sawalFor({ ...SAWAL, ...over });

Deno.test("the sawal asks for the date, then the hour, then the place, then about them", () => {
  const all = { dob: false, hour: false, place: false };
  assertEquals([sawal(all).about, sawal(all).askFor], ["dob", "dob"]);
  assertEquals(sawal({ ...all, dob: true }).askFor, "birth_time");
  assertEquals(sawal({ hour: true, place: false }).askFor, "birth_place");
  const about = sawal();
  assertEquals([about.about, about.askFor, about.question?.id], ["situation", "none", "marriage.who_looks"]);

  // Each once: the hour asked or declined, the place asked — on to the next.
  assertEquals(sawal({ hour: false, place: false, hourAsks: { asked: 1, declined: false } }).askFor, "birth_place");
  assertEquals(sawal({ hour: false, hourAsks: { asked: 0, declined: true } }).askFor, "none");
  assertEquals(sawal({ place: false, placeAsks: 1 }).about, "situation");
  // The date not on file is asked twice at most; with no chart there is nothing to time.
  assertEquals(sawal({ dob: false, dobAsks: 2 }).about, "situation");
});

Deno.test("a detail asked again: the date or hour called wrong, one unreadable, an hour without am/pm", () => {
  assertEquals([sawal({ message: "meri DOB galat hai" }).askFor, sawal({ message: "meri DOB galat hai" }).because], ["dob", "wrong"]);
  assertEquals(sawal({ message: "mera birth time galat save hai" }).because, "wrong");
  assertEquals(sawal({ message: "mera birth time galat save hai" }).askFor, "birth_time");
  assertEquals(sawal({ captureFailed: "dob", dobAsks: 1 }).because, "unreadable");
  assertEquals(sawal({ hour: false, captureFailed: "birth_time", hourAsks: { asked: 1, declined: false } }).because, "unreadable");
  assertEquals(sawal({ hour: false, unsettled: true, hourAsks: { asked: 1, declined: false } }).because, "unsettled");
  // Once more, not forever; and never over a "don't know".
  assertEquals(sawal({ hour: false, unsettled: true, hourAsks: { asked: 2, declined: false } }).askFor, "none");
  assertEquals(sawal({ hour: false, unsettled: true, hourAsks: { asked: 1, declined: true } }).askFor, "none");
  // What was just saved is not asked for again.
  assertEquals(sawal({ message: "meri DOB galat hai, sahi 3 Jan 2000", captured: "dob" }).about, "situation");
});

Deno.test("a detail is called wrong only when it is theirs and it is said outright", () => {
  const cases: Array<[string, "dob" | "birth_time" | null]> = [
    ["meri DOB galat hai", "dob"],
    ["meri date galat hai", "dob"],
    ["मेरी जन्मतिथि गलत है", "dob"],
    ["ನನ್ನ ದಿನಾಂಕ ತಪ್ಪು", "dob"],
    ["mera birth time galat hai", "birth_time"],
    ["mera time galat hai", "birth_time"],
    ["जन्म समय गलत है", "birth_time"],
    ["shaadi ka sahi time kab hai?", null],
    ["galat date bata rahe ho aap", null],
    ["papa ki DOB galat hai", null],
    ["meri shaadi kab hogi", null],
  ];
  for (const [said, detail] of cases) assertEquals(saysOwnDetailWrong(said), detail, said);
});

Deno.test("never a situational question twice; a greeting is asked what they want; care, only about them", () => {
  assertEquals(sawal({ asked: ["marriage.who_looks"] }).question?.id, "marriage.talks");
  const done = sawal({ asked: ["marriage.who_looks", "marriage.talks", "marriage.since", "marriage.hopes"] });
  assertEquals([done.about, done.question], ["situation", null]);
  assert(describeSawal(done).includes("Never one of the questions already asked in this conversation: whether the family is looking"));

  // "hi" before the hour: what would they like to know, not a form.
  const hi = sawal({ topic: "general", message: "Namaste ji 🙏", hour: false, place: false });
  assertEquals([hi.about, hi.askFor, hi.question?.id], ["situation", "none", "general.mind"]);
  for (const said of ["hi", "Hello", "namaste", "ನಮಸ್ಕಾರ", "வணக்கம்", "राम राम"]) assert(isGreeting(said), said);
  for (const said of ["hi, shaadi kab hogi?", "namaste, naukri?"]) assert(!isGreeting(said), said);

  const care = sawal({ care: true, hour: false, place: false, dob: false });
  assertEquals([care.about, care.askFor], ["care", "none"]);
  assert(describeSawal(care).includes("Never a birth detail"));
});

Deno.test("every topic has a question, and every question's answers pass the topic's chip guard", () => {
  for (const topic of REPLY_TOPICS) {
    const plan = sawal({ topic });
    assert(plan.question, topic);
    const block = describeSawal(plan);
    assert(block.includes(plan.question!.example), topic);
    // The example answers are what the options are meant to look like; none may be dropped.
    assertEquals(onTopicOptions(plan.question!.answers, { topic, answers: true }), [...plan.question!.answers], topic);
  }
});

Deno.test("the place question names a place said once, and never asks it as if unknown", () => {
  const plan = sawal({ place: false });
  assert(describeSawal(plan).includes('"Aap kis shehar ya kasbe mein paida hue the?'));
  assert(describeSawal(plan, { placeSaid: "Kota" }).includes('"Aapne janm sthan Kota bataya tha'));
});

// ---------------------------------------------------------------- the review of 28 Sep

Deno.test("a Mangal dosh or a fear gets the table's Hanuman Chalisa every day, whatever the day", () => {
  // Section E: "Health worry / Mangal dosh / dar: Hanuman Chalisa roz, 40 din". These read as no
  // subject, and a Monday got Shiv ji's jal, a Tuesday the weekly Chalisa.
  for (
    const said of [
      "Mangal dosh ka upay batao",
      "Main manglik hoon, koi upay batao",
      "Mujhe bahut dar lagta hai, koi upay?",
      "मंगल दोष का उपाय बताइए",
      "मैं मांगलिक हूँ",
      "ಕುಜ ದೋಷ ಇದೆ, ಪರಿಹಾರ ಹೇಳಿ",
      "செவ்வாய் தோஷம் இருக்கிறது",
      "I am scared, any remedy?",
    ]
  ) {
    for (const now of [MONDAY, TUESDAY, WEEK[5]]) {
      const topic = turnTopic(said, []);
      assertEquals(upayDue({ topic, message: `${said} upay`, answers: 0, care: false, context: ENOUGH })?.because, "asked", said);
      const upay = upayFor(topic, { now, said });
      assertEquals([upay.id, upay.times, upay.length, upay.from, upay.doctor], ["hanuman_roz", "roz ek baar", "40 din", "dosh", false], said);
      assertEquals(upay.start, "today", said);
    }
  }
  // The dosh's why is Hanuman ji as Mangal's devta — never a threat.
  assert(upayFor("marriage", { now: MONDAY, said: "main manglik hoon" }).why.includes("Mangal ke devta"));
  // Given once in the thread, the subject's own comes next; a worry or "bhayankar" is not a fear.
  assertEquals(upayFor("marriage", { now: MONDAY, said: "manglik hoon", given: ["hanuman_roz"] }).id, "shiv_jal");
  for (const said of ["shaadi ki bahut tension hai", "chinta ho rahi hai", "bhayankar garmi hai", "darshan karne jaana hai"]) {
    assert(upayFor("marriage", { now: MONDAY, said }).id !== "hanuman_roz", said);
  }
});

Deno.test("the invitation back fits when the upay starts: tomorrow only for one begun today", () => {
  // Live: "agle Guruvar se shuru kijiye … kal wapas aaiye, iska asar dekhte hain", in Hindi and
  // Kannada.
  const hook = (upay: ReturnType<typeof upayFor>) =>
    flat(describeUpay(upay, { hook: "return" })).split("- THE HOOK:")[1];
  const today = upayFor("marriage", { now: MONDAY });
  assertEquals(today.start, "today");
  assert(hook(today).includes('"Kal wapas aaiye, upay ka asar dekhte hain."'));

  const next = upayFor("money", { now: MONDAY });
  assertEquals([next.start, WEEKDAYS[next.day].name], ["next", "Guruvar"]);
  assert(hook(next).includes('"Guruvar ko shuru karke wapas aaiye — bataiye kaisa laga."'));
  assert(hook(next).includes('Never "kal wapas aaiye"'));

  const tomorrow = upayFor("debt", { now: MONDAY });
  assertEquals(tomorrow.start, "tomorrow");
  assert(hook(tomorrow).includes('"Kal Mangalvar ko shuru karke wapas aaiye'));
  const morning = upayFor("career", { now: new Date("2026-09-28T10:30:00Z") });
  assert(hook(morning).includes('"Kal subah shuru karke wapas aaiye'));
  // The plan's hook, and none at all, are as they were.
  assert(!flat(describeUpay(next, { hook: null })).includes("wapas aaiye"));
});

Deno.test("after an upay, the next one waits for the third or fourth answer since it", () => {
  // Live: "Ghar kab banega?" got Hanuman ji's laal phool, and the very next turn, "Karz kab
  // utrega?", Rin Mochan — each the first answer on a new subject.
  const after = (answers: number) => [
    ...Array.from({ length: answers }, () => astro({ kind: "answer", topic: "career" })),
    astro({ kind: "answer", topic: "home", upay_topic: "home", upay_id: "hanuman_phool" }),
    astro({ kind: "answer", topic: "home" }),
    astro({ kind: "answer", topic: "home" }),
  ];
  assertEquals(answersSinceUpay(after(0)), 0);
  assertEquals(answersSinceUpay(after(2)), 2);
  assertEquals(answersSinceUpay([astro({ kind: "answer" }), astro({ kind: "remedy", topic: "money" })]), 1);
  assertEquals(answersSinceUpay([astro({ kind: "answer" })]), null);

  const next = (rows: ReturnType<typeof after>, over: Partial<Parameters<typeof upayDue>[0]> = {}) =>
    due({ topic: "debt", message: "Karz kab utrega?", answers: answersIn(rows), sinceUpay: answersSinceUpay(rows), given: remediesGiven(rows), ...over });
  assertEquals(next(after(0)), null);
  assertEquals(next(after(1)), null);
  assertEquals(next(after(2)), { because: "enough" });
  assertEquals(next(after(2), { context: { ...ENOUGH, place: false } }), null);
  assertEquals(next(after(3), { context: { ...ENOUGH, place: false } }), { because: "fourth" });
  // Asked for, it still comes at once.
  assertEquals(next(after(0), { message: "karz ka upay batao" })?.because, "asked");
});

Deno.test("a long thread, read whole: no remedy and no invitation back given twice", () => {
  // `astro-chat` counts from every reply in the thread (`readArc`), not the prompt's twenty rows:
  // a Monday marriage thread gave Shiv ji's jal and the hook on turn 3 and again on turn 14.
  const rows: Array<{ role: string; body: Record<string, unknown> }> = [];
  const given: string[] = [];
  let hooks = 0;
  const topics = ["marriage", "marriage", "marriage", "marriage", "money", "home", "debt", "marriage", "career", "career", "career", "career", "marriage", "marriage", "marriage", "marriage"];
  for (const topic of topics) {
    const upay = due({
      topic,
      message: "aur batao",
      answers: answersIn(rows),
      sinceUpay: answersSinceUpay(rows),
      given: remediesGiven(rows),
    })
      ? upayFor(topic, { now: MONDAY, given: upaysGiven(rows) })
      : null;
    const hook = upay !== null && !rows.some((row) => row.body.hook === true);
    if (upay) given.push(upay.id);
    if (hook) hooks++;
    rows.unshift(user("aur batao"));
    rows.unshift(astro({ kind: "answer", topic, ...(upay ? { upay_topic: topic, upay_id: upay.id } : {}), ...(hook ? { hook: true } : {}) }));
  }
  assertEquals(given, ["shiv_jal", "hanuman_phool", "surya_jal"]);
  assertEquals(new Set(given).size, given.length);
  assertEquals(hooks, 1);
  // And the twenty newest rows alone would have lost the first: the reason for reading it whole.
  assertEquals(remediesGiven(rows.slice(0, 20)).includes("marriage"), false);
});

Deno.test("an upay asked for alone, after its answer, is the answer: the window is not said again", () => {
  // Live: "कोई उपाय बताइए" restated "अगस्त 2027 से जुलाई 2028" and its reason word for word.
  const thread = [astro({ kind: "answer", topic: "marriage" }), user("meri shaadi kab hogi?")];
  assertEquals(topicsAnswered(thread), ["marriage"]);
  for (const said of ["कोई उपाय बताइए", "upay batao", "ಪರಿಹಾರ ಹೇಳಿ", "Shaadi jaldi ho iske liye upay batao"]) {
    const topic = turnTopic(said, thread);
    assert(onlyAsksForUpay(said), said);
    assertEquals(due({ topic, message: said, answered: topicsAnswered(thread) }), { because: "asked", afterAnswer: true }, said);
  }
  // Not when it asks for the window too, nor before any answer on the subject.
  assertEquals(due({ topic: "debt", message: "karz kab utrega, koi upay bhi?", answered: ["debt"] }), { because: "asked" });
  assertEquals(due({ message: "upay batao", answered: [] }), { because: "asked" });

  const upay = upayFor("marriage", { now: MONDAY });
  const block = flat(describeUpay(upay, { hook: "return", afterAnswer: true }));
  assert(block.includes("THEY ASKED ONLY FOR THE UPAY"));
  assert(block.includes("Never the window, the dasha or the reason again"));
  assert(!flat(describeUpay(upay, { hook: "return" })).includes("THEY ASKED ONLY FOR THE UPAY"));
  // The prompt carries it through.
  assert(flat(buildUserPromptV5("upay batao", context({ upay, upayAfterAnswer: true }))).includes("THEY ASKED ONLY FOR THE UPAY"));
  // And a reply that leaves the answer out is the upay and the sawal.
  const reply = shape({ ...REPLY, answer: [] }, { upay: true });
  assertEquals(reply.bubbles, [REPLY.upay, REPLY.sawal]);
});

Deno.test("a question about the upay given, with an \"and\" or an \"or\", is not a wish for another", () => {
  for (
    const said of [
      "Upay kaise karna hai aur kab tak?",
      "ye upay subah karna hai or shaam ko?",
      "upay mein kya bolna hai aur kitni baar?",
      "is upay ka asar kab dikhega aur kaise pata chalega?",
      "should I do the remedy in the morning or evening?",
      "उपाय सुबह करना है या शाम को?",
    ]
  ) {
    assertEquals(asksForUpay(said, { given: true }), false, said);
    assertEquals(due({ message: said, answers: 5, given: ["marriage"] }), null, said);
  }
  for (const said of ["aur koi upay batao", "koi aur upay?", "upay aur batao", "one more remedy please", "dusra upay?", "और उपाय बताइए", "ಇನ್ನೊಂದು ಪರಿಹಾರ ಹೇಳಿ"]) {
    assert(asksForUpay(said, { given: true }), said);
  }
});

Deno.test("a question on no subject the chat reads is asked what is behind it, not to pick one", () => {
  // Live: a Tamil question about one person was asked "shaadi, naukri ya paisa?".
  for (
    const [said, topic] of [
      ["அவர் மீண்டும் என்னிடம் பேசுவாரா?", "love"],
      ["ಅವನು ಮತ್ತೆ ನನ್ನ ಜೊತೆ ಮಾತಾಡ್ತಾನಾ?", "love"],
      ["kya wo kisi aur se baat kar raha hai", "love"],
      ["wo dobara mujhse baat karega?", "love"],
      ["videsh mein settle ho paunga?", "career"],
      ["विदेश जाने का योग है?", "career"],
    ] as const
  ) {
    assertEquals(turnTopic(said, []), topic, said);
    assert(sawal({ topic, message: said }).question?.id.startsWith(`${topic}.`), said);
  }
  // Still no subject: what lies behind it — never the topic picker.
  const unnamed = sawal({ topic: "general", message: "Mangal dosh ka upay batao" });
  assertEquals(unnamed.question?.id, "general.behind");
  assertEquals(sawal({ topic: "general", message: "Mangal dosh ka upay batao", asked: ["general.behind"] }).question?.id, "general.since");
  assert(!describeSawal(unnamed).includes("shaadi, naukri ya paisa"));
  // A greeting, or a message that asks nothing, is asked what is on their mind.
  assertEquals(sawal({ topic: "general", message: "Namaste ji" }).question?.id, "general.mind");
  assertEquals(sawal({ topic: "general", message: "main theek hoon" }).question?.id, "general.mind");
  // Look-alikes stay off the subject.
  for (const said of ["kisi aur shehar mein naukri", "paisa wapas milega?"]) assert(turnTopic(said, []) !== "love", said);
});

Deno.test("under a death, an accident or despair, the sawal is about them — never a birth detail", () => {
  for (
    const said of [
      "Papa ka dehant pichle mahine ho gaya, ab ghar kaise chalega?",
      "Meri maa ka accident ho gaya, wo hospital mein hain",
    ]
  ) {
    const sorrow = notTheMoment(said);
    assert(sorrow, said);
    // Without the hour, and without the place: neither is asked, and no button is raised.
    for (const missing of [{ hour: false, place: false }, { place: false }]) {
      const plan = sawal({ topic: "general", message: said, sorrow, ...missing });
      assertEquals([plan.about, plan.askFor], ["sorrow", "none"], said);
      const block = describeSawal(plan);
      assert(block.includes("how they are holding up") && block.includes("Never a birth detail"), said);
    }
    // Nor an upay.
    assertEquals(due({ message: said, sorrow, answers: 5 }), null, said);
  }
  // The ask waits for the next turn: nothing was stored as asked.
  assertEquals(sawal({ hour: false, place: false }).askFor, "birth_time");
});

Deno.test("an idiom is not a birth detail called wrong, and one said again the same is no change", () => {
  // "I'm going through a bad phase", a wedding date, a job: each was asked for the "correct" hour,
  // date or place, and the hour said back again re-cast an unchanged kundali.
  for (
    const said of [
      "Mera time galat chal raha hai, kab theek hoga?",
      "mera samay kharab chal raha hai, galat ho raha hai sab",
      "maine galat date par shaadi fix ki kya?",
      "maine galat jagah naukri le li",
    ]
  ) {
    assertEquals(saysOwnDetailWrong(said), null, said);
    assertEquals(sawal({ message: said }).about, "situation", said);
  }
  for (const [said, detail] of [["mera time galat hai", "birth_time"], ["meri date galat hai", "dob"], ["mera janm sthan galat hai", "birth_place"]] as const) {
    assertEquals(saysOwnDetailWrong(said), detail, said);
  }
  // A date called wrong is asked for twice in a thread at most, like the hour and the place.
  assertEquals(sawal({ message: "meri DOB galat hai", dobAsks: 1 }).about, "dob");
  assertEquals(sawal({ message: "meri DOB galat hai", dobAsks: 2 }).about, "situation");
  // The same hour or date again changes nothing, so nothing is written and nothing is re-cast.
  assertEquals(changedDetails({ birth_time: "07:00" }, { birth_time: "07:00:00" }), {});
  assertEquals(changedDetails({ dob: "1998-08-15" }, { dob: "1998-08-15", birth_time: null }), {});
  assertEquals(changedDetails({ birth_time: "07:30" }, { birth_time: "07:00:00" }), { birth_time: "07:30" });
  assertEquals(changedDetails({ dob: "1998-08-16", birth_time: "07:00" }, { dob: "1998-08-15", birth_time: "07:00" }), { dob: "1998-08-16" });
  assertEquals(changedDetails({ birth_time: "07:00" }, { birth_time: null }), { birth_time: "07:00" });
});

Deno.test("the reply to the place ask is about the thread's subject, whatever the place is called", () => {
  // Live (review): "Laxmi Nagar, Delhi" in a shaadi thread gave the upay for money.
  const thread = [
    astro({ kind: "answer", topic: "marriage", ask_for: "birth_place" }),
    user("subah 7 baje"),
    astro({ kind: "answer", topic: "marriage", ask_for: "birth_time" }),
    user("Meri shaadi kab hogi?"),
  ];
  for (const said of ["Laxmi Nagar, Delhi, India", "Hospital Road, Jaipur", "Prem Nagar, Dehradun", "School Road, Kanpur"]) {
    assert(answersPlaceAsk(thread, undefined, said), said);
    assertEquals(turnTopic("", thread), "marriage", said);
    assert(turnTopic(said, thread) !== "marriage" || said === "Prem Nagar, Dehradun", said);
  }
  // A picked row is a place answer even when nothing asked for it; a new question is not one.
  assert(answersPlaceAsk([astro({ kind: "answer", topic: "marriage" })], { place_id: "ChIJlaxmi", description: "Laxmi Nagar, Delhi, India" }, "Laxmi Nagar, Delhi, India"));
  assert(!answersPlaceAsk(thread, undefined, "Jaipur. Aur naukri kab lagegi?"));
  assert(!answersPlaceAsk([astro({ kind: "answer", topic: "marriage" })], undefined, "Laxmi Nagar, Delhi"));
});

// ---------------------------------------------------------------- the reply's shape

const REPLY = {
  kind: "answer",
  topic: "marriage",
  answer: ["Ayush ji, ‹window› shaadi ka sabse accha samay hai.", "Is time Shukra ki dasha chalegi, jo rishton ke liye shubh hai."],
  upay: "Aaj Somvar hai — aaj se shuru kijiye: 16 Somvar Shiv ji ko jal chadhaiye. Kal wapas aaiye, upay ka asar dekhte hain.",
  sawal: "Rishta ghar wale dhoond rahe hain ya aap khud?",
  options: ["Ghar wale dhoond rahe hain", "Meri apni pasand hai", "Naukri kab lagegi?"],
};
const shape = (raw: unknown, over: Partial<Parameters<typeof normaliseChatReplyV5>[1]> = {}) =>
  normaliseChatReplyV5(raw, { language: "Hinglish", hourAsked: false, ...over })!;

Deno.test("a reply is assembled in order: jawab, kyun, upay, sawal — four messages at most", () => {
  const reply = shape(REPLY, { upay: true });
  assertEquals(reply.bubbles, [...REPLY.answer, REPLY.upay, REPLY.sawal]);
  assert(reply.bubbles.length <= MAX_BUBBLES);
  assertEquals([reply.upay, reply.sawal], [REPLY.upay, REPLY.sawal]);
  // The answers to the sawal are the options, and one off the topic still goes.
  assertEquals(reply.options, ["Ghar wale dhoond rahe hain", "Meri apni pasand hai"]);
  // Stored so the thread knows what it gave and asked, and so an old build renders it.
  const body = v5Body(reply, {
    version: "v5",
    hook: true,
    upay: upayFor("marriage", { now: MONDAY }),
    sawalId: "marriage.who_looks",
  });
  assertEquals([body.upay_topic, body.upay_id, body.upay_day, body.sawal_id, body.hook], ["marriage", "shiv_jal", "Somvar", "marriage.who_looks", true]);
  assertEquals(body.verdict, REPLY.answer[0]);
  assertEquals(body.offer, "none");
  assertEquals(remediesGiven([{ role: "astro", body }]), ["marriage"]);
  assertEquals(upaysGiven([{ role: "astro", body }]), ["shiv_jal"]);
});

Deno.test("a chat is its message and the sawal; an ask its question alone; care keeps its helpline", () => {
  const chat = shape({ ...REPLY, kind: "chat", answer: ["Aapka swagat hai 🙏"], upay: "" });
  assertEquals(chat.bubbles, ["Aapka swagat hai 🙏", REPLY.sawal]);

  const ask = shape({ ...REPLY, kind: "ask", answer: [], upay: REPLY.upay, sawal: "Aap kis samay paida hue the?" }, { upay: true, askFor: "birth_time" });
  assertEquals([ask.kind, ask.bubbles, ask.upay, ask.askFor], ["ask", ["Aap kis samay paida hue the?"], "", "birth_time"]);
  // An "ask" that says more is a chat — nothing it said is cut.
  const said = shape({ ...REPLY, kind: "ask", upay: "" }, { askFor: "birth_place" });
  assertEquals([said.kind, said.bubbles.length], ["chat", 3]);
  // A chat that carries the upay the code asked for is an answer.
  assertEquals(shape({ ...REPLY, kind: "chat" }, { upay: true }).kind, "answer");

  const care = shape({ ...REPLY, answer: ["Aap akele nahi hain.", "Tele-MANAS 14416 par abhi call kijiye."] }, { upay: true, askFor: "birth_time" });
  assertEquals([care.kind, care.upay, care.askFor], ["care", "", "none"]);
  assertEquals(care.bubbles.length, 3);
  // In a flagged thread, no upay even if one was due.
  assertEquals(shape(REPLY, { upay: true, care: true }).upay, "");
});

Deno.test("ask_for is what the code asked, and none when the reply asks nothing", () => {
  assertEquals(shape(REPLY, { askFor: "birth_place" }).askFor, "birth_place");
  assertEquals(shape({ ...REPLY, sawal: "" }, { askFor: "birth_place" }).askFor, "none");
  // Whatever the model writes — the field is not in the schema, and is not read.
  assertEquals(shape({ ...REPLY, ask_for: "dob" }).askFor, "none");
  // Beside the app's own button for a birth detail, two chips at most.
  assertEquals(shape({ ...REPLY, options: ["Jeevansathi kaisa hoga?", "Love ya arrange?", "Shaadi mein deri kyun?"] }, { askFor: "birth_place" }).options.length, 2);
  assert(!shape({ ...REPLY, options: ["Birth time batayein", "Love ya arrange?"] }, { askFor: "birth_time" }).options.includes("Birth time batayein"));
});

Deno.test("exactly one question, and under a hundred words — the upay never cut", () => {
  assertEquals(oneQuestion("Kya rishta aaya hai? Ya aap khud dhoond rahe hain?"), "Kya rishta aaya hai?");
  assertEquals(
    oneQuestion("Janm ka sahi samay mile toh main aur pakka bata sakta hoon — aap kis samay paida hue the? Jaise subah 7:30 ya raat 10 baje."),
    "Janm ka sahi samay mile toh main aur pakka bata sakta hoon — aap kis samay paida hue the? Jaise subah 7:30 ya raat 10 baje.",
  );
  assertEquals(oneQuestion("आपका जन्म किस शहर में हुआ था? और किस समय?"), "आपका जन्म किस शहर में हुआ था?");
  assertEquals(shape({ ...REPLY, sawal: "Kya rishta aaya hai? Ya aap khud dhoond rahe hain?" }).sawal, "Kya rishta aaya hai?");

  const long = "Ye bahut accha samay hai aur aapke liye kaafi umeed hai.";
  const verbose = shape({
    ...REPLY,
    answer: [`${REPLY.answer[0]} ${long} ${long}`, `${REPLY.answer[1]} ${long} ${long}`],
    sawal: `${long} ${long} ${REPLY.sawal}`,
  }, { upay: true });
  const words = verbose.bubbles.join(" ").split(/\s+/).length;
  assert(words <= MAX_WORDS, `${words} words`);
  assertEquals(verbose.upay, REPLY.upay);
  assertEquals(verbose.sawal, REPLY.sawal);
  assert(verbose.bubbles[0].startsWith(REPLY.answer[0]));
  // A reply inside the limit is left exactly as written.
  assertEquals(shape(REPLY, { upay: true }).bubbles.join(" "), [...REPLY.answer, REPLY.upay, REPLY.sawal].join(" "));
});

// Live, 28 Sep: four single long sentences, 109 and 111 words.
const LONG_UPAY =
  "Aaj Somvar hai — aaj se shuru kijiye: har Somvar Shiv ji ko ek lota jal chadhaiye, 16 Somvar tak; ye acche jeevansathi ke liye sabse shubh maana jaata hai. Kal wapas aaiye, iske asar par baat karenge.";

Deno.test("one long sentence loses its elaboration, never its reason, its window or the kundali line", () => {
  const live = shape({
    ...REPLY,
    answer: [
      "Priya ji, deri ka matlab rukavat nahi hai, June 2027 tak aapke rishta pakka hone ke sabse mazboot yog bane hue hain.",
      "Is samay aapki kundali mein Guru ka gochar chal raha hai, jo shaadi ke ghar ko shubh drishti se dekh raha hai aur achha rishta dilane mein madad karega.",
    ],
    upay: LONG_UPAY,
    sawal: "Abhi ghar mein kya kisi rishte ko lekar baat chal rahi hai ya aap khud koi pasand dekh rahe hain?",
  }, { upay: true });
  assert(live.bubbles.join(" ").split(/\s+/).length <= MAX_WORDS);
  assertEquals(live.bubbles[1], "Is samay aapki kundali mein Guru ka gochar chal raha hai.");
  assertEquals(live.upay, LONG_UPAY);
  assert(live.bubbles[0].includes("June 2027"));

  // "Kyonki…" is the reason itself, and stays whatever the count.
  const because = "June 2027 tak shaadi ke yog sabse mazboot hain, kyonki Guru ka shubh asar aapke shaadi wale ghar par hai aur rahega.";
  const kept = shape({ ...REPLY, answer: [REPLY.answer[0], because], upay: `${LONG_UPAY} ${LONG_UPAY.slice(0, 120)}.` }, { upay: true });
  assertEquals(kept.bubbles[1], because);

  // The answer's own elaboration goes only when it holds no window and the reply does not open
  // with the kundali line, whose last clause is its hope.
  const hindi = {
    ...REPLY,
    answer: [
      "सुनीता जी, इस समय आपकी कुंडली में गुरु की महादशा चल रही है, जो बहुत शुभ है और शादी के रास्ते की अड़चनों को दूर करने में मदद करेगी।",
      "दशा मजबूत होने से अगस्त 2027 से जुलाई 2028 के बीच अच्छे रिश्ते आने और बात पक्की होने के सबसे सुंदर योग बने हुए हैं।",
    ],
    upay: "आज सोमवार है — आज से ही शुरू कीजिए: हर सोमवार शिव जी को एक लोटा जल चढ़ाइए, 16 सोमवार तक; यह उपाय अच्छे जीवनसाथी और सुख-शांति के लिए बहुत शुभ माना जाता है। कल जरूर बताइएगा कि मन कैसा महसूस कर रहा है।",
    sawal: "क्या अभी घर में किसी रिश्ते को लेकर कोई बातचीत चल रही है?",
  };
  const cut = shape(hindi, { upay: true, language: "Hindi" });
  assertEquals(cut.bubbles[0], "सुनीता जी, इस समय आपकी कुंडली में गुरु की महादशा चल रही है।");
  assert(cut.bubbles.join(" ").split(/\s+/).length <= MAX_WORDS);
  assertEquals(shape(hindi, { upay: true, language: "Hindi", opening: true }).bubbles[0], hindi.answer[0]);
  const window = shape({ ...hindi, answer: ["शादी का सबसे अच्छा समय है, अगस्त 2027 से जुलाई 2028 के बीच जब गुरु और शुक्र दोनों आपके साथ होंगे और रिश्ते पक्के होंगे।", hindi.answer[1]] }, { upay: true, language: "Hindi" });
  assert(window.bubbles[0].includes("2027"));
});

Deno.test("THE KUNDALI LINE and an upay on one turn still come in under a hundred words", () => {
  // Live (review, 28 Sep): the first reply, asked for an upay, with the whole chart — 106 and
  // 116 words, with nothing left for the budget to cut.
  const s6 = {
    kind: "answer",
    topic: "career",
    answer: [
      "Maine aapki janm tithi aur samay se kundali dekhi — aapki Karka rashi aur Punarvasu nakshatra hai, aur aane wala samay aapke kaam ke liye accha dikh raha hai 🙏",
      "Abhi se lekar July 2027 tak ka samay naukri ke liye sabse mazboot hai, kyonki Mangal ki antardasha chal rahi hai jo aapke kaam ke ghar ka swami hai.",
    ],
    upay: "Aaj Mangalvar hai — aaj se shuru kijiye: har Mangalvar ek baar Hanuman Chalisa padhiye, 4 hafte tak. Ye Mangal ko mazboot karke kaam ki rukawatein door karta hai. Kal wapas aaiye, dekhte hain kaisa lag raha hai.",
    sawal: "Aap kis shehar ya kasbe mein paida hue the?",
    options: [],
  };
  const s7 = {
    kind: "answer",
    topic: "marriage",
    answer: [
      "Maine aapki janm tithi, samay aur sthan se kundali dekhi — aapki Vrischika rashi aur Anuradha nakshatra hai, aur aane wala samay shaadi ke liye accha dikh raha hai 🙏",
      "Abhi se September 2028 ke beech shaadi ke sabse mazboot yog hain, kyonki aapki kundali mein Shukra ki dasha chal rahi hai jo rishton ke liye shubh hoti hai.",
    ],
    upay: "Aaj Guruvar hai — aaj se shuru kijiye: har Guruvar subah kele ke ped mein ek lota jal chadhaiye, 4 hafte tak. Kele ka ped Guru ka hota hai aur Guru shaadi ke yog banate hain. Kal wapas aaiye, iska asar dekhte hain.",
    sawal: "Pooja ji, abhi rishta ghar wale dekh rahe hain ya aapki apni pasand hai?",
    options: [],
  };
  const count = (bubbles: string[]) => bubbles.join(" ").split(/\s+/).filter(Boolean).length;
  for (const [raw, window, graha] of [[s6, "July 2027", "Mangal ki antardasha"], [s7, "September 2028", "Shukra ki dasha"]] as const) {
    const before = count([...raw.answer, raw.upay, raw.sawal]);
    assert(before > MAX_WORDS, `${before}`);
    for (const hook of [true, false]) {
      const reply = shape(raw, { upay: true, opening: true, hook });
      assert(count(reply.bubbles) < MAX_WORDS, `${count(reply.bubbles)} words`);
      // The kundali line whole; the window and the reason kept; the upay's day, count and length,
      // and its hook — only its why went.
      assertEquals(reply.bubbles[0], raw.answer[0]);
      assert(reply.bubbles[1].includes(window) && reply.bubbles[1].includes(graha), reply.bubbles[1]);
      assert(reply.upay.startsWith(raw.upay.split(". ")[0]), reply.upay);
      assert(/4 hafte tak/.test(reply.upay) && /Kal wapas aaiye/.test(reply.upay), reply.upay);
      assertEquals(reply.bubbles.length, 4);
    }
  }
});

Deno.test("under a hundred means under: a reply of exactly a hundred words is cut", () => {
  assertEquals(MAX_WORDS, 100);
  // Short words, so the second sentence stays inside a bubble's length and only the count is at issue.
  const words = (n: number) => Array.from({ length: n }, () => "ek").join(" ");
  const upay = "Aaj Somvar hai — aaj se shuru kijiye: har Somvar Shiv ji ko ek lota jal chadhaiye, 16 Somvar tak.";
  const sawalText = "Rishta ghar wale dhoond rahe hain ya aap khud?";
  const jawab = "‹window› shaadi ka sabse accha samay hai, bahut accha.";
  const kyun = "Is time Shukra ki dasha chalegi.";
  const fixed = [jawab, kyun, upay, sawalText].join(" ").split(/\s+/).length;
  // The reason's second sentence is what goes, and it is the only thing that has to.
  const raw = { ...REPLY, answer: [jawab, `${kyun} ${words(100 - fixed)}.`], upay, sawal: sawalText };
  const total = [...raw.answer, upay, sawalText].join(" ").split(/\s+/).length;
  assertEquals(total, 100);
  const reply = shape(raw, { upay: true });
  assertEquals(reply.bubbles[1], "Is time Shukra ki dasha chalegi.");
  assert(reply.bubbles.join(" ").split(/\s+/).length < MAX_WORDS);
});

// ---------------------------------------------------------------- the prompt

function context(over: Partial<ChatContextV5> = {}): ChatContextV5 {
  return {
    chart: computeChart({ dob: "2000-01-01", birthTime: "03:00", asOf: MONDAY }),
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

Deno.test("the prompt hands over the upay, the question and the good — each only when there is one", () => {
  const upay = upayFor("marriage", { now: MONDAY });
  const prompt = flat(buildUserPromptV5("shaadi mein deri kyun?", context({
    upay,
    sawal: sawal(),
    strengths: ["The Mahadasha of Guru runs now: the most benefic graha."],
  })));
  assert(prompt.includes("THE UPAY FOR TODAY — worked out in code"));
  assert(prompt.includes('THE QUESTION TO ASK — the "sawal", chosen in code. Exactly one question, this one: one question about their situation'));
  assert(prompt.includes('"Rishta ghar wale dhoond rahe hain ya aap khud?"'));
  assert(prompt.includes("THE GOOD IN THEIR CHART (computed and true"));
  // The question comes last before their words.
  assert(prompt.indexOf("THE QUESTION TO ASK") > prompt.indexOf("THE UPAY FOR TODAY"));
  assert(prompt.indexOf("THEY SAY:") > prompt.indexOf("THE QUESTION TO ASK"));

  const none = buildUserPromptV5("x", context());
  for (const block of ["THE UPAY FOR TODAY", "THE QUESTION TO ASK", "THE GOOD IN THEIR CHART", '"ask_for"']) {
    assert(!none.includes(block), block);
  }
  // The hour's block no longer lets the model ask on its own.
  const noHour = flat(buildUserPromptV5("x", context({ chart: computeChart({ dob: "1996-04-12", asOf: MONDAY }) })));
  assert(noHour.includes("Ask for it only when THE QUESTION TO ASK does, and never in the answer itself."));
});

Deno.test("the good in their chart is only what is true of it", () => {
  const now = MONDAY;
  const noHour = computeChart({ dob: "1996-04-12", asOf: now })!;
  const good = goodInChart({ chart: noHour, timing: null, transits: transitTiming(noHour.moonRashi, now) });
  assert(good.some((line) => line.startsWith("Guru, the most benefic graha, stands in the 7th house")), good.join("\n"));
  assert(!good.some((line) => line.includes("Mahadasha")), "no dasha without the hour");

  // Shani–Shani is no benefic period, and says nothing of one.
  const whole = computeChart({ dob: "2000-01-01", birthTime: "03:00", asOf: now })!;
  const lines = goodInChart({
    chart: whole,
    timing: chatTiming(whole, { dob: "2000-01-01", asOf: now, v5: true }),
    transits: transitTiming(whole.moonRashi, now),
  });
  assert(lines[0].startsWith("A favourable period runs now or opens within the year for marriage"));
  assert(!lines.some((line) => /Mahadasha|Antardasha/.test(line)));

  // A Guru or Shukra period is named; no chart, nothing but the mini kundli's own.
  const guru = { ...whole, dasha: { mahadasha: "Guru", mahaPhase: "early" as const, antardasha: "Shukra", antarPhase: "early" as const } };
  const named = goodInChart({ chart: guru, timing: null, transits: null });
  assertEquals(named, [
    "The Mahadasha of Guru runs now: the most benefic graha — of wisdom, blessing and growth.",
    "The Antardasha of Shukra runs now: a benefic graha — of love, comfort and prosperity.",
  ]);
  assertEquals(goodInChart({ chart: null, timing: null, transits: null }), []);
  assertEquals(goodInChart({ chart: null, timing: null, transits: null, more: ["Guru in a kendra."] }), ["Guru in a kendra."]);
});

// ---------------------------------------------------------------- what stays as it was

Deno.test("an offer stored before 28 Sep still works: its yes, its chips, its hidden upay", () => {
  // `serveRemedy`'s guard: the offer's own chips, minus the yes just tapped.
  assert(isRemedyAccept("Haan, upay batao 🙏") && isRemedyAccept("haan"));
  assertEquals(
    onTopicOptions(["Haan, upay batao 🙏", "Jeevansathi kaisa hoga?"], { topic: "marriage", asked: ["Haan, upay batao 🙏"] }),
    ["Jeevansathi kaisa hoga?"],
  );
  // Its turn, served, is a remedy turn — counted as given, and never an answer.
  const served = v5Body({ kind: "remedy", topic: "marriage", bubbles: ["Har Shukravar…"], offer: "none", options: [], askFor: "none" }, { version: "v5", hook: true });
  assertEquals(remediesGiven([{ role: "astro", body: served }]), ["marriage"]);
  assertEquals(answersIn([{ role: "astro", body: served }]), 0);
  // The old rows keep rendering: the hidden upay is still stored beside an old offer.
  const offer = v5Body({ kind: "answer", topic: "marriage", bubbles: ["a", "b", "Upay bataun?"], offer: "remedy", remedyBubbles: ["c"], options: [], askFor: "none" }, { version: "v5", remedyHook: true });
  assertEquals([offer.offer, offer.remedy_bubbles, offer.remedy_hook], ["remedy", ["c"], true]);
});

Deno.test("v4 knows none of it", () => {
  for (const language of ["Hinglish", "Hindi", "Kannada"]) {
    const v4 = chatSystemPrompt({ version: "v4", language });
    for (const word of ["THE UPAY FOR TODAY", "THE QUESTION TO ASK", "THE GOOD IN THEIR CHART", "sawal"]) {
      assert(!v4.includes(word), `${language}: ${word}`);
    }
  }
});
