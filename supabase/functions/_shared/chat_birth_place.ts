/**
 * The place of birth, told to Astro in the chat: read, found on the map, and saved.
 *
 * Chat v5 asks for it (`chat_sawal.ts`, `ask_for: "birth_place"`) after the date and the hour —
 * the last thing a pandit ji asks before he reads the whole chart — and the answer comes one of
 * two ways: the row they picked in the app's place search ("📍 Jagah chunein", sent beside the
 * message as `birth_place: {place_id, description}`), or the town typed as a reply. A picked row
 * is looked up by its id; typed words go through the same India-biased search the Kundali form
 * uses, and its top suggestion is taken. Either way it is saved only once it is located — a Google
 * place id, coordinates and a time zone — because words alone cast nothing, and the chat's small
 * kundli (`mini_kundli.ts`) needs all three.
 *
 * The rules are the hour's (`captureBirthDetails` in `astro-chat`):
 * - A place fills a blank. One already located — by the Kundali form, or here — is replaced only
 *   when they say it is wrong (`correctionIntent`), or when they answer again after this thread
 *   said one back to them. Otherwise coordinates on file are never overwritten, nor even looked up.
 *   Words on file that were never located (a town said once and promoted from the memory) are not
 *   a place yet: the ask names them (`describeSawal`), and the located answer replaces them, since
 *   the words saved must be the words the coordinates came from.
 * - Words that are plainly not a place are never searched for: a question, a "pata nahi", a yes,
 *   a date. A place with a question after it ("Jaipur. Aur naukri kab lagegi?") is the part before
 *   the question. Words that still find nothing are not saved, and the sawal asks once more, for
 *   the town and the state.
 * - What was found is said back — "Rampur, Uttar Pradesh — sahi hai na?", the reply's one question
 *   — so a wrong match is one "nahi" from being asked again. A "nahi" is only ever a no: it takes
 *   the place off the account again ([undoPlace]) and is never searched for. "Nahi abhi tak nahi",
 *   answering a question beside the check, once had "tak" found in Thailand and saved.
 * - Google failing never fails the turn: it is a place not found. Neither the words nor the place
 *   are ever logged.
 * - Nothing here reads or writes `kundalis`, and no re-cast follows (`kundali_recast.ts` is for a
 *   corrected date or hour): the Kundali screen keeps the place it was cast from until its own
 *   form changes it.
 *
 * The reading ([pickedPlace], [placeQuery], [deniesPlace]) is pure; [captureBirthPlace] does the
 * looking up, the saving and the undoing.
 */

import { isValidTimeZone } from "./birth_timezone.ts";
import { correctionIntent, parseDob, parseHour } from "./birth_details.ts";
import { asksSomething, isGreeting } from "./chat_sawal.ts";
import { topicsOf } from "./chat_topics.ts";
import { AppConfig, configFlag, configSetting } from "./config.ts";
import { serviceClient } from "./db.ts";
import {
  asUserRow,
  entitlementPayload,
  graceHoursFrom,
  USER_COLUMNS,
  UserRow,
} from "./entitlement.ts";
import {
  autocomplete,
  isSessionToken,
  placeDetails,
  PlacesError,
  placesApiKey,
  timeZoneAt,
} from "./google_places.ts";
import { planFor } from "./pricing.ts";

// ---------------------------------------------------------------- what they sent

/** A row picked in the chat's place search. */
export interface PickedPlace {
  placeId: string;

  /** "Jaipur, Rajasthan, India" — the row as the search showed it, which is what is saved. */
  description: string;

  /**
   * The search's session token, when the app sends it: the Details call then closes the same
   * billed session the typing opened. Optional — without it the lookup opens a session of its own.
   */
  sessionToken: string | null;
}

/** `users.birth_place`'s own limit. */
const MAX_LABEL_CHARS = 120;

/**
 * The `birth_place` object the app sends beside the words of a picked row, or null when there is
 * none or it is not one: an id shaped the way `place-search` accepts one, and its words.
 */
