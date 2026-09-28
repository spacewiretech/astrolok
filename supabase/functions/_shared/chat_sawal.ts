/**
 * The one question every v5 reply ends on — the sawal — chosen in code.
 *
 * The product team's arc (28 Sep) ends each answer with "1 question about their real situation,
 * which will help the next answer", and wants Astro to gather what a real pandit asks for before
 * he reads — the date, hour and place of birth — the way one would: one at a time, each once, and
 * then questions about the person. Left to the model, v5 asked for the hour when it pleased (v4
 * needed `birthHourAsks` because it could not stop), never for the place, and rarely about the
 * person at all. So the code decides, in this order ([sawalFor]):
 *
 * 0. Under a crisis or a loss, a question about them and nothing else; after a place just found,
 *    the check on it — "Rampur, Uttar Pradesh — sahi hai na?" — alone, so a "nahi" is its answer.
 * 1. Their date of birth: when it is not on file or they say it is wrong (twice at most in a
 *    thread, either way), or when their answer to the ask could not be read.
 * 2. Their hour of birth: when it is not on file and not yet asked or declined in this thread; or,
 *    once more, when it came without morning or night, could not be read, or they say it is wrong.
 * 3. Their place of birth: when it is not located and not yet asked in this thread; or, once more,
 *    when what they gave could not be found on the map, or they say it is wrong
 *    (`chat_birth_place.ts` reads the answer).
 * 4. Otherwise a question about their situation on the topic, the kind a pandit ji asks to know
 *    them — "Rishta ghar wale dhoond rahe hain ya aap khud?" — never one this thread has asked;
 *    for a question on no subject the chat reads, what lies behind it.
 *
 * `ask_for` follows from this and from nothing else: the model no longer writes it. A crisis
 * thread is asked only about them, and a greeting what they would like to know. Pure.
 */

import type { AskForV5, ReplyTopic } from "./astro_chat_v5.ts";
import type { BirthHourAsks } from "./astro_chat.ts";
import { saysOwnDetailWrong } from "./birth_details.ts";

/** A question about their situation, as a pandit ji would ask it. */
export interface SituationQuestion {
  id: string;

  /** What it asks, for the prompt — the model words it fresh. */
  about: string;

  /** One way to say it, in Hinglish. */
  example: string;

  /** The sort of first-person answers the options are, in Hinglish. */
  answers: readonly string[];
}

const q = (id: string, about: string, example: string, answers: string[]): SituationQuestion => ({
  id,
  about,
  example,
  answers,
});

/**
 * Per topic, in the order they are asked. Each question's answers stay inside what `offTopic`
 * allows under the topic — "Shaadi ko kitne saal hue?" is not here under children, because its
 * answer names marriage and the chip would be dropped.
 */
