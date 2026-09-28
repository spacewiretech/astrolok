/**
 * The upay, for chat v5: when one is due, and which.
 *
 * The product team's arc for an answer (28 Sep): seedha jawab, kyun, and — once Astro knows enough
 * to give a real one — one upay, then one question. v5 left both halves of the upay to the model,
 * and it did neither well. It offered one under every answer ("Kya main aapko aaj ka upay
 * bataun?"), which is the repetition the one-star chats named; and it chose the remedy itself, so
 * a Tuesday got a Friday mantra and nobody could start that day. Both are decided here instead:
 *
 * - **When** ([upayDue]). Never in a thread flagged for a crisis or above a loss. At once when
 *   they ask for one, in any of the eight languages ([asksForUpay]). Otherwise on the third answer
 *   of a thread when Astro has their date and has their hour and place or has asked for them, and
 *   on the fourth answer whatever it has — "after 3 to 4 chat when u have enough context" — and
 *   after one, counted again from it. One per topic in a thread, unless they ask for another.
 * - **Which** ([upayFor]). From the topic, today's weekday in India and the running dasha: the
 *   topic's own remedy that falls on today, so they can start today ("Aaj Somvar hai — aaj se
 *   shuru kijiye"); else today's deity's remedy where it suits the topic; else the topic's own,
 *   with its day named ("agle Shukravar se"); a Mangal dosh or a fear gets the table's Hanuman
 *   Chalisa every day, whatever the subject. Each has a day, a count and a length. None costs
 *   more than a diya, a flower or a handful of daal, and none is given twice in a thread.
 *
 * The model words it in their language ([describeUpay]); it never chooses it. Pure, and the clock
 * comes in from outside.
 */

import { Chart, IST_OFFSET_HOURS } from "./jyotish.ts";
import { topicsOf } from "./chat_topics.ts";
import type { ReplyTopic } from "./astro_chat_v5.ts";

// ---------------------------------------------------------------- the day

/** The seven days as `getUTCDay` counts them, Sunday first, each with the graha whose day it is. */
export const WEEKDAYS = [
  { name: "Ravivar", english: "Sunday", graha: "Surya" },
  { name: "Somvar", english: "Monday", graha: "Chandra" },
  { name: "Mangalvar", english: "Tuesday", graha: "Mangal" },
  { name: "Budhvar", english: "Wednesday", graha: "Budh" },
  { name: "Guruvar", english: "Thursday", graha: "Guru" },
  { name: "Shukravar", english: "Friday", graha: "Shukra" },
  { name: "Shanivar", english: "Saturday", graha: "Shani" },
] as const;

export type Weekday = 0 | 1 | 2 | 3 | 4 | 5 | 6;

/**
 * The weekday and the hour in India at [now]. One clock for the whole country and no summer time,
 * so the offset is the whole of it — and "today" is theirs, not the server's: at 20:00 UTC on a
 * Sunday it is already Monday in India.
 */
export function indiaDay(now: Date): { weekday: Weekday; hour: number } {
  const local = new Date(now.getTime() + IST_OFFSET_HOURS * 3_600_000);
  return { weekday: local.getUTCDay() as Weekday, hour: local.getUTCHours() };
}

/** Rahu and Ketu have no day of their own; the tradition keeps Rahu's on Shani's, Ketu's on Mangal's. */
const SHADOW_DAYS: Record<string, Weekday> = { Rahu: 6, Ketu: 2 };

function dayOf(graha: string): Weekday | null {
  const index = WEEKDAYS.findIndex((day) => day.graha === graha);
  return index >= 0 ? index as Weekday : SHADOW_DAYS[graha] ?? null;
}

/** After this hour a morning practice starts on the next morning. */
const MIDDAY = 12;

// ---------------------------------------------------------------- the remedies

interface Remedy {
  /** Whose day it is done on — and what a running dasha or a weak graha favours ([upayFor]). */
  graha: typeof WEEKDAYS[number]["graha"];

  /** "week": on that day each week. "day": every day — from that day when [begins], else any. */
  every: "week" | "day";
  begins?: boolean;

  /** Done in the morning, so after [MIDDAY] it starts on the next one. */
  morning?: boolean;

  /** As it is said, in Hinglish; the model words it in their language. */
  what: string;
  times: string;
  length: string;
  why: string;
}

/**
 * Every upay the chat gives: the product team's table (Section E of the 28 Sep brief), and one
 * for each day's deity. Nothing here is bought, booked or fasted for — BOUNDARIES' counsel bullet.
 */