export function pickedPlace(raw: unknown): PickedPlace | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const { place_id, description, session_token } = raw as Record<string, unknown>;
  const placeId = typeof place_id === "string" ? place_id.trim() : "";
  if (!/^[A-Za-z0-9_-]{1,300}$/.test(placeId)) return null;
  const words = typeof description === "string" ? description.trim().replace(/\s+/g, " ") : "";
  return {
    placeId,
    description: words.slice(0, MAX_LABEL_CHARS),
    sessionToken: isSessionToken(session_token) ? session_token : null,
  };
}

/** Longer than this, a reply is a sentence about something, not the name of a town. */
const MAX_REPLY_CHARS = 80;

/** A place is a few words: "Sector 62, Noida, Uttar Pradesh" is five. */
const MAX_PLACE_WORDS = 6;

/** Not knowing, or not remembering. */
const DECLINE =
  /(?<![\p{L}\p{M}])(?:pata\s*(?:nahi|nahin|nhi|nai)|pta\s*(?:nahi|nhi)|(?:nahi|nhi)\s*pata|(?:yaad|yad|malum|maloom|maaloom)\s*(?:nahi|nahin|nhi)|don'?t\s*know|dont\s*know|do\s*not\s*know|no\s*idea|not\s*sure|idk)(?![\p{L}\p{M}])|पता\s*नहीं|नहीं\s*पता|याद\s*नहीं|मालूम\s*नहीं|ಗೊತ್ತಿಲ್ಲ|ನೆನಪಿಲ್ಲ|தெரியாது|நினைவில்லை|తెలియదు|గుర్తులేదు|അറിയില്ല|ഓർമ്മയില്ല/iu;

/**
 * The words around a place in a reply — "mera janm Jaipur mein hua tha", "born in Rampur, UP",
 * "नहीं, रामपुर वाला", "ನಾನು ಮೈಸೂರಿನಲ್ಲಿ ಹುಟ್ಟಿದೆ" — and a yes or a thanks with nothing else. What is
 * left is the search. Never a word that is part of a place's own name: not "nagar", not "pradesh",
 * not "pur" — and the few that can be ([PLACE_WORDS]) only when they stand apart from one.
 */
const FILLER = new Set([
  // Hinglish
  "mera", "meri", "mere", "main", "mai", "mein", "me", "maine", "mujhe", "hum", "humara", "hamara",
  "apna", "apni", "janm", "janam", "janma", "janmsthan", "sthan", "jagah", "jaga", "shehar",
  "shahar", "sheher", "kasba", "qasba", "gaon", "gav", "gaanv", "gaav", "jila", "zila", "tehsil",
  "hua", "hui", "huwa", "hue", "huyi", "tha", "thi", "the", "hai", "hain", "hu", "hoon", "ka",
  "ki", "ke", "ko", "se", "par", "pe", "paida", "ji", "wala", "wali", "wale", "vala", "vali",
  "ye", "yeh", "yah", "wo", "woh", "vo", "voh", "sahi", "galat", "galt", "nahi", "nahin", "nhi",
  "nai", "na", "haan", "han", "ha", "hn", "ok", "okay", "hi", "to", "toh", "bhi", "ek", "sa",
  "chhota", "chota", "paas", "abhi", "yahin", "yahan", "yaha", "wahi", "vahi", "jo", "bataya",
  "bata", "diya", "shukriya", "dhanyavad", "dhanyavaad", "dhanyawad", "asal", "actually",
  // English
  "my", "i", "am", "was", "were", "is", "born", "birth", "place", "city", "town", "village",
  "district", "state", "in", "at", "a", "of", "from", "near", "no", "not", "yes", "wrong",
  "correct", "right", "it", "its", "it's", "thanks", "thank", "you", "sir",
  // Hindi
  "मेरा", "मेरी", "मेरे", "मैं", "मै", "में", "मे", "मुझे", "हमारा", "जन्म", "जनम", "स्थान",
  "जगह", "शहर", "कस्बा", "कस्बे", "गाँव", "गांव", "जिला", "ज़िला", "हुआ", "हुई", "था", "थी",
  "थे", "है", "हैं", "हूँ", "हूं", "का", "की", "के", "को", "से", "पर", "पैदा", "जी", "वाला",
  "वाली", "वाले", "यह", "ये", "वो", "वह", "सही", "गलत", "ग़लत", "नहीं", "नही", "ना", "हाँ",
  "हां", "एक", "पास", "धन्यवाद", "शुक्रिया",
  // Kannada, Tamil, Telugu, Malayalam: "I", "my", "was born", "place", "town"
  "ನಾನು", "ನನ್ನ", "ನಮ್ಮ", "ಹುಟ್ಟಿದೆ", "ಹುಟ್ಟಿದ್ದು", "ಹುಟ್ಟಿದ್ದೇನೆ", "ಹುಟ್ಟಿದ", "ಜನ್ಮ", "ಸ್ಥಳ", "ಊರು",
  "ಹೌದು", "ಇಲ್ಲ",
  "நான்", "என்", "எங்க", "பிறந்தேன்", "பிறந்தது", "பிறந்த", "ஊர்", "இடம்", "ஆமாம்", "இல்லை",
  "నేను", "నా", "మా", "పుట్టాను", "పుట్టింది", "పుట్టిన", "ఊరు", "ప్రదేశం", "అవును", "కాదు",
  "ഞാൻ", "എന്റെ", "ഞങ്ങളുടെ", "ജനിച്ചു", "ജനിച്ചത്", "ജനിച്ച", "സ്ഥലം", "നാട്", "അതെ", "അല്ല",
]);

/**
 * Filler that is also part of some places' names: "Cape Town", "Kansas City", "Port of Spain",
 * "Model Town, Ludhiana". Dropped only standing apart — "born in the city of Mysore" — and kept
 * when it follows a word of the place, with no comma between.
 */
const PLACE_WORDS = new Set(["city", "town", "village", "district", "state", "of"]);

/**
 * "In", fused on in the southern scripts: ಮೈಸೂರಿನಲ್ಲಿ, சென்னையில், విజయవాడలో, കൊച്ചിയിൽ. Cut with
 * the vowel sign before it, so what is searched is the start of the town's own name — ಮೈಸೂರ for
 * ಮೈಸೂರು, மைசூர for மைசூர் — which the search completes.
 */
const LOCATIVE =
  /(?:ಯಲ್ಲಿ|\u0CBF?ನಲ್ಲಿ|ದಲ್ಲಿ|யில்|\u0BBFல்|\u200C?లో|\u0D2F?\u0D3F(?:ൽ|ല്\u200D?))$/u;

/** A word as [FILLER] spells it: lower case, without the punctuation around it. */
const bare = (word: string) =>
  word.toLowerCase().replace(/^[^\p{L}\p{M}\p{N}]+|[^\p{L}\p{M}\p{N}']+$/gu, "");

/**
 * A locality, which names a subject the chat reads more often than one would think: "Laxmi Nagar,
 * Delhi" is not about money, nor "Prem Nagar" about love, "Hospital Road" about health or "School
 * Road" about studies. Taken out before the subject check, never out of the search.
 */
const LOCALITY = new RegExp(
  "[\\p{L}\\p{M}]+\\s+(?:nagar|nagara|road|rd|marg|colony|vihar|enclave|chowk|bazaa?r|market|gali|" +
    "mohalla|puram|ganj|layout|street|lane|cross|sector|block|phase|extension|halli|palya|basti|" +
    "cantt|cantonment|नगर|रोड|मार्ग|कॉलोनी|कालोनी|विहार|चौक|बाजार|बाज़ार|गंज|गली|मोहल्ला|पुरम)" +
    "(?![\\p{L}\\p{M}])",
  "giu",
);

/** "Par", "aur", "but" at the start of what follows a place: "Jaipur mein, par shaadi kab hogi?" */
const CLAUSE = /\s*[,;.!?।॥]+\s*|\s+(?=(?:par|pr|lekin|magar|but|aur|and|or|ya|पर|लेकिन|मगर|और|या)\s)/iu;

/**
 * The place and what came with it: the part of the reply before a question or a subject, when a
 * question follows it — "Jaipur mein, par shaadi kab hogi?" is "Jaipur mein", which [placeQuery]
 * then reads — and whether one did. Null when the reply opens on the question: then it is a new
 * one, not the answer to the ask.
 */
function beforeTheQuestion(said: string): string | null {
  const place: string[] = [];
  for (const clause of said.split(CLAUSE)) {
    const words = clause.replace(/^(?:par|pr|lekin|magar|but|aur|and|or|ya|पर|लेकिन|मगर|और|या)\s+/iu, "");
    if (!words.trim()) continue;
    if (asksSomething(words) || topicsOf(words.replace(LOCALITY, " ")).size > 0) break;
    place.push(words.trim());
  }
  return place.length > 0 ? place.join(", ") : null;
}

/** A place read out of a reply: the words to search, and whether a question came after them. */
export interface PlaceAnswer {
  query: string;
  asks: boolean;
}

/**
 * What a reply to "Aap kis shehar mein paida hue the?" says as a search — the town, and the state
 * when they gave it, without the sentence around it — or null when it is plainly not a place: a
 * question and nothing before it, something about a subject the chat reads ("shaadi ki baat chal
 * rahi hai"), not knowing, a greeting, a date or a time, or nothing left once the filler is gone.
 * Nothing null is ever searched for.
 */
export function readPlace(message: string, now: Date): PlaceAnswer | null {
  const said = message.normalize("NFC")
    .replace(/[\p{Extended_Pictographic}\u{FE0F}\u{200D}]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (said.length < 2 || said.length > MAX_REPLY_CHARS) return null;
  if (DECLINE.test(said) || isGreeting(said)) return null;
  const asks = asksSomething(said);
  const place = asks ? beforeTheQuestion(said) : said;
  if (!place) return null;
  if (topicsOf(place.replace(LOCALITY, " ")).size > 0) return null;
  if (parseDob(place, now) || parseHour(place, now).time) return null;

  const raw = place.split(" ");
  const words = raw.flatMap((word, index) => {
    const core = bare(word);
    if (core === "") return [];
    if (FILLER.has(core)) {
      // "Cape Town", "Port of Spain": after a word of the place, with no comma between, it is its name.
      const before = index > 0 ? raw[index - 1] : "";
      const named = PLACE_WORDS.has(core) && before !== "" && !/[,;]$/.test(before) &&
        !FILLER.has(bare(before));
      if (!named) return [];
    }
    // The southern scripts' fused "in", off the end of the word — never down to nothing.
    const [, body, tail] = /^(.*?)([,;.]*)$/su.exec(word)!;
    const stem = body.replace(LOCATIVE, "");
    return [`${/(?:\p{L}\p{M}*){2,}/u.test(stem) ? stem : body}${tail}`];
  });
  const query = words.join(" ")
    .replace(/\s*,\s*/g, ", ")
    .replace(/(?:,\s*){2,}/g, ", ")
    .replace(/^[\s,.\-–—]+|[\s,.\-–—]+$/g, "");
  if (words.length === 0 || words.length > MAX_PLACE_WORDS) return null;
  // A town has a name of three letters or more; "UP" alone, or "ye", is not one.
  if (!/[\p{L}\p{M}]{3,}/u.test(query)) return null;
  return { query, asks };
}

/** [readPlace]'s search alone. */
export function placeQuery(message: string, now: Date): string | null {
  return readPlace(message, now)?.query ?? null;
}

/**
 * "Nahi", "galat", "ye wala nahi" — a reply that says the place just said back to them is wrong.
 * Only ever asked of the turn after one was saved: anywhere else "nahi" is just a no. The southern
 * scripts' no and wrong as whole words only: ಇಲ್ಲಿ is "here" and അല്ലെങ്കിൽ "or", and both were read
 * as a "nahi" to the place.
 */
const DENIAL = new RegExp(
  [
    "^(?:nahi|nahin|nhi|nai|na|no|nope|not|galat|galt|wrong|incorrect)(?![\\p{L}\\p{M}])",
    "^(?:नहीं|नही|ना)(?![\\p{L}\\p{M}])",
    "(?<![\\p{L}\\p{M}])(?:galat|galt|wrong|incorrect|sahi\\s*(?:nahi|nhi|nahin))(?![\\p{L}\\p{M}])",
    "गलत|ग़लत|सही\\s*नहीं",
    "(?<![\\p{L}\\p{M}])(?:ತಪ್ಪು|ಇಲ್ಲ|ಅಲ್ಲ|தவறு|இல்லை|தப்பு|తప్పు|కాదు|లేదు|തെറ്റ്|അല്ല|ഇല്ല)(?![\\p{L}\\p{M}])",
  ].join("|"),
  "iu",
);

export function deniesPlace(message: string): boolean {
  return DENIAL.test(message.normalize("NFC").trim());
}

/** Google's name for a place without its postal code: "Rampur, Uttar Pradesh 244901, India". */
function withoutPostcode(address: string): string {
  return address.replace(/\s*\b\d{5,6}\b/g, "").replace(/\s+,/g, ",").replace(/,\s*,/g, ",").trim();
}

/** "Jaipur, Rajasthan, India" as it is said back: without the country, when that is India. */
export function spokenPlace(label: string): string {
  return withoutPostcode(label).replace(/,\s*India\s*$/i, "").trim();
}

// ---------------------------------------------------------------- finding it

export interface LocatedPlace {
  placeId: string;
  /** As `users.birth_place` stores it: a picked row's words, or Google's name for a typed one. */
  label: string;
  lat: number;
  lng: number;
  timeZoneId: string;
}

/** Four places is about eleven metres, far finer than a lagna can tell apart — `place-search`'s. */
const round4 = (n: number) => Math.round(n * 10_000) / 10_000;

/**
 * The birth instant the zone is looked up at, as `place-search` does it: the date and hour when
 * they are known, noon when only the date is, now otherwise. The zone's id does not depend on it;
 * the lookup only needs a moment.
 */
function birthMoment(dob: string | null | undefined, time: string | null | undefined, now: Date): number {
  if (!dob || !/^\d{4}-\d{2}-\d{2}$/.test(dob)) return now.getTime();
  const clock = time && /^\d{2}:\d{2}/.test(time) ? time.slice(0, 5) : "12:00";
  const ms = Date.parse(`${dob}T${clock}:00Z`);
  return Number.isFinite(ms) ? ms : now.getTime();
}

/**
 * Where [answer] is: the picked row by its id, or the top suggestion for the typed words — then
 * its coordinates and its time zone. Null when nothing is found. Any other failure of Google's is
 * thrown as a `PlacesError`, for the caller to treat as nothing found.
 *
 * The typed search and its Details share one session token, as `place-search` bills them; a
 * picked row's Details uses the app's token when it sent one.
 */
export async function locatePlace(
  apiKey: string,
  answer: { picked: PickedPlace } | { query: string },
  { atMs }: { atMs: number },
): Promise<LocatedPlace | null> {
  const sessionToken = ("picked" in answer ? answer.picked.sessionToken : null) ?? crypto.randomUUID();

  // A picked row is saved in the words it was shown in, as the Kundali form saves one. Typed words
  // are saved as Google names the place it found — never a suggestion they did not see, whose
  // words can be their own back ("Rampur, UP"), which would not show them which Rampur it was.
  let placeId: string;
  let shown = "";
  let suggested = "";
  if ("picked" in answer) {
    placeId = answer.picked.placeId;
    shown = answer.picked.description;
  } else {
    const [top] = await autocomplete(apiKey, { input: answer.query, sessionToken });
    if (!top) return null;
    placeId = top.place_id;
    suggested = top.secondary ? `${top.primary}, ${top.secondary}` : top.primary;
  }

  try {
    const place = await placeDetails(apiKey, { placeId, sessionToken });
    const timeZoneId = await timeZoneAt(apiKey, { lat: place.lat, lng: place.lng, atMs });
    if (!isValidTimeZone(timeZoneId)) return null;
    return {
      placeId: place.place_id,
      label: (shown || withoutPostcode(place.formatted_address) || suggested).slice(0, MAX_LABEL_CHARS),
      lat: round4(place.lat),
      lng: round4(place.lng),
      timeZoneId,
    };
  } catch (error) {
    if (error instanceof PlacesError && error.kind === "not_found") return null;
    throw error;
  }
}

/**
 * How long the whole lookup may hold the turn up. Three calls of about 150 ms each, normally;
 * `google_places.ts` gives each one eight seconds, which three in a row would spend most of the
 * turn on. Past this it is a place not found, and the sawal asks again.
 */
const LOOKUP_BUDGET_MS = 5_000;

function withinBudget<T>(work: Promise<T>, ms: number): Promise<T | null> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<null>((resolve) => {
    timer = setTimeout(() => resolve(null), ms);
  });
  return Promise.race([work, late]).finally(() => clearTimeout(timer));
}

// ---------------------------------------------------------------- saving it

/** One stored turn, as the history query reads it. */
type Row = { role: string; body?: Record<string, unknown> | null };

export interface PlaceCapture {
  captured?: { field: "birth_place"; said: string; question: string | null };

  /** Asked for, and what they wrote could not be found — nothing is saved. */
  failed?: "birth_place";

  /**
   * The place this thread just said back was called wrong: it is off the account again
   * ([undoPlace]), and the sawal asks for the right one.
   */
  denied?: boolean;

  /** What it was and what it is now, as the reply stores it. */
  saved?: { field: "birth_place"; from: string | null; to: string };

  /** The refreshed account, for the app to install the way Profile does. */
  user?: Record<string, unknown>;
}

/**
 * The last question they asked before the birth details were asked for — the one the reply to a
 * detail still owes an answer to. Their replies to an ask ("subah 7 baje") are skipped; [rows]
 * are newest first, so the reply a user turn answered is the astro turn after it in the list.
 */
export function questionBefore(rows: readonly Row[]): string | null {
  for (let i = 0; i < rows.length; i++) {
    if (rows[i].role !== "user") continue;
    const said = String(rows[i].body?.text ?? "").trim();
    const answered = rows.slice(i + 1).find((row) => row.role === "astro")?.body?.ask_for;
    const answering = answered === "dob" || answered === "birth_time" || answered === "birth_place";
    if (said && !answering && !isGreeting(said)) return said;
  }
  return null;
}

/**
 * Whether [message] answers the place ask — the row picked in the search, or words typed after the
 * reply asked for it — and asks nothing of its own. Its words then say nothing about what the turn
 * is about: "Laxmi Nagar, Delhi" turned a shaadi thread's upay into one for money, and "Hospital
 * Road, Jaipur" into one for health (`turnTopic` in `chat_upay.ts`).
 */
export function answersPlaceAsk(rows: readonly Row[], sent: unknown, message: string): boolean {
  const lastAstro = rows.find((row) => row.role === "astro")?.body;
  return (lastAstro?.ask_for === "birth_place" || pickedPlace(sent) !== null) && !asksSomething(message);
}

/** Whether the dashboard has switched place search off — the switch that stops Places spending. */
function searchOff(config: AppConfig): boolean {
  return Boolean(configSetting(config, "place_search_enabled")) &&
    !configFlag(config, "place_search_enabled");
}

/**
 * The place this thread saved and said back, taken off the account after their "nahi": the words
 * it replaced go back (`saved.from`, which the reply stores so it can be undone), and its id,
 * coordinates and zone go. Left on, the small kundli went on being cast from a place they had
 * called wrong — that turn, and every turn after a second "nahi" had used up the re-asks — and
 * the Kundali form would have found it. Only while the account still holds that place: one saved
 * since, by the Kundali form, is not the chat's to take back.
 */
async function undoPlace(
  db: ReturnType<typeof serviceClient>,
  config: AppConfig,
  user: UserRow,
  saved: { from?: unknown; to?: unknown } | undefined,
): Promise<PlaceCapture> {
  if (!saved || user.birth_place !== saved.to) return { denied: true };
  const update = {
    birth_place: typeof saved.from === "string" && saved.from.trim() ? saved.from : null,
    birth_place_id: null,
    birth_lat: null,
    birth_lng: null,
    birth_tz: null,
    birth_coords_at: null,
  };
  const { data: row, error } = await db.from("users").update(update).eq("user_id", user.user_id)
    .select(USER_COLUMNS).single();
  if (error || !row) {
    console.error(`astro-chat: could not take back the birth place (${error?.code ?? "no row"})`);
    return { denied: true };
  }
  const { birth_coords_at: _at, ...onUser } = update;
  Object.assign(user, onUser);
  console.log("astro-chat: birth place taken back after a no");

  const refreshed = asUserRow(row);
  return {
    denied: true,
    user: entitlementPayload(refreshed, graceHoursFrom(config), planFor(config, refreshed.plan_variant)),
  };
}

/**
 * Reads a birth place out of this turn, finds it, and saves it — or, after a "nahi" to the one
 * just said back, takes it off again. See the file header for the rules. Null when there is
 * nothing to do: no place asked for or picked, one already located and nothing said against it,
 * a reply that is not a place at all, or search switched off.
 *
 * Mutates [user] so everything after this in the turn — the small kundli, THE KUNDALI LINE's
 * "sthan", the sawal — works from what was just saved. Never throws.
 */
export async function captureBirthPlace(
  db: ReturnType<typeof serviceClient>,
  config: AppConfig,
  user: UserRow,
  rows: readonly Row[],
  message: string,
  sent: unknown,
  now: Date,
): Promise<PlaceCapture | null> {
  try {
    const lastAstro = rows.find((row) => row.role === "astro")?.body ?? null;
    const picked = pickedPlace(sent);
    const asked = lastAstro?.ask_for === "birth_place";
    const saidBack = (lastAstro?.saved as { field?: unknown } | undefined)?.field === "birth_place";
    // A no to the place said back is a no, and nothing else: whatever else it says is never
    // searched for. The sawal asks for the right place (`chat_sawal.ts`), and that answer is read.
    if (saidBack && !picked && deniesPlace(message)) {
      return await undoPlace(db, config, user, lastAstro?.saved as { from?: unknown; to?: unknown });
    }
    if (!picked && !asked) return null;
    if (searchOff(config)) return null;

    // A place this thread saved, asked for again: they said it was wrong (`chat_sawal.ts`).
    const savedHere = rows.some((row) =>
      row.role === "astro" && (row.body?.saved as { field?: unknown } | undefined)?.field === "birth_place"
    );
    const recent = rows.filter((row) => row.role === "user").slice(0, 2)
      .map((row) => String(row.body?.text ?? ""));
    const intent = correctionIntent(message) || recent.some(correctionIntent) || (asked && savedHere);
    const located = (user.birth_lat != null && user.birth_lng != null) || Boolean(user.birth_place_id);
    if (located && !intent) return null;

    const answer = picked ? null : readPlace(message, now);
    if (!picked && !answer) return null;
    const query = answer?.query ?? null;

    const apiKey = placesApiKey(config);
    if (!apiKey) {
      console.error("astro-chat: no google_places_api_key; a birth place was not looked up");
      return null;
    }

    let found: LocatedPlace | null = null;
    try {
      found = await withinBudget(
        locatePlace(apiKey, picked ? { picked } : { query: query! }, {
          atMs: birthMoment(user.dob, user.birth_time, now),
        }),
        LOOKUP_BUDGET_MS,
      );
    } catch (error) {
      // The kind only: a Places error's detail can carry the words that were searched for.
      console.error(
        `astro-chat: birth place lookup failed: ${error instanceof PlacesError ? error.kind : "error"}`,
      );
    }
    if (!found) return { failed: "birth_place" };

    const update = {
      birth_place: found.label,
      birth_place_id: found.placeId,
      birth_lat: found.lat,
      birth_lng: found.lng,
      birth_tz: found.timeZoneId,
      // When they were fetched, so `purge_expired` clears them after Google's thirty days, as it
      // does the Kundali form's.
      birth_coords_at: now.toISOString(),
    };
    const { data: row, error } = await db.from("users").update(update).eq("user_id", user.user_id)
      .select(USER_COLUMNS).single();
    if (error || !row) {
      // The code only: a failed write's details can quote the row, and the row is the place.
      console.error(`astro-chat: could not save the birth place (${error?.code ?? "no row"})`);
      return null;
    }

    const from = user.birth_place ?? null;
    const { birth_coords_at: _at, ...onUser } = update;
    Object.assign(user, onUser);
    console.log(`astro-chat: birth place saved from the chat (${picked ? "picked" : "typed"})`);

    const refreshed = asUserRow(row);
    return {
      // With a question of its own after the place, that is what this reply answers.
      captured: {
        field: "birth_place",
        said: spokenPlace(found.label),
        question: answer?.asks ? null : questionBefore(rows),
      },
      saved: { field: "birth_place", from, to: found.label },
      user: entitlementPayload(refreshed, graceHoursFrom(config), planFor(config, refreshed.plan_variant)),
    };
  } catch (error) {
    console.error(`astro-chat: birth place capture failed (${error instanceof Error ? error.name : "error"})`);
    return null;
  }
}