const SITUATIONS: Record<ReplyTopic, readonly SituationQuestion[]> = {
  marriage: [
    q("marriage.who_looks", "whether the family is looking for the match, or they themselves",
      "Rishta ghar wale dhoond rahe hain ya aap khud?", ["Ghar wale dhoond rahe hain", "Meri apni pasand hai"]),
    q("marriage.talks", "whether a proposal is being talked about at home right now",
      "Kya abhi ghar mein kisi rishte ki baat chal rahi hai?", ["Haan, ek rishta aaya hai", "Abhi koi baat nahi"]),
    q("marriage.since", "how long the family has been looking",
      "Kitne samay se rishta dekh rahe hain?", ["Ek saal se", "Abhi shuru kiya hai"]),
    q("marriage.hopes", "what matters most to them in a partner",
      "Jeevansathi mein aapke liye sabse zaroori kya hai?", ["Accha swabhav", "Samajhdaar ho", "Parivaar ko maane"]),
  ],
  love: [
    q("love.last_talk", "when the two of them last spoke",
      "Aap dono ki aakhri baat kab hui thi?", ["Ek hafte pehle", "Mahino se baat nahi hui"]),
    q("love.between", "what came between them",
      "Aap dono ke beech doori kis baat par aayi?", ["Ghar walon ki wajah se", "Ek chhoti si ladai"]),
    q("love.how_long", "how long they have been together",
      "Aap kitne samay se saath hain?", ["Do saal se", "Abhi naya hai"]),
  ],
  children: [
    q("children.since", "how long they have been hoping for a child",
      "Kitne samay se santan ki umeed kar rahe hain?", ["Ek saal se", "Teen saal se zyada"]),
    q("children.first", "whether it would be their first child",
      "Ye pehli santan hogi ya doosri?", ["Pehli santan", "Doosri santan"]),
  ],
  career: [
    q("career.field", "what field they work in, or want to",
      "Aap abhi kis field mein kaam kar rahe hain?", ["IT mein job hai", "Abhi padhai chal rahi hai", "Apna business hai"]),
    q("career.sarkari", "whether they want a government job or a private one",
      "Sarkari naukri ki taiyari hai ya private?", ["Sarkari ki taiyari", "Private job chahiye"]),
    q("career.change", "whether they have a job and want a change, or are looking for their first",
      "Abhi naukri hai aur badalni hai, ya pehli naukri dhoond rahe hain?", ["Naukri badalni hai", "Pehli naukri chahiye"]),
  ],
  money: [
    q("money.where", "where money gets stuck — the earning or the spending",
      "Paisa kamai mein atakta hai ya kharche zyada hain?", ["Kamai kam hai", "Kharche zyada hain"]),
    q("money.since", "how long money has been tight",
      "Kab se paise ki tangi chal rahi hai?", ["Ek saal se", "Kuch mahino se"]),
  ],
  debt: [
    q("debt.kind", "whether the debt is a bank loan or money owed to people",
      "Karz bank ka hai ya logon ka?", ["Bank ka loan hai", "Logon ka udhaar hai"]),
    q("debt.since", "how long the debt has been running",
      "Ye karz kitne samay se chal raha hai?", ["Do saal se", "Kuch mahino se"]),
  ],
  home: [
    q("home.buy_build", "whether they want to buy a home or build one",
      "Ghar khareedna chahte hain ya banwana?", ["Khareedna hai", "Banwana hai"]),
    q("home.land", "whether they already have land or a plot",
      "Kya aapke paas zameen ya plot pehle se hai?", ["Haan, plot hai", "Abhi nahi"]),
  ],
  studies: [
    q("studies.exam", "which exam they are preparing for",
      "Aap kaunse exam ki taiyari kar rahe hain?", ["SSC ki taiyari", "College ke exam", "UPSC"]),
    q("studies.attempt", "whether this is their first attempt",
      "Ye aapka pehla attempt hai ya pehle bhi diya hai?", ["Pehla attempt hai", "Pehle bhi diya hai"]),
  ],
  health: [
    q("health.who", "whose health they are worried about — their own, or someone's at home",
      "Aapko kiski chinta hai — apni ya ghar mein kisi ki?", ["Apni chinta hai", "Mummy ki chinta hai"]),
  ],
  general: [
    q("general.mind", "what is on their mind most right now",
      "Aap abhi sabse zyada kis baat ko lekar soch rahe hain — shaadi, naukri ya paisa?",
      ["Shaadi ke baare mein", "Naukri ke baare mein", "Paise ke baare mein"]),
  ],
};

/**
 * For a question on no subject the chat reads — "Mangal dosh ka upay batao", "videsh mein settle
 * ho paunga?", a Tamil question about one person — a question about what lies behind it. The
 * general menu's "shaadi, naukri ya paisa?" is for a greeting or a message that asks nothing:
 * after a question it asked them to choose a subject they had just named.
 */
const BEHIND_A_QUESTION: readonly SituationQuestion[] = [
  q("general.behind", "what has happened that brings this question to mind",
    "Aisa kya hua jisse ye sawal mann mein aaya?", ["Kuch samay se pareshani hai", "Bas jaanne ke liye"]),
  q("general.since", "how long this has been on their mind",
    "Ye baat kab se mann mein chal rahi hai?", ["Kuch mahino se", "Bahut samay se"]),
];

/** Every situational question, by id — for a thread's asked list, whatever topic it was on. */
const BY_ID = new Map(
  [...Object.values(SITUATIONS).flat(), ...BEHIND_A_QUESTION].map((question) => [question.id, question]),
);

/** A date of birth not on file is asked for this many times in a thread, and then left. */
const DOB_ASKS = 2;

/** The hour, asked again after a first ask — a time without morning or night, say — once. */
const HOUR_ASKS = 2;

/** The place, asked again after a first ask — a town the map could not find, say — once. */
const PLACE_ASKS = 2;

/**
 * A greeting and nothing else: "hi", "namaste ji", "ನಮಸ್ಕಾರ", "வணக்கம்". Asked for their hour in
 * reply, someone who has not yet said what they want is being handed a form.
 */