const REMEDIES = {
  katyayani_mantra: {
    graha: "Shukra",
    every: "week",
    what: "Maa Katyayani ka mantra padhiye",
    times: "11 baar",
    length: "4 hafte",
    why: "Maa Katyayani shaadi ki rukawatein door karti hain",
  },
  safed_mithai: {
    graha: "Shukra",
    every: "week",
    what: "safed mithai ka daan kijiye",
    times: "ek baar",
    length: "4 hafte",
    why: "Shukra rishton ka graha hai, aur safed cheez ka daan use mazboot karta hai",
  },
  kele_jal: {
    graha: "Guru",
    every: "week",
    morning: true,
    what: "subah kele ke ped mein jal chadhaiye",
    times: "ek lota",
    length: "4 hafte",
    why: "kele ka ped Guru ka maana jaata hai, aur Guru shaadi aur santan ka aashirwad dete hain",
  },
  surya_jal: {
    graha: "Surya",
    every: "day",
    morning: true,
    what: "subah Surya ko jal chadhaiye",
    times: "roz ek lota",
    length: "21 din",
    why: "Surya maan, pad aur safalta ka graha hai",
  },
  shani_tel: {
    graha: "Shani",
    every: "week",
    what: "Shani mandir mein thoda sarson ka tel chadhaiye",
    times: "ek baar",
    length: "4 hafte",
    why: "Shani mehnat ka phal dene wala graha hai",
  },
  hanuman_mangalvar: {
    graha: "Mangal",
    every: "week",
    what: "Hanuman Chalisa padhiye",
    times: "ek baar",
    length: "4 hafte",
    why: "Hanuman ji har rukawat door karte hain",
  },
  lakshmi_diya: {
    graha: "Shukra",
    every: "week",
    what: "shaam ko Lakshmi ji ki puja karke ghee ka diya jalaiye",
    times: "ek diya",
    length: "4 hafte",
    why: "Lakshmi ji dhan aur barkat ki devi hain",
  },
  peeli_daan: {
    graha: "Guru",
    every: "week",
    what: "peeli cheez — chane ki daal ya haldi — ka daan kijiye",
    times: "ek baar",
    length: "4 hafte",
    why: "Guru dhan badhane wala aur rahat dene wala graha hai",
  },
  hanuman_phool: {
    graha: "Mangal",
    every: "week",
    what: "Hanuman ji ko laal phool chadhaiye",
    times: "ek baar",
    length: "4 hafte",
    why: "Mangal zameen aur ghar ka graha hai, aur Hanuman ji uske devta hain",
  },
  ganesh_puja: {
    graha: "Budh",
    every: "week",
    what: "Ganesh ji ki puja kijiye",
    times: "ek baar",
    length: "4 hafte",
    why: "har naye ghar ki shuruaat Ganesh ji se hoti hai",
  },
  santan_gopal: {
    graha: "Guru",
    every: "day",
    begins: true,
    what: "Santan Gopal mantra padhiye",
    times: "roz 11 baar",
    length: "40 din",
    why: "Santan Gopal mantra santan ke liye sabse maana hua mantra hai",
  },
  peeli_daal: {
    graha: "Guru",
    every: "week",
    what: "peeli daal ka daan kijiye",
    times: "ek baar",
    length: "4 hafte",
    why: "Guru santan ka graha hai",
  },
  rin_mochan: {
    graha: "Mangal",
    every: "week",
    what: "Rin Mochan Mangal Stotra padhiye",
    times: "ek baar",
    length: "4 hafte",
    why: "ye stotra karz se mukti ke liye hi hai",
  },
  ganesh_durva: {
    graha: "Budh",
    every: "week",
    what: "Ganesh ji ko durva chadhaiye",
    times: "21 durva",
    length: "4 hafte",
    why: "Ganesh ji buddhi dete hain aur har rukawat door karte hain",
  },
  shiv_jal: {
    graha: "Chandra",
    every: "week",
    what: "Shiv ji ko jal chadhaiye",
    times: "ek lota",
    length: "16 Somvar",
    why: "16 Somvar ka jal acche jeevansathi aur rishton mein sukh ke liye maana jaata hai",
  },
  parvati_puja: {
    graha: "Shukra",
    every: "week",
    what: "Maa Parvati ki puja karke laal phool chadhaiye",
    times: "ek baar",
    length: "4 hafte",
    why: "Maa Parvati prem aur rishton ki devi hain",
  },
  hanuman_roz: {
    graha: "Mangal",
    every: "day",
    what: "Hanuman Chalisa padhiye",
    times: "roz ek baar",
    length: "40 din",
    why: "Hanuman ji dar aur chinta door karte hain",
  },
  peepal_diya: {
    graha: "Shani",
    every: "week",
    what: "shaam ko peepal ke ped ke neeche sarson ke tel ka diya jalaiye",
    times: "ek diya",
    length: "4 hafte",
    why: "Shani ki kripa se atka hua kaam chalne lagta hai",
  },
} satisfies Record<string, Remedy>;

export type RemedyId = keyof typeof REMEDIES;

const remedy = (id: RemedyId): Remedy => REMEDIES[id];

/**
 * Each topic's own remedies, as the table gives them. A government job or an exam has a row of
 * its own there ("Sarkari naukri / exam"); studies is that row, and a career question that names
 * a government job reads it first ([SARKARI]).
 */
