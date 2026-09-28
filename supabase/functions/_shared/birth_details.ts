/**
 * Reading a date and hour of birth out of a chat reply.
 *
 * Chat v5 asks for these in the conversation — "Aap kis samay paida hue the?" — and reads the
 * answer in code, before the model is called, so the chart the model is given that same turn is
 * already the corrected one and the window it names comes from it.
 *
 * Deliberately narrow, like `readClock`: a wrong reading here is saved onto the user and becomes a
 * wrong chart, so anything that does not clearly say a date or a time is left alone and the turn
 * goes to the model as an ordinary message. Pure.
 */

import { readClock, StatedClock } from "./birth_time.ts";

// ---------------------------------------------------------------- digits

/** The zero of each Indian script's own digits. People type "१५/०८/१९९८" too. */
const DIGIT_ZEROS = [0x0966, 0x09e6, 0x0ae6, 0x0be6, 0x0c66, 0x0ce6, 0x0d66];

/** Every Indian-script digit as its ASCII one. */
function asciiDigits(text: string): string {
  return text.replace(/[०-९০-৯૦-૯௦-௯౦-౯೦-೯൦-൯]/g, (ch) => {
    const code = ch.codePointAt(0)!;
    const zero = DIGIT_ZEROS.find((z) => code >= z && code <= z + 9)!;
    return String(code - zero);
  });
}

// ---------------------------------------------------------------- the date

/** Every way a month is typed: English, Hinglish, Devanagari and the four southern scripts. */
const MONTHS: ReadonlyArray<readonly string[]> = [
  ["january", "jan", "janvari", "janwari", "janvary", "जनवरी", "ಜನವರಿ", "ஜனவரி", "జనవరి", "ജനുവരി"],
  [
    "february",
    "feb",
    "febuary",
    "farvari",
    "farwari",
    "farvri",
    "फरवरी",
    "फ़रवरी",
    "ಫೆಬ್ರವರಿ",
    "பிப்ரவரி",
    "ఫిబ్రవరి",
    "ഫെബ്രുവരി",
  ],
  ["march", "mar", "marach", "मार्च", "ಮಾರ್ಚ್", "மார்ச்", "మార్చి", "മാർച്ച്"],
  ["april", "apr", "aprail", "aprel", "अप्रैल", "ಏಪ್ರಿಲ್", "ஏப்ரல்", "ఏప్రిల్", "ഏപ്രിൽ"],
  ["may", "mai", "मई", "ಮೇ", "மே", "మే", "മേയ്"],
  ["june", "jun", "joon", "जून", "ಜೂನ್", "ஜூன்", "జూన్", "ജൂൺ"],
  ["july", "jul", "julai", "जुलाई", "ಜುಲೈ", "ஜூலை", "జూలై", "ജൂലൈ"],
  ["august", "aug", "agast", "agust", "अगस्त", "ಆಗಸ್ಟ್", "ஆகஸ்ட்", "ఆగస్టు", "ఆగస్ట్", "ഓഗസ്റ്റ്"],
  [
    "september",
    "sept",
    "sep",
    "sitambar",
    "sitmbar",
    "सितंबर",
    "सितम्बर",
    "ಸೆಪ್ಟೆಂಬರ್",
    "செப்டம்பர்",
    "సెప్టెంబర్",
    "സെപ്റ്റംബർ",
  ],
  [
    "october",
    "oct",
    "aktubar",
    "aktoobar",
    "अक्टूबर",
    "अक्तूबर",
    "ಅಕ್ಟೋಬರ್",
    "அக்டோபர்",
    "అక్టోబర్",
    "ഒക്ടോബർ",
  ],
  ["november", "nov", "navambar", "नवंबर", "नवम्बर", "ನವೆಂಬರ್", "நவம்பர்", "నవంబర్", "നവംബർ"],
  ["december", "dec", "disambar", "dismbar", "दिसंबर", "दिसम्बर", "ಡಿಸೆಂಬರ್", "டிசம்பர்", "డిసెంబర్", "ഡിസംബർ"],
];