const GREETING =
  /^(?:h+i+|hello|helo|hey|hlo|namaste|namaskar|namaskaram|pranam|ram ram|radhe radhe|jai shri (?:ram|krishna)|good (?:morning|afternoon|evening)|नमस्ते|नमस्कार|प्रणाम|राम राम|राधे राधे|हेलो|हाय|ನಮಸ್ಕಾರ|ನಮಸ್ತೆ|வணக்கம்|నమస్కారం|నమస్తే|നമസ്കാരം|ഹലോ)(?: (?:ji|guru ?ji|pandit ?ji|astro|sir|जी))?$/iu;

export function isGreeting(message: string): boolean {
  const said = message.normalize("NFC").toLowerCase()
    .replace(/[\p{Extended_Pictographic}\u{FE0F}\u{200D}.,!?।]/gu, "").replace(/\s+/g, " ").trim();
  return GREETING.test(said);
}

/** A question, in any of the languages — something asked, not something told. */
const QUESTION =
  /[?？]|(?<![\p{L}\p{M}])(?:kab|kya|kyu|kyun|kyon|kaise|kaisa|kaisi|kitna|kitni|kitne|kaun|when|what|why|how|who|which|will|should|batao|bataiye|btao|btaiye|bataye)(?![\p{L}\p{M}])|कब|क्या|क्यों|कैसे|कैसा|कैसी|बताओ|बताइए|बताएं|ಯಾವಾಗ|ಏನು|ಹೇಗೆ|எப்போது|என்ன|எப்படி|ఎప్పుడు|ఏమి|ఎలా|എപ്പോൾ|എന്ത്|എങ്ങനെ/iu;

/** Whether [message] asks something: a question mark, or a question word in any language. */
export function asksSomething(message: string): boolean {
  return QUESTION.test(message.normalize("NFC"));
}

export interface SawalContext {
  /** What this turn is about (`turnTopic`). */
  topic: ReplyTopic;
  message: string;

  /** A thread flagged for a crisis in the last day. */
  care: boolean;

  /**
   * Their message tells of a death, an accident or despair (`notTheMoment`) — the turn that holds
   * back THE KUNDALI LINE and the upay for the same reason. No birth detail is asked under it.
   */
  sorrow?: boolean;

  /** The date of birth is on file — a chart could be cast. */
  dob: boolean;

  /** The hour of birth is on file. */
  hour: boolean;

  /**
   * Their place of birth is located: coordinates, or the Google place id they came from.
   * `purge_expired` clears the coordinates after thirty days and keeps the id, so the id alone
   * still counts — someone who chose their town on the Kundali form is not asked for it again.
   */
  place: boolean;

  hourAsks: BirthHourAsks;

  /** Replies in this thread that asked for the date, and for the place ([asksFor]). */
  dobAsks: number;
  placeAsks: number;

  /** Situational questions this thread has asked, by id ([sawalsAsked]). */
  asked: readonly string[];

  /** The detail this message just gave, which was saved: nothing about it is wrong any more. */
  captured?: "dob" | "birth_time" | "birth_place" | null;

  /**
   * The detail the last reply asked for, which this message could not be read as — or, for the
   * place, could not be found on the map.
   */
  captureFailed?: "dob" | "birth_time" | "birth_place" | null;

  /** They said "nahi" to the place the last reply said back, and gave no other. */
  placeDenied?: boolean;

  /** They gave an hour without morning or night. */
  unsettled?: boolean;
}

export interface SawalPlan {
  /**
   * What the question is about. "place_check" is the place just found, said back — "Rampur,
   * Uttar Pradesh — sahi hai na?" — as the reply's only question ([sawalFor]).
   */
  about: "dob" | "birth_time" | "birth_place" | "place_check" | "situation" | "sorrow" | "care";

  /** What the app raises a control for, as the reply's `ask_for` — none for a situation. */
  askFor: AskForV5;

  /** Why a birth detail is asked. */
  because: "missing" | "wrong" | "unreadable" | "unsettled" | null;

  /** The situational question, when one of the topic's is left to ask. */
  question: SituationQuestion | null;

  /** The situational questions this thread asked already, for the block to rule out. */
  asked: SituationQuestion[];
}