const TOPIC_REMEDIES: Record<ReplyTopic | "sarkari", readonly RemedyId[]> = {
  marriage: ["katyayani_mantra", "safed_mithai", "kele_jal"],
  love: ["shiv_jal", "parvati_puja"],
  children: ["santan_gopal", "peeli_daal"],
  career: ["surya_jal", "shani_tel", "hanuman_mangalvar"],
  sarkari: ["surya_jal", "ganesh_durva"],
  money: ["lakshmi_diya", "peeli_daan"],
  debt: ["rin_mochan", "hanuman_mangalvar"],
  home: ["hanuman_phool", "ganesh_puja"],
  studies: ["surya_jal", "ganesh_durva"],
  // A worry about health, a Mangal dosh, a fear: Hanuman Chalisa and nothing else — and a doctor.
  health: ["hanuman_roz"],
  general: [],
};

/** A government job or an exam, in any of the languages. */
const SARKARI =
  /(?<![\p{L}\p{M}])(?:sarkari|government|govt|upsc|ssc|psc|exams?|par(?:i|ee)ksha)(?![\p{L}\p{M}])|सरकारी|परीक्ष|ಸರ್ಕಾರಿ|ಪರೀಕ್ಷ|அரசு|தேர்வ|ప్రభుత్వ|పరీక్ష|സ(?:ർ|ര്)ക്കാ(?:ർ|ര്)|പരീക്ഷ/iu;

/**
 * A Mangal dosh, in any of the languages: "main manglik hoon", "mangal dosh ka upay", "मंगल दोष",
 * "ಕುಜ ದೋಷ", "செவ்வாய் தோஷம்", "కుజ దోషం", "ചൊവ്വാദോഷം". [topicsOf] reads none of these as a
 * subject, so they were answered with today's deity — Shiv ji's jal on a Monday — rather than the
 * table's own row for them.
 */
const MANGAL_DOSH =
  /(?<![\p{L}\p{M}])(?:mangal(?:ik)?[\s-]*dosh(?:a|am)?|manglik|mangalik|kuja[\s-]*dosh(?:a|am)?|chevvai[\s-]*dosh(?:a|am)?)(?![\p{L}\p{M}])|मंगल\s*दोष|मांगलिक|मंगलीक|मांगली|मंगळ\s*दोष|ಕುಜ\s*ದೋಷ|ಮಂಗಳ\s*ದೋಷ|செவ்வாய்\s*தோஷ|కుజ\s*దోష|మంగళ\s*దోష|ചൊവ്വാ\s*ദോഷ|ചൊവ്വാദോഷ/iu;

/** Hanuman Chalisa's why for a Mangal dosh: Hanuman ji is Mangal's devta. Never a threat. */
const DOSH_WHY = "Hanuman ji Mangal ke devta hain, aur unki bhakti se Mangal shubh phal deta hai";

/**
 * A fear, said as one: "mujhe dar lagta hai", "डर", "bhay", "ಭಯ", "பயம்", "భయం", "പേടി". Not a
 * worry ("tension", "chinta"), which half of every question begins with and which is its topic's;
 * and not "bhayankar", which is as often "very" as "terrible".
 */
const FEAR =
  /(?<![\p{L}\p{M}])(?:darr?|darr?(?:ta|ti|te)|darr?(?:na|ne)|bhay|bhaya|fear(?:s|ful)?|scared|afraid)(?![\p{L}\p{M}])|(?<![\p{L}\p{M}])(?:डर|भय(?!ंक)|भीती|ಭಯ(?!ಂಕ)|ಹೆದರಿಕೆ|பயம|భయ(?!ంక)|ഭയ(?!ങ്ക)|പേടി)/iu;

/**
 * Today's deity, and the topics its remedy suits. Where none of a topic's own remedies falls on
 * today, this is how they still start today: a Monday shaadi question gets Shiv ji's 16 Somvar,
 * the tradition's own for a good spouse. Ganesh ji, who removes obstacles, suits everything but
 * health, which is Hanuman Chalisa's alone.
 */
const DAY_REMEDIES: Record<Weekday, ReadonlyArray<readonly [RemedyId, readonly ReplyTopic[]]>> = {
  0: [["surya_jal", ["career", "studies", "general"]]],
  1: [["shiv_jal", ["marriage", "love", "general"]]],
  2: [["hanuman_mangalvar", ["career", "debt", "home", "studies", "general"]]],
  3: [[
    "ganesh_durva",
    ["marriage", "love", "children", "career", "money", "debt", "home", "studies", "general"],
  ]],
  4: [
    ["kele_jal", ["marriage", "love", "children", "general"]],
    ["peeli_daan", ["money", "debt", "studies", "career"]],
  ],
  5: [["lakshmi_diya", ["money", "home", "debt", "career", "general"]]],
  6: [["peepal_diya", ["career", "debt", "money", "home", "general"]]],
};