/** Longest first, so "sept" is not read as "sep" and a leftover "t". */
const MONTH_WORD = MONTHS.flat().slice().sort((a, b) => b.length - a.length).join("|");

function monthOf(word: string): number | null {
  const index = MONTHS.findIndex((aliases) => aliases.includes(word.toLowerCase()));
  return index < 0 ? null : index + 1;
}

const SEP = "[\\s,./-]*";

const ISO = /(?<!\d)(\d{4})[/.-](\d{1,2})[/.-](\d{1,2})(?!\d)/u;
const NUMERIC = /(?<!\d)(\d{1,2})[/.\- ](\d{1,2})[/.\- ](\d{4}|\d{2})(?!\d)/u;
const DAY_MONTH = new RegExp(
  `(?<!\\d)(\\d{1,2})(?:st|nd|rd|th)?${SEP}(?:of\\s+)?(${MONTH_WORD})${SEP}(\\d{4}|\\d{2})(?!\\d)`,
  "iu",
);
const MONTH_DAY = new RegExp(
  `(${MONTH_WORD})${SEP}(\\d{1,2})(?:st|nd|rd|th)?${SEP}(\\d{4})(?!\\d)`,
  "iu",
);

export interface FoundDate {
  /** `YYYY-MM-DD`, as `users.dob` stores it. */
  dob: string;

  /** Where in the (digit-normalised) text it was, so the hour can be read from what is left. */
  start: number;
  end: number;
}

/**
 * A date of birth, read the way India writes one — day first — or null when the text does not
 * clearly say one.
 *
 * The same rules `update-profile` applies to a date from the picker: a real calendar day, no
 * earlier than 1900, and not in the future. Two-digit years land in the last hundred years.
 */
export function parseDob(raw: string | null | undefined, today: Date): FoundDate | null {
  const text = asciiDigits(raw ?? "");

  const candidates: Array<{ y: number; m: number; d: number; start: number; end: number }> = [];
  const push = (y: number, m: number | null, d: number, match: RegExpExecArray) => {
    if (m !== null) candidates.push({ y, m, d, start: match.index, end: match.index + match[0].length });
  };

  const iso = ISO.exec(text);
  if (iso) push(Number(iso[1]), Number(iso[2]), Number(iso[3]), iso);

  const numeric = NUMERIC.exec(text);
  if (numeric) push(fullYear(numeric[3], today), Number(numeric[2]), Number(numeric[1]), numeric);

  const dayMonth = DAY_MONTH.exec(text);
  if (dayMonth) push(fullYear(dayMonth[3], today), monthOf(dayMonth[2]), Number(dayMonth[1]), dayMonth);

  const monthDay = MONTH_DAY.exec(text);
  if (monthDay) push(Number(monthDay[3]), monthOf(monthDay[1]), Number(monthDay[2]), monthDay);

  for (const { y, m, d, start, end } of candidates.sort((a, b) => a.start - b.start)) {
    const dob = realPastDate(y, m, d, today);
    if (dob) return { dob, start, end };
  }
  return null;
}

function fullYear(raw: string, today: Date): number {
  const year = Number(raw);
  if (raw.length === 4) return year;
  const century = today.getUTCFullYear() % 100;
  return year <= century ? 2000 + year : 1900 + year;
}