/** The sawal for this turn. See the file header for the order. */
export function sawalFor(c: SawalContext): SawalPlan {
  const asked = c.asked.map((id) => BY_ID.get(id)).filter((q): q is SituationQuestion => !!q);
  const plan = (
    about: SawalPlan["about"],
    askFor: AskForV5,
    because: SawalPlan["because"] = null,
    question: SituationQuestion | null = null,
  ): SawalPlan => ({ about, askFor, because, question, asked });

  if (c.care) return plan("care", "none");
  // Under a loss, a question about them; the birth details wait for another turn, uncounted.
  if (c.sorrow) return plan("sorrow", "none");
  // A place just found is checked, and nothing else is asked beside it: a reply that also asked
  // "Kya abhi ghar mein kisi rishte ki baat chal rahi hai?" had its "Nahi, abhi koi baat nahi"
  // read as a "nahi" to the place (`chat_birth_place.ts`).
  if (c.captured === "birth_place") return plan("place_check", "none");

  // What was just saved is not wrong; anything else they call wrong is asked for again.
  const wrong = saysOwnDetailWrong(c.message);
  const wrongNow = wrong && wrong !== c.captured ? wrong : null;

  // 1. The date — without it there is no chart to read at all. Called wrong, it is asked for as
  // often as a missing one and no more: the hour and the place had a cap, and the date had none.
  if (wrongNow === "dob" && c.dobAsks < DOB_ASKS) return plan("dob", "dob", "wrong");
  if (c.captureFailed === "dob" && c.dobAsks <= DOB_ASKS) return plan("dob", "dob", "unreadable");
  if (!c.dob && c.dobAsks < DOB_ASKS) return plan("dob", "dob", "missing");

  const situation = () => {
    // A question the chat reads no subject in is asked what lies behind it, never to pick one.
    const unnamed = c.topic === "general" && !isGreeting(c.message) && asksSomething(c.message);
    const menu = unnamed ? BEHIND_A_QUESTION : SITUATIONS[c.topic] ?? SITUATIONS.general;
    const next = menu.find((question) => !c.asked.includes(question.id)) ?? null;
    return plan("situation", "none", null, next);
  };

  // A greeting is asked what they want before anything is asked of them.
  if (isGreeting(c.message) && c.topic === "general") return situation();
  if (!c.dob) return situation();

  // 2. The hour: once when it is missing; once more when what they gave could not be used.
  const hourOpen = !c.hourAsks.declined;
  if (hourOpen && c.hourAsks.asked < HOUR_ASKS) {
    if (wrongNow === "birth_time") return plan("birth_time", "birth_time", "wrong");
    if (c.captureFailed === "birth_time") return plan("birth_time", "birth_time", "unreadable");
    if (c.unsettled) return plan("birth_time", "birth_time", "unsettled");
  }

  // 3. The place — ahead of a missing hour when it is the place they just answered about.
  if (c.placeAsks < PLACE_ASKS) {
    if (wrongNow === "birth_place" || c.placeDenied) return plan("birth_place", "birth_place", "wrong");
    if (c.captureFailed === "birth_place") return plan("birth_place", "birth_place", "unreadable");
  }
  if (!c.hour && hourOpen && c.hourAsks.asked === 0) {
    return plan("birth_time", "birth_time", "missing");
  }
  if (!c.place && c.placeAsks === 0) return plan("birth_place", "birth_place", "missing");

  // 4. Their situation.
  return situation();
}

// ---------------------------------------------------------------- what the thread holds

type Row = { role: string; body?: Record<string, unknown> | null };

/** How many of the thread's replies asked for [detail] — the `ask_for` each one stored. */
export function asksFor(rows: readonly Row[], detail: "dob" | "birth_place"): number {
  return rows.filter((row) => row.role === "astro" && row.body?.ask_for === detail).length;
}

/** The situational questions the thread's replies asked, by id (`sawal_id`, `v5Body`). */
export function sawalsAsked(rows: readonly Row[]): string[] {
  const ids = rows
    .map((row) => row.role === "astro" ? row.body?.sawal_id : null)
    .filter((id): id is string => typeof id === "string" && id !== "");
  return [...new Set(ids)];
}

// ---------------------------------------------------------------- for the prompt

const quoted = (answers: readonly string[]) => answers.map((answer) => `"${answer}"`).join(", ");

/**
 * THE QUESTION TO ASK block. [placeSaid] is a birth place on file as words only — said in the chat
 * once, never located — which the question then names rather than asking as if it were unknown.
 * [placeFound] is the place this turn found on the map, as it is said back for the check.
 */