// ---------------------------------------------------------------- choosing one

export interface Upay {
  id: RemedyId;

  /** What it is for: the reply's topic. */
  topic: ReplyTopic;

  /** Today in India, when it was chosen. */
  today: Weekday;

  /** The day it is done on, or begun on; for a daily upay, the day it starts. */
  day: Weekday;
  every: "week" | "day";

  /** When they start: today, tomorrow, or the next time [day] comes round. */
  start: "today" | "tomorrow" | "next";

  what: string;
  times: string;
  length: string;
  why: string;

  /** A graha it strengthens that the chart points to — the running dasha's, or a weak one. */
  strengthens: { graha: string; because: "antardasha" | "mahadasha" | "kundali" } | null;

  /** A worry about health: "Doctor se zaroor milein" goes with it. */
  doctor: boolean;

  /** How it was chosen, for the log and the tests. */
  from: "dosh" | "topic_today" | "deity_today" | "topic_later" | "deity_later" | "repeat";
}

/** The reply topics, without the table's own "sarkari" row. */
const REPLY_TOPIC_SET: ReadonlySet<string> = new Set(
  Object.keys(TOPIC_REMEDIES).filter((topic) => topic !== "sarkari"),
);

/**
 * The one upay for [topic], today. See the file header for the order; within a step the chart
 * breaks the tie — a weak graha from the mini kundali first ([weakGrahas]), then the running
 * Antardasha's lord, then the Mahadasha's — and then the soonest day and the table's own order.
 *
 * A Mangal dosh or a fear in what they said ([MANGAL_DOSH], [FEAR]) comes before all of it: the
 * table's row for them is the health worry's own, Hanuman Chalisa every day for 40 days, whatever
 * the subject — without the doctor, which is for health alone.
 *
 * [given] is what this thread already had, which is never given again; when every remedy that
 * suits the topic has been, they asked for another ([upayDue]) and get the topic's first again.
 */
export function upayFor(
  topic: string,
  { now, chart = null, weakGrahas = [], given = [], said = "" }: {
    now: Date;
    chart?: Chart | null;
    /** From the mini kundli, when there is one: grahas that want strengthening, weakest first. */
    weakGrahas?: readonly string[];
    /** Remedy ids already given in this thread ([upaysGiven]). */
    given?: readonly string[];
    /** What they said, which tells a government job from any other. */
    said?: string;
  },
): Upay {
  const subject = (REPLY_TOPIC_SET.has(topic) ? topic : "general") as ReplyTopic;
  const { weekday, hour } = indiaDay(now);
  const afternoon = hour >= MIDDAY;

  const own: RemedyId[] = subject === "career" && SARKARI.test(said)
    ? [...new Set([...TOPIC_REMEDIES.sarkari, ...TOPIC_REMEDIES.career])]
    : [...TOPIC_REMEDIES[subject]];
  const deity = (day: Weekday) =>
    DAY_REMEDIES[day].filter(([, fits]) => fits.includes(subject)).map(([id]) => id);
  const fresh = (ids: RemedyId[]) => ids.filter((id) => !given.includes(id));

  // The graha behind each preference, strongest first, and why it is there.
  const favoured: Array<{ graha: string; because: "antardasha" | "mahadasha" | "kundali" }> = [
    ...weakGrahas.map((graha) => ({ graha, because: "kundali" as const })),
    ...(chart?.dasha
      ? [
        { graha: chart.dasha.antardasha, because: "antardasha" as const },
        { graha: chart.dasha.mahadasha, because: "mahadasha" as const },
      ]
      : []),
  ];
  const favour = (id: RemedyId) => {
    const day = dayOf(remedy(id).graha);
    const index = favoured.findIndex(({ graha }) => dayOf(graha) === day);
    return index < 0 ? null : favoured[index];
  };

  /** Days until it can start: 0 for today. */
  const wait = (id: RemedyId): number => {
    const r = remedy(id);
    const late = r.morning && afternoon;
    if (r.every === "day" && !r.begins) return late ? 1 : 0;
    const days = (dayOf(r.graha)! - weekday + 7) % 7;
    return days === 0 && late ? 7 : days;
  };
  const daySpecific = (id: RemedyId) => remedy(id).every === "week" || remedy(id).begins === true;

  const ranked = (ids: RemedyId[]) =>
    ids
      .map((id, order) => ({ id, order, favour: favour(id) }))
      .sort((a, b) =>
        rank(a.favour) - rank(b.favour) || wait(a.id) - wait(b.id) || a.order - b.order
      );
  const rank = (entry: { graha: string } | null) =>
    entry ? favoured.findIndex(({ graha }) => graha === entry.graha) : favoured.length;

  const dosh = MANGAL_DOSH.test(said);
  const steps: Array<[Upay["from"], RemedyId[]]> = [
    ["dosh", dosh || FEAR.test(said) ? fresh(["hanuman_roz"]) : []],
    // Theirs, on today's own day — Hanuman Chalisa on a Tuesday — before theirs on any day.
    ["topic_today", fresh(own).filter((id) => wait(id) === 0 && daySpecific(id))],
    ["topic_today", fresh(own).filter((id) => wait(id) === 0)],
    ["deity_today", fresh(deity(weekday)).filter((id) => wait(id) === 0)],
    ["topic_later", fresh(own)],
    [
      "deity_later",
      fresh([...new Set(([1, 2, 3, 4, 5, 6, 0] as Weekday[]).flatMap((day) => deity(day)))]),
    ],
    ["repeat", own.length > 0 ? own : deity(weekday)],
  ];

  for (const [from, ids] of steps) {
    const [best] = ranked(ids);
    if (!best) continue;
    const r = remedy(best.id);
    const days = wait(best.id);
    return {
      id: best.id,
      topic: subject,
      today: weekday,
      day: ((weekday + days) % 7) as Weekday,
      every: r.every,
      start: days === 0 ? "today" : days === 1 ? "tomorrow" : "next",
      what: r.what,
      times: r.times,
      length: r.length,
      // Hanuman ji is Mangal's devta; for a dosh that is the why, and it frightens no one.
      why: from === "dosh" && dosh ? DOSH_WHY : r.why,
      strengthens: best.favour,
      doctor: subject === "health",
      from,
    };
  }

  // Unreachable: every day's deity suits "general". Kept so the type is total.
  return upayFor("general", { now, chart, weakGrahas, given: [], said });
}