/** `YYYY-MM-DD` when it is a real day between 1900 and today, else null. */
function realPastDate(y: number, m: number, d: number, today: Date): string | null {
  if (y < 1900 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  const date = new Date(Date.UTC(y, m - 1, d));
  if (date.getUTCMonth() !== m - 1 || date.getUTCDate() !== d) return null;
  if (date.getTime() > today.getTime()) return null;
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

// ---------------------------------------------------------------- the hour

/**
 * Part-of-day words in the four southern languages, as the markers `readClock` understands.
 * Hindi and Hinglish it reads already.
 */
const PART_OF_DAY: ReadonlyArray<readonly [RegExp, string]> = [
  [/ಬೆಳಿಗ್ಗೆ|ಬೆಳಗ್ಗೆ|காலை|ఉదయం|രാവിലെ/gu, " morning "],
  [/ಮಧ್ಯಾಹ್ನ|மதியம்|మధ్యాహ్నం|ഉച്ച/gu, " afternoon "],
  [/ಸಂಜೆ|ಸಾಯಂಕಾಲ|மாலை|సాయంత్రం|വൈകുന്നേരം|വൈകിട്ട്/gu, " evening "],
  [/ರಾತ್ರಿ|இரவு|రాత్రి|രാത്രി/gu, " night "],
];

/** An hour said without minutes: "7 baje", "7pm", "shaam 7", "raat 2 baje", "ಸಂಜೆ 7 ಗಂಟೆ". */
const HOUR_ONLY =
  /(?<![\d:.])(\d{1,2})(?![\d:.])\s*(?:baje|bje|baj|o'?clock|बजे|ಗಂಟೆ|மணி|గంటలకు|గంటకు|గంటలు|മണി)?\s*(am|pm|a\.m\.|p\.m\.)?/iu;

const HAS_MARKER =
  /(?<![a-z])(?:am|pm|a\.m\.|p\.m\.|morning|afternoon|evening|night|noon|midnight|subah|subha|savere|sawere|shaam|sham|dopahar|dopehar|raat)(?![a-z])|सुबह|सवेरे|शाम|दोपहर|रात/iu;
const HAS_UNIT = /(?<![a-z])(?:baje|bje|baj|o'?clock)(?![a-z])|बजे|ಗಂಟೆ|மணி|గంట|മണി/iu;

/**
 * The hour of birth in a reply, as [StatedClock]: a time, an ambiguous time ("7:30", "7 baje" —
 * morning or night?), or nothing.
 *
 * Any date in the text is cut out first. `readClock` takes the first `H:MM`-shaped thing it
 * finds, and "15.08.1998 7:30 pm" would otherwise be read as 15:08.
 */
export function parseHour(raw: string | null | undefined, today: Date): StatedClock {
  let text = asciiDigits(raw ?? "");
  const date = parseDob(text, today);
  if (date) text = `${text.slice(0, date.start)} ${text.slice(date.end)}`;

  for (const [pattern, marker] of PART_OF_DAY) text = text.replace(pattern, marker);

  // Minutes said as a word — "12 pm 9 minit", "7 baj kar 15 minat", "4 बजकर 20 मिनट" — become the
  // H:MM `readClock` reads, with any am/pm kept beside it.
  text = text.replace(
    /(?<!\d)(\d{1,2})\s*(?:baje|bje|baj(?:\s*kar)?|o'?clock|बजकर|बजे)?\s*(am|pm|a\.m\.|p\.m\.)?\s*(\d{1,2})\s*(?:min(?:it|ute|at|ut)?s?|मिनट)(?![a-z])/iu,
    (_, h: string, half: string | undefined, m: string) => `${h}:${m.padStart(2, "0")} ${half ?? ""}`,
  );

  // A clock written without its colon — "0630 ಸಂಜೆ" — only beside a part of the day, and never
  // anything that reads as a year.
  if (HAS_MARKER.test(text)) {
    text = text.replace(/(?<![\d:.])([01]\d|2[0-3])([0-5]\d)(?![\d:.])/u, (whole, h: string, m: string) =>
      /^(19|20)\d\d$/.test(whole) ? whole : `${h}:${m}`
    );
  }

  const stated = readClock(text);
  if (stated.time || stated.ambiguous) return stated;

  // No minutes. Only an hour that is clearly an hour — next to "baje", or with a part of the day
  // — so "25 saal" or a stray number is never read as a birth time.
  const hour = HOUR_ONLY.exec(text);
  if (!hour) return { time: null, ambiguous: false };
  const value = Number(hour[1]);
  if (value > 23) return { time: null, ambiguous: false };
  if (!hour[2] && !HAS_MARKER.test(text) && !HAS_UNIT.test(text)) {
    return { time: null, ambiguous: false };
  }

  return readClock(`${value}:00 ${hour[2] ?? ""} ${text}`);
}

// ---------------------------------------------------------------- correcting

/**
 * Whether they are saying the date or time on file is wrong.
 *
 * DOB is required before anyone reaches the chat, so a date read from a chat reply always
 * replaces one already saved — and in a question about someone else ("uski DOB 12/3/1999") a
 * date is not theirs at all. A date is only ever taken when this is true of the conversation.
 */
export function correctionIntent(raw: string | null | undefined): boolean {
  return /(?<![a-z])(?:galat|galt|wrong|incorrect|mistake|asli|actual|correct|sahi\s*(?:date|tarikh|tareekh|tithi|dob|time|samay))(?![a-z])|गलत|ग़लत|असली|सही\s*(?:तारीख|तिथि|समय)|ತಪ್ಪು|தவறு|తప్పు|തെറ്റ്/iu
    .test(raw ?? "");
}

/** The date of birth, named as such: "DOB", "date of birth", "janm tithi", "जन्मतिथि", "ಜನ್ಮ ದಿನಾಂಕ". */
const DOB_WORDS =
  /(?<![a-z])(?:d\.?o\.?b|date\s*of\s*birth|birth\s*-?date|b(?:irth)?'?day|jan(?:a|u)?m\s*(?:ki\s*)?(?:tithi|tarikh|tareekh|tarik|date|din))(?![a-z])|जन्म\s*(?:की\s*)?(?:तिथि|तारीख|तारीख़|दिन)|जन्मतिथि|जन्मदिन|ಜನ್ಮ\s*ದಿನಾಂಕ|ಹುಟ್ಟಿದ\s*ದಿನ|பிறந்த\s*(?:தேதி|நாள்)|పుట్టిన\s*(?:తేదీ|రోజు)|జన్మ\s*తేదీ|ജനന\s*തീയതി|ജനനത്തീയതി/iu;

/** Theirs: "meri", "my", "मेरी", "ನನ್ನ", "என்", "నా", "എന്റെ". */
const FIRST_PERSON =
  /(?<![a-z])(?:meri|mera|mere|my|mine|apni|apna|mujhe|maine)(?![a-z])|(?<![\p{L}\p{M}])(?:मेरी|मेरा|मेरे|अपनी|मुझे|मैंने|माझी|माझं|माझा|ನನ್ನ|ನನ್ನದು|என்|என்னுடைய|నా|నాది|എന്റെ)(?![\p{L}\p{M}])/iu;

/**
 * Somebody else's: "beti ki DOB", "uski date of birth", "पति की जन्मतिथि". A date beside any of
 * these may be theirs, and is not ours to save. Not "he", which is how half of chat spells "hai".
 */
const SOMEONE_ELSE =
  /(?<![a-z])(?:beti|beta|bete|bitiya|pati|patni|wife|husband|biwi|bhai|bhaiya|behen|bahen|behan|didi|papa|pitaji|mummy|mummi|maa|mom|dad|father|mother|son|daughter|brother|sister|dost|friend|gf|bf|boyfriend|girlfriend|partner|uski|uska|uske|unki|unka|unke|his|her|she|ladk[aeio]|bach+[aeio]|baby|sasur|saas|devar|nanad|jija|bhabhi|chacha|chachi|mama|mami|nana|nani|dada|dadi)(?![a-z])|बेटी|बेटा|बेटे|पति|पत्नी|भाई|बहन|दीदी|पापा|पिताजी|मम्मी|माँ|मां|दोस्त|उसकी|उसका|उसके|उनकी|उनका|उनके|लड़क|लडक|बच्च|ಮಗ|ಅವರ|ಅವನ|ಅವಳ|ಗಂಡ|ಹೆಂಡತಿ|மகன்|மகள்|அவர|அவன|அவள|கணவ|மனைவி|కొడుకు|కూతురు|ఆయన|ఆమె|అతని|భర్త|భార్య|മക(?:ൻ|ന്|ൾ|ള്)|അവന|അവള|അവര|ഭർത്താ|ഭാര്യ/iu;

/**
 * Whether [raw] says, unasked, that the date of birth on file is wrong and that the right one is
 * theirs — "meri DOB galat save ho gayi hai, sahi wali 3 January 2000 hai". The one date read
 * without Astro having asked for it: left to the model, that message got "Maine sahi janm tithi
 * note kar li hai" and nothing saved, and every window after it came from the wrong chart.
 *
 * All four, or it is not taken: a correction, the date of birth named as such, a word that it is
 * their own, and no word for anyone else. What misses here is asked for in the chat and read from
 * the reply the usual way.
 */
export function correctsOwnDate(raw: string | null | undefined): boolean {
  const text = raw ?? "";
  return correctionIntent(text) && DOB_WORDS.test(text) && FIRST_PERSON.test(text) &&
    !SOMEONE_ELSE.test(text);
}

/**
 * "Wrong", said outright. Narrower than [correctionIntent], which also hears "sahi time" and
 * "actual" — and "shaadi ka sahi time kab hai?" asks for a window, not to be asked for an hour.
 */
const WRONG = /(?<![a-z])(?:galat|galt|wrong|incorrect|mistake)(?![a-z])|गलत|ग़लत|चुकीच|ತಪ್ಪು|தவறு|తప్పు|തെറ്റ്/iu;

/**
 * A date by a bare word for one, said as theirs — "meri date galat hai", "ನನ್ನ ದಿನಾಂಕ ತಪ್ಪು": the
 * word straight after "my". Anywhere else a bare word is not their birth detail: "maine galat
 * date par shaadi fix ki?" is about a wedding date, and was asked for a date of birth.
 */
const OWN_DATE =
  /(?<![a-z])(?:meri|mera|my|apni)\s+(?:date|tarikh|tareekh|tarik|tithi)(?![a-z])|(?:मेरी|मेरा|अपनी)\s+(?:तारीख|तिथि)|ನನ್ನ\s+ದಿನಾಂಕ|(?:என்|என்னுடைய)\s+தேதி|నా\s+తేదీ|എന്റെ\s+തീയതി/iu;

/** The hour of birth, named as such: "birth time", "janm ka samay", "जन्म समय", "ಜನ್ಮ ಸಮಯ". */
const BIRTH_TIME_WORDS =
  /(?<![a-z])(?:birth\s*time|time\s*of\s*birth|jan(?:a|u)?m\s*(?:ka\s*)?(?:samay|time)|paida\s*hone\s*ka\s*(?:samay|time))(?![a-z])|जन्म\s*(?:का\s*)?समय|ಜನ್ಮ\s*ಸಮಯ|ಹುಟ್ಟಿದ\s*ಸಮಯ|பிறந்த\s*நேர|పుట్టిన\s*సమయ|ജനന\s*സമയ/iu;

/** A time by a bare word, said as theirs: "mera time galat hai" — see [OWN_DATE]. */
const OWN_TIME =
  /(?<![a-z])(?:mera|meri|my|apna)\s+(?:time|samay|samai)(?![a-z])|(?:मेरा|मेरी|अपना)\s+समय|ನನ್ನ\s+ಸಮಯ|(?:என்|என்னுடைய)\s+நேர|నా\s+సమయ|എന്റെ\s+സമയ/iu;

/** The place of birth, named as such: "birth place", "janm sthan", "जन्म स्थान", "ಹುಟ್ಟಿದ ಸ್ಥಳ". */
const BIRTH_PLACE_WORDS =
  /(?<![a-z])(?:birth\s*-?place|place\s*of\s*birth|jan(?:a|u)?m\s*(?:ka\s*|ki\s*)?(?:sthan|sthal|jagah|jaga|shehar|shahar|place|city)|janmsthan|paida\s*hone\s*ki\s*(?:jagah|jaga))(?![a-z])|जन्म\s*(?:का\s*|की\s*)?(?:स्थान|स्थल|जगह|शहर)|जन्मस्थान|ಹುಟ್ಟಿದ\s*(?:ಸ್ಥಳ|ಊರು)|ಜನ್ಮ\s*ಸ್ಥಳ|பிறந்த\s*(?:இடம்|ஊர்)|పుట్టిన\s*(?:ప్రదేశ|ఊరు)|జన్మ\s*స్థల|ജനന\s*സ്ഥല|ജനിച്ച\s*സ്ഥല/iu;

/**
 * A place by a bare word, said as theirs: "meri jagah galat save hai" — see [OWN_DATE]. "Maine
 * galat jagah naukri le li" is about a job.
 */
const OWN_PLACE =
  /(?<![a-z])(?:meri|mera|my|apni|apna)\s+(?:jagah|sthan|shehar|shahar|city|place)(?![a-z])|(?:मेरी|मेरा|अपनी|अपना)\s+(?:स्थान|जगह|शहर)|ನನ್ನ\s+ಸ್ಥಳ|(?:என்|என்னுடைய)\s+இடம்|నా\s+ప్రదేశ|എന്റെ\s+സ്ഥല/iu;

/**
 * "Mera time galat chal raha hai": a bad phase, not a wrong hour — and no bare word beside it is
 * a birth detail. Asked for their correct hour, one such message re-cast an unchanged kundali.
 */
const A_PHASE = /(?<![a-z])(?:chal|ho)\s*(?:raha|rahi|rahe|rha|rhi|rhe)(?![a-z])|(?:चल|हो)\s*(?:रहा|रही|रहे)/iu;

/**
 * Which of their own birth details [raw] says is wrong, with or without the right one beside it —
 * "meri DOB galat hai", "mera birth time galat save hai", "mera janm sthan galat hai" — so the
 * sawal asks for it (`chat_sawal.ts`). The date before the hour, and the hour before the place,
 * when more than one is named. A bare "date", "time" or "jagah" counts only right after "my"
 * ([OWN_DATE]) and never in a "chal raha hai" ([A_PHASE]), and nothing counts beside a word for
 * someone else: "galat date bata rahe ho" is about a window, "papa ki DOB galat hai" about papa.
 */
export function saysOwnDetailWrong(
  raw: string | null | undefined,
): "dob" | "birth_time" | "birth_place" | null {
  const text = raw ?? "";
  if (!WRONG.test(text) || SOMEONE_ELSE.test(text)) return null;
  const bare = !A_PHASE.test(text);
  if (DOB_WORDS.test(text) || (bare && OWN_DATE.test(text))) return "dob";
  if (BIRTH_TIME_WORDS.test(text) || (bare && OWN_TIME.test(text))) return "birth_time";
  if (BIRTH_PLACE_WORDS.test(text) || (bare && OWN_PLACE.test(text))) return "birth_place";
  return null;
}

/**
 * The part of [update] that differs from what is on file — a date or an hour said again, the same,
 * is a confirmation and nothing to write. Times compare to the minute: "07:00" is "07:00:00".
 */
export function changedDetails(
  update: { dob?: string; birth_time?: string },
  onFile: { dob?: string | null; birth_time?: string | null },
): { dob?: string; birth_time?: string } {
  const changed: { dob?: string; birth_time?: string } = {};
  if (update.dob !== undefined && update.dob !== onFile.dob) changed.dob = update.dob;
  if (update.birth_time !== undefined && update.birth_time.slice(0, 5) !== (onFile.birth_time ?? "").slice(0, 5)) {
    changed.birth_time = update.birth_time;
  }
  return changed;
}