export function describeSawal(
  plan: SawalPlan,
  { placeSaid = null, placeFound = null }: { placeSaid?: string | null; placeFound?: string | null } = {},
): string {
  const head = 'THE QUESTION TO ASK — the "sawal", chosen in code. Exactly one question, this one:';
  const never = plan.asked.length > 0
    ? `\nNever one of the questions already asked in this conversation: ${
      plan.asked.map((question) => question.about).join("; ")
    }.`
    : "";

  switch (plan.about) {
    case "care":
      return `${head} one gentle question about them — whether there is someone they trust they ` +
        "can talk to right now. Never a birth detail, never anything about the chart.";

    case "sorrow":
      return `${head} one gentle question about them — how they are holding up, or who is with ` +
        "them now. Never a birth detail and nothing about the chart: that can wait for another " +
        "day.\nThe options are two short answers about them, in their words.";

    case "place_check": {
      const found = placeFound?.trim() || "‹the place›";
      return `${head} the check on the place of birth just found — "${found} — sahi hai na?", ` +
        "worded fresh in their language — and nothing else. It is this reply's one question: no " +
        "question about their situation beside it; that waits for the next reply." +
        '\nThe options are two short answers to it, in their words — like "Haan, sahi hai", ' +
        '"Nahi, dusri jagah hai".';
    }

    case "dob":
      return `${head} ` + (plan.because === "wrong"
        ? 'their correct date of birth — they say the one on file is wrong. "Sahi janm tithi ' +
          'likhiye, jaise 15 August 1998."'
        : plan.because === "unreadable"
        ? "their date of birth, once more — their last reply could not be read as one. Gently, " +
          'with an example: "jaise 15 August 1998".'
        : "their date of birth. It is not on file, and every window comes from it. One sentence " +
          'and the question: "Apni janm tithi batayein, jaise 15 August 1998 — isse main aapki ' +
          'kundali dekh sakta hoon."');

    case "birth_time":
      return `${head} ` + (plan.because === "wrong"
        ? 'their correct hour of birth — they say the one on file is wrong. "Sahi janm samay ' +
          'batayein, jaise subah 7:30 ya raat 10 baje."'
        : plan.because === "unreadable"
        ? "their hour of birth, once more — their last reply could not be read as one. Gently, " +
          'with an example: "jaise subah 7:30 ya raat 10 baje".'
        : plan.because === "unsettled"
        ? "whether the hour they gave was in the morning or at night — without that it cannot be " +
          "used. One short line."
        : "their hour of birth — not on file, and not asked for yet in this conversation. One " +
          'sentence and the question: "Janm ka sahi samay mile toh main aur pakka bata sakta hoon ' +
          '— aap kis samay paida hue the, jaise subah 7:30 ya raat 10 baje?" The answer before ' +
          "it still gives THE TIMING's window in full: the hour only makes it finer.") +
        " The app puts its own button for the time under it.";

    case "birth_place": {
      const said = placeSaid?.trim();
      return `${head} ` + (plan.because === "wrong"
        ? "their correct place of birth — they say the one they gave is wrong. The town and the " +
          'state: "Sahi janm sthan batayein — shehar aur rajya, jaise Rampur, Uttar Pradesh."'
        : plan.because === "unreadable"
        ? "the town and the state they were born in, once more — the place they gave could not " +
          'be found on the map, and nothing is saved. Gently, with an example: "Kaunsa shehar ' +
          'aur kaunsa rajya? Jaise Rampur, Uttar Pradesh."'
        : said
        ? `the city or town they were born in, exactly. They once told you "${said}"; name it ` +
          `and ask which town — "Aapne janm sthan ${said} bataya tha — kaunsa shehar ya kasba, ` +
          'thoda sahi bata dijiye?"'
        : "the city or town they were born in — not on file, and not asked for yet in this " +
          'conversation. One sentence and the question: "Aap kis shehar ya kasbe mein paida hue ' +
          'the? Isse kundali aur pakki banti hai."') +
        " The app may put its own place search under it; never mention it.";
    }

    case "situation":
      return plan.question
        ? `${head} one question about their situation, the kind a pandit ji asks to understand ` +
          `them — ${plan.question.about}: "${plan.question.example}", worded fresh in their ` +
          "language. If this conversation or WHAT YOU ALREADY KNOW already answers it, ask one " +
          "more like it on the same subject instead." + never +
          `\nThe options are two or three short answers to it, in their words — like ` +
          `${quoted(plan.question.answers)}.`
        : `${head} one new question about their situation on this subject, the kind a pandit ji ` +
          "asks to understand them." + never +
          "\nThe options are two or three short answers to it, in their words.";
  }
}