// ---------------------------------------------------------------- asking for one

/**
 * An upay asked for, in any of the eight languages: "upay batao", "koi totka", "remedy?", "उपाय",
 * "ಪರಿಹಾರ", "பரிகாரம்", "పరిహారం", "പരിഹാരം" — and "koi mantra", "koi puja", which ask the same.
 */
const UPAY_WORDS = new RegExp(
  [
    "(?<![\\p{L}\\p{M}])(?:u+pa+y(?:e|on|o)?|upai|uppay|remed(?:y|ies)|totk(?:a|e)|tootk(?:a|e)|" +
    "samadhaa?n)(?![\\p{L}\\p{M}])",
    "(?<![\\p{L}\\p{M}])(?:koi|kuch|ek) (?:hal|mantra|puja|pooja|daan|totka)(?![\\p{L}\\p{M}])",
    "उपाय|टोटक|समाधान|कोई (?:हल|मंत्र|पूजा)",
    "ಪರಿಹಾರ|ಉಪಾಯ",
    "பரிகார|உபாய",
    "పరిహార|ఉపాయ",
    "പരിഹാര|ഉപായ",
  ].join("|"),
  "iu",
);

/**
 * A question about an upay already given — how, when, at what hour, what to say, whether it works
 * — not a wish for another. "Ye upay subah karna hai or shaam ko?" asks about the one given.
 */
const ABOUT_ONE =
  /(?<![\p{L}\p{M}])(?:kaise|kese|kaisey|kab|kitni|kitne|kaha|kahan|kis din|kis samay|asar|kaam kar\w*|subah|subha|shaam|sham|raat|kya bol\w*|bolna|how|when|work(?:s|ing)?|morning|evening|night)(?![\p{L}\p{M}])|कैसे|कब|कितनी|कितने|असर|काम कर|सुबह|शाम|रात|क्या बोल|ಹೇಗೆ|ಯಾವಾಗ|ಬೆಳಿಗ್ಗೆ|ಸಂಜೆ|எப்படி|எப்போது|காலை|மாலை|ఎలా|ఎప్పుడు|ఉదయం|సాయంత్రం|എങ്ങനെ|എപ്പോ|രാവിലെ|വൈകുന്നേരം/iu;

/** An upay by name, for [ANOTHER] to find its "another" beside. */
const UPAY_NAME = "(?:u+pa+y(?:e|on|o)?|upai|uppay|remed(?:y|ies)|totk(?:a|e)|tootk(?:a|e))";

/**
 * Another one: "aur koi upay", "koi aur upay", "dusra upay", "upay aur batao", "one more remedy",
 * "और उपाय", "ಇನ್ನೊಂದು ಪರಿಹಾರ" — the "another" next to the upay it is about. Anywhere else, "aur"
 * and "or" are only "and" and "or": "Upay kaise karna hai aur kab tak?" and "subah karna hai or
 * shaam ko?" ask about the one given, and were served a second one in its place.
 */
const ANOTHER = new RegExp(
  [
    "(?<![\\p{L}\\p{M}])(?:aur|or|dusra|doosra|dusri|doosri|another|more|other|naya|nayi|new)\\s+" +
    `(?:(?:koi|ek|kuch|bhi|one|any)\\s+)?${UPAY_NAME}(?![\\p{L}\\p{M}])`,
    `(?<![\\p{L}\\p{M}])${UPAY_NAME}\\s+aur(?![\\p{L}\\p{M}])`,
    "(?:और|दूसरा|दूसरी|नया|नई)\\s+(?:(?:कोई|एक|भी)\\s+)?(?:उपाय|टोटक)",
    "(?:उपाय|टोटक\\S*)\\s+और",
    "(?:ಇನ್ನೊಂದು|ಬೇರೆ)\\s+(?:ಪರಿಹಾರ|ಉಪಾಯ)",
    "(?:இன்னொரு|வேறு)\\s+(?:பரிகார|உபாய)",
    "(?:మరో|మరొక|ఇంకో|ఇంకొక)\\s+(?:పరిహార|ఉపాయ)",
    "(?:ഇനിയൊരു|മറ്റൊരു|വേറെ|വേറൊരു)\\s+(?:പരിഹാര|ഉപായ)",
  ].join("|"),
  "iu",
);

/**
 * Whether [message] asks for an upay. Once this topic's has been [given], "upay kaise karun?" and
 * "upay kab tak karna hai?" are about that one, and only a wish for another counts.
 */
export function asksForUpay(message: string, { given = false }: { given?: boolean } = {}): boolean {
  const said = message.normalize("NFC").toLowerCase().replace(/\s+/g, " ");
  if (!UPAY_WORDS.test(said)) return false;
  return !given || ANOTHER.test(said) || !ABOUT_ONE.test(said);
}

/** "Kab" and "kyun", in any of the languages: a question that still wants its window or reason. */
const STILL_ASKS =
  /(?<![\p{L}\p{M}])(?:kab|when|kyun|kyon|kyu|kyo|why)(?![\p{L}\p{M}])|कब|क्यों|ಯಾವಾಗ|ಏಕೆ|ಯಾಕೆ|எப்போது|ஏன்|ఎప్పుడు|ఎందుకు|എപ്പോ|എന്തുകൊണ്ട്/iu;

/** Longer than this, a message says more than "give me an upay". */
const BARE_ASK_WORDS = 12;

/**
 * An ask for an upay and nothing else: "upay batao", "Shaadi jaldi ho iske liye upay batao",
 * "ಪರಿಹಾರ ಹೇಳಿ" — not "karz kab utrega, koi upay bhi?", which asks for the window as well. After
 * an answer on the same subject ([upayDue]'s `afterAnswer`), such an ask is answered by the upay:
 * "कोई उपाय बताइए" restated "अगस्त 2027 से जुलाई 2028" and its reason word for word, live.
 */
export function onlyAsksForUpay(message: string): boolean {
  const said = message.normalize("NFC").toLowerCase().replace(/\s+/g, " ").trim();
  return asksForUpay(said) && !STILL_ASKS.test(said) && said.split(" ").length <= BARE_ASK_WORDS;
}

// ---------------------------------------------------------------- when one is due

/** The answer on which an upay comes when Astro knows enough; the one on which it comes anyway. */
export const UPAY_WITH_CONTEXT = 3;
export const UPAY_BY_THEN = 4;

export interface UpayDue {
  because: "asked" | "enough" | "fourth";

  /**
   * Asked for and nothing else ([onlyAsksForUpay]), on a subject an earlier answer in the thread
   * already gave its window for: the upay is this reply's answer, and the window is not said
   * again. Only ever present as true.
   */
  afterAnswer?: true;
}

/**
 * Whether this turn's answer carries an upay. See the file header. [answers] counts the answers
 * already in the thread, so this one is `answers + 1`; [context] is what Astro has to go on —
 * each detail on file, or asked for already in this thread (asked once is enough: the hour is
 * never asked twice, and someone who does not know it should not wait for an upay).
 *
 * Once the thread has had an upay, the count starts again from it ([sinceUpay]): a thread that
 * went from ghar to karz to shaadi got an upay in every reply, each the first answer on a new
 * subject, where the brief's "after 3 to 4 chat" meant one every few answers.
 *
 * Not decided here: that the reply really is an answer. Code decides before the model writes, so
 * `normaliseChatReplyV5` keeps the upay only on a reply of kind "answer", and one it drops is not
 * recorded — it is still due next turn.
 */
export function upayDue(
  { topic, message, answers, sinceUpay = null, care, sorrow = false, given = [], answered = [], context }: {
    topic: string;
    message: string;
    answers: number;
    /** Answers since the thread's last upay, or null when it has had none ([answersSinceUpay]). */
    sinceUpay?: number | null;
    /** A thread flagged for a crisis in the last day: never an upay. */
    care: boolean;
    /** Their message tells of a death, an accident or despair (`notTheMoment`). */
    sorrow?: boolean;
    /** Topics whose upay this thread already gave ([remediesGiven]). */
    given?: readonly string[];
    /** Topics the thread's answers were on ([topicsAnswered]). */
    answered?: readonly string[];
    context: { dob: boolean; hour: boolean; place: boolean };
  },
): UpayDue | null {
  if (care || sorrow) return null;
  const already = given.includes(topic);
  if (asksForUpay(message, { given: already })) {
    return answered.includes(topic) && onlyAsksForUpay(message)
      ? { because: "asked", afterAnswer: true }
      : { because: "asked" };
  }
  if (already || !REPLY_TOPIC_SET.has(topic) || topic === "general") return null;

  const turn = (sinceUpay ?? answers) + 1;
  if (turn >= UPAY_BY_THEN) return { because: "fourth" };
  if (turn >= UPAY_WITH_CONTEXT && context.dob && context.hour && context.place) {
    return { because: "enough" };
  }
  return null;
}

// ---------------------------------------------------------------- what the thread holds

/** One stored turn, as the history query reads it. */
type Row = { role: string; body?: Record<string, unknown> | null };

/**
 * Topics whose upay the thread has had: an answer that carried one (`upay_topic`, [v5Body]), and a
 * `kind: "remedy"` turn — the upay served from an offer, before the upay rode in the answer.
 */
export function remediesGiven(rows: readonly Row[]): string[] {
  const topics = rows
    .filter((row) => row.role === "astro")
    .map((row) =>
      typeof row.body?.upay_topic === "string"
        ? row.body.upay_topic
        : row.body?.kind === "remedy"
        ? String(row.body?.topic ?? "")
        : ""
    )
    .filter((topic) => topic !== "");
  return [...new Set(topics)];
}

/** The remedies the thread has had, by id. An upay served from an offer carries none. */
export function upaysGiven(rows: readonly Row[]): RemedyId[] {
  const ids = rows
    .map((row) => row.role === "astro" ? row.body?.upay_id : null)
    .filter((id): id is RemedyId => typeof id === "string" && id in REMEDIES);
  return [...new Set(ids)];
}

/** How many answers the thread holds — the count [upayDue] turns on. */
export function answersIn(rows: readonly Row[]): number {
  return rows.filter((row) => row.role === "astro" && row.body?.kind === "answer").length;
}

/**
 * How many answers came after the thread's last upay — one that rode in an answer, or a remedy
 * turn served from an offer — or null when it has had none. [rows] are newest first.
 */
export function answersSinceUpay(rows: readonly Row[]): number | null {
  let answers = 0;
  for (const row of rows) {
    if (row.role !== "astro") continue;
    if (typeof row.body?.upay_topic === "string" || row.body?.kind === "remedy") return answers;
    if (row.body?.kind === "answer") answers++;
  }
  return null;
}

/** The topics the thread's answers were on, each once. */
export function topicsAnswered(rows: readonly Row[]): string[] {
  const topics = rows
    .filter((row) => row.role === "astro" && row.body?.kind === "answer")
    .map((row) => typeof row.body?.topic === "string" ? row.body.topic : "")
    .filter((topic) => topic !== "");
  return [...new Set(topics)];
}

/** Which subject wins when a message names two: the order the topics report ranks them in. */
const TOPIC_ORDER: readonly ReplyTopic[] = [
  "marriage",
  "love",
  "children",
  "career",
  "studies",
  "money",
  "debt",
  "home",
  "health",
];

/**
 * What this turn is about, before the model has said: what the message names — the thread's own
 * subject when it is one of them — or, when it names nothing ("kab tak?", "ghar wale dhoond rahe
 * hain"), the subject of the thread's last answer. [rows] are newest first.
 */
export function turnTopic(message: string, rows: readonly Row[]): ReplyTopic {
  const named = topicsOf(message);
  const last = rows.find((row) => row.role === "astro" && typeof row.body?.topic === "string")
    ?.body?.topic as string | undefined;
  const thread = last && last !== "general" && REPLY_TOPIC_SET.has(last) ? last as ReplyTopic : null;
  if (named.size > 0) {
    return thread && named.has(thread as never)
      ? thread
      : TOPIC_ORDER.find((topic) => named.has(topic as never)) ?? "general";
  }
  return thread ?? "general";
}

// ---------------------------------------------------------------- for the prompt

const TOPIC_NAMES: Record<ReplyTopic, string> = {
  marriage: "their marriage",
  love: "their relationship",
  children: "children",
  career: "their work",
  money: "money",
  debt: "clearing their debt",
  home: "a home of their own",
  studies: "their studies and exams",
  health: "a worry about health",
  general: "what is on their mind — no one subject yet",
};

/** "Aaj Somvar hai — aaj se shuru kijiye", and the like: when they start, as they will hear it. */
function startLine(upay: Upay, today: Weekday): string {
  const day = WEEKDAYS[upay.day].name;
  if (upay.every === "day" && !remedy(upay.id).begins) {
    return upay.start === "today"
      ? `They start today: "Aaj ${WEEKDAYS[today].name} hai — aaj se hi shuru kijiye".`
      : 'They start tomorrow morning: "Kal subah se shuru kijiye".';
  }
  if (upay.start === "today") {
    return `Today is ${day}, so they start today: "Aaj ${day} hai — aaj se shuru kijiye".`;
  }
  if (upay.start === "tomorrow") {
    return `Tomorrow is ${day}, so they start tomorrow: "Kal ${day} hai — kal se shuru kijiye".`;
  }
  return `They start on the next ${day}: "Agle ${day} se shuru kijiye".`;
}

function whenLine(upay: Upay): string {
  const day = WEEKDAYS[upay.day];
  if (upay.every === "week") return `every ${day.name} (${day.english})`;
  if (remedy(upay.id).begins) return `every day, begun on a ${day.name} (${day.english})`;
  return remedy(upay.id).morning ? "every morning" : "every day";
}

/** What the chart's preference adds to the why. A day's remedy pleases its graha, whoever it is. */
function strengthLine({ graha, because }: NonNullable<Upay["strengthens"]>): string {
  return because === "kundali"
    ? `it strengthens ${graha}, which their kundali wants stronger`
    : `it pleases ${graha}, whose ${because === "antardasha" ? "Antardasha" : "Mahadasha"} runs now`;
}

/**
 * THE HOOK's return line, as they will hear it: back tomorrow to see the upay's effect only when
 * they start it today. An upay begun next Guruvar has no effect to see tomorrow, and "agle Guruvar
 * se shuru kijiye … kal wapas aaiye, iska asar dekhte hain" was said, live, in Hindi and Kannada.
 */
function returnLine(upay: Upay): string {
  const day = WEEKDAYS[upay.day].name;
  if (upay.start === "today") return '"Kal wapas aaiye, upay ka asar dekhte hain."';
  if (upay.start === "tomorrow") {
    return upay.every === "day" && !remedy(upay.id).begins
      ? '"Kal subah shuru karke wapas aaiye — bataiye kaisa laga." Never "kal wapas aaiye" alone: ' +
        "it only starts tomorrow."
      : `"Kal ${day} ko shuru karke wapas aaiye — bataiye kaisa laga." Never "kal wapas aaiye" ` +
        "alone: it only starts tomorrow.";
  }
  return `"${day} ko shuru karke wapas aaiye — bataiye kaisa laga." Never "kal wapas aaiye": it ` +
    `starts on ${day}, and there is nothing to see before then.`;
}

/**
 * THE UPAY FOR TODAY block. Its facts are given, not described — the model may word them, never
 * change them. [hook] is THE HOOK's kind this turn: the 3-month plan when it exists, a return to
 * see the upay's effect when it does not, or none when this session already had one.
 *
 * [afterAnswer]: they asked only for the upay, on what an earlier reply already answered
 * (`UpayDue.afterAnswer`) — the upay is the answer, and nothing before it says the window again.
 */
export function describeUpay(
  upay: Upay,
  { hook, afterAnswer = false }: { hook: "plan" | "return" | null; afterAnswer?: boolean },
): string {
  const weekday = upay.today;
  const why = upay.strengthens ? `${upay.why} — and ${strengthLine(upay.strengthens)}` : upay.why;

  return [
    `THE UPAY FOR TODAY — worked out in code from their topic, today's day and their chart. You ` +
    `word it; you do not choose it. Today is ${WEEKDAYS[weekday].name} ` +
    `(${WEEKDAYS[weekday].english}) in India.`,
    `- For: ${TOPIC_NAMES[upay.topic]}.`,
    `- What: ${upay.what}.`,
    `- Which day: ${whenLine(upay)}. ${startLine(upay, weekday)}`,
    `- How many times, for how long: ${upay.times}, ${upay.length}.`,
    `- Why, in one clause: ${why}.`,
    ...(upay.doctor
      ? ['- Then: "Doctor se zaroor milein." An upay is support, never treatment.']
      : []),
    'Write it as the "upay" message, in their language, in one or two short sentences: when they ' +
    "start, what to do, the day, how many times and for how long, and the why — about 35 words " +
    "with the hook. Never another day, count or length, never a second upay, and never a " +
    "mantra's words written out.",
    hook === "plan"
      ? '- THE HOOK: after the upay, in the same message, one line inviting them back for their ' +
        '3-month plan — "Kal wapas aaiye, hum aapke liye agle 3 mahine ka poora plan banayenge." ' +
        "— worded fresh."
      : hook === "return"
      ? "- THE HOOK: the 3-month plan does not exist yet, so never promise one. After the upay, " +
        `in the same message, one line inviting them back to see how it works — ${returnLine(upay)} ` +
        "— worded fresh."
      : "- THE HOOK: already given this session. No invitation back in this message.",
    ...(afterAnswer
      ? [
        "- THEY ASKED ONLY FOR THE UPAY, and an earlier reply in this conversation already answered " +
        'them on this. The upay is this reply\'s answer: "answer" is one short line leading into ' +
        'it at most — "Zaroor, ye upay kijiye." — or empty. Never the window, the dasha or the ' +
        "reason again.",
      ]
      : []),
  ].join("\n");
}
