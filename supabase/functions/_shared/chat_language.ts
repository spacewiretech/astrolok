/**
 * Which language Astro answers in, and how the sage is told to write it.
 *
 * The list lives in `app_config` rather than in this file so a language can be added from the
 * Supabase dashboard without a deploy — the same reason `gemini_model` lives there. That only
 * works if an unrecognised name still produces a usable instruction, hence the generic template
 * at the bottom of [languageInstruction]: the dashboard is the source of truth, and this module
 * is what makes trusting it safe.
 *
 * Chat only. Palm and face still write in Roman letters, because their PDF export and read-aloud
 * voice cannot render anything else — see `PANDIT_VOICE` in `pandit.ts`.
 */

import { AppConfig, configSetting } from "./config.ts";

/** The key holding the comma-separated list of language names. Public: the picker reads it. */
export const LANGUAGES_KEY = "chat_languages";

/** The key naming which of them a user who has never chosen gets. Public, for the same reason. */
export const DEFAULT_LANGUAGE_KEY = "chat_language_default";

/**
 * What ships if the rows are missing entirely.
 *
 * Not an empty list: an unconfigured project must still answer someone, and answering in the
 * language the app was built for beats answering in whatever the model felt like.
 */
export const BUILT_IN_LANGUAGES = ["Hinglish", "English", "Hindi"] as const;

/** A name long enough to be real and short enough not to be a paragraph smuggled into a cell. */
const MAX_NAME_LENGTH = 40;

/**
 * The supported languages, in the order the dashboard lists them.
 *
 * Trimmed, de-duplicated case-insensitively, and capped — a dashboard cell is a text box, and
 * this string ends up inside a model prompt.
 */
export function supportedLanguages(config: AppConfig): string[] {
  const raw = configSetting(config, LANGUAGES_KEY);
  if (!raw) return [...BUILT_IN_LANGUAGES];

  const seen = new Set<string>();
  const languages: string[] = [];

  for (const entry of raw.split(",")) {
    const name = entry.trim();
    if (!name || name.length > MAX_NAME_LENGTH) continue;

    const key = name.toLowerCase();
    if (seen.has(key)) continue;

    seen.add(key);
    languages.push(name);
  }

  return languages.length > 0 ? languages : [...BUILT_IN_LANGUAGES];
}

/** True when [name] is one the dashboard currently offers. Case-insensitive; used to validate. */
export function isSupported(name: string, config: AppConfig): boolean {
  const wanted = name.trim().toLowerCase();
  return supportedLanguages(config).some((entry) => entry.toLowerCase() === wanted);
}

/**
 * The language this turn is written in.
 *
 * [stored] is `users.language`, which is null for anyone who has never chosen. A stored value
 * that has since been removed from the dashboard falls back to the default rather than being
 * honoured — otherwise retiring a language would leave its last users talking to a prompt that
 * names a language nobody supports any more.
 */
export function resolveLanguage(stored: string | null | undefined, config: AppConfig): string {
  const languages = supportedLanguages(config);

  const match = (name: string | null | undefined) => {
    const wanted = (name ?? "").trim().toLowerCase();
    return wanted ? languages.find((entry) => entry.toLowerCase() === wanted) : undefined;
  };

  return match(stored) ??
    match(configSetting(config, DEFAULT_LANGUAGE_KEY)) ??
    languages[0];
}

/**
 * How to write each language, in the sage's own terms.
 *
 * Written per language rather than as one "reply in X" line because the three differ in ways a
 * generic instruction gets wrong: Hinglish is a script choice as much as a language, English
 * needs the Sanskrit glossed, and Hindi has to be told to stay spoken rather than drifting into
 * literary register.
 */
const INSTRUCTIONS: Record<string, string> = {
  hinglish:
    "Hinglish means Hindi as it is actually typed on a phone: Hindi words in Roman letters, " +
    "with the English words people genuinely use left in English. " +
    '"Aapka Chandra Mesha rashi mein hai, aur yeh sahas deta hai." ' +
    "Never Devanagari, and never formal Hindi transliterated word for word — write it the way " +
    "they wrote to you.",

  english:
    "English means plain, warm Indian English. Keep the Sanskrit terms — Chandra, rashi, " +
    "nakshatra — in transliteration, glossed once where they first appear: " +
    '"your Chandra — the Moon — sits in Mesha, the Ram."',

  hindi:
    "Hindi means Hindi written in Devanagari, as Hindi is written. " +
    '"आपका चंद्र मेष राशि में है, और यह साहस देता है।" ' +
    "Keep it spoken Hindi, the way an elder actually talks — not literary or heavily " +
    "Sanskritised Hindi, which reads as a textbook rather than as someone sitting with them.",
};

/** The line describing how to write [name]. Unknown names get a template, so config can lead. */
export function languageInstruction(name: string): string {
  return INSTRUCTIONS[name.trim().toLowerCase()] ??
    `Write your whole reply in ${name}, in the script ${name} is normally written in, in the ` +
      `register an elder would actually speak it — not a formal or literary version of it.`;
}

/**
 * The block that goes into the system prompt.
 *
 * Placed early, before the craft, because it governs every field rather than any one of them —
 * a model told the language last has already begun composing in another.
 *
 * The last paragraphs are the rules that matter most in practice. People switch languages
 * mid-conversation without changing any setting, and a reply that comes back in the wrong one
 * reads as a bug rather than as an honoured preference.
 *
 * [conversation] is the chat. A reading has no earlier replies to be misled by, and no message
 * typed on a keyboard, so palm and face keep the block exactly as it shipped.
 */
export function languageBlock(name: string, { conversation = false } = {}): string {
  const head = `
THE LANGUAGE YOU WRITE IN.

Write every field of your reply in ${name} — the verdict, the title, the opening, every section
heading and body, and every option. Not a mixture of two languages, and never a translation
appended after. The person reads one language; give them that one.

${languageInstruction(name)}
`.trim();

  if (!conversation) {
    return `${head}

If their message is written in a different language from the one above, answer in the language
they wrote in. The person in front of you outranks the setting: someone who types in English
gets English back, whatever they chose in the app, and someone who types in Hinglish gets
Hinglish.`;
  }

  return `${head}

${followingThePerson(name)}

Earlier replies in this conversation may be in a different language. That is not a precedent to
follow: this reply is written in the language set out here, whatever came before it.`;
}

/**
 * The switching rule for a conversation.
 *
 * Written apart from the reading's version because of one real exchange. Someone whose setting
 * was Hinglish typed "Hindi me bat kre" — in Roman letters — and "someone who types in Hinglish
 * gets Hinglish" told the sage to ignore the very thing they had asked for, three turns running.
 * An explicit request now comes first, and when the setting is Hindi, Hindi typed in Roman letters
 * is named for what it is: how a phone keyboard makes people write it.
 */
function followingThePerson(name: string): string {
  const request =
    "If they ask you to write in another language, do it, from this reply on. If their " +
    "message is written wholly in a different language from the one above, answer in the " +
    "language they wrote in: the person in front of you outranks the setting.";

  if (name.trim().toLowerCase() === "hindi") {
    return `${request} Hindi typed in Roman letters is not a different language, though. It is ` +
      "how most people type Hindi on a phone — a keyboard habit, not a request for Hinglish — " +
      "and it still gets Devanagari back.";
  }

  return `${request} Someone who types in English gets English back, whatever they chose in the ` +
    "app, and someone who types in Hinglish gets Hinglish.";
}

// ---------------------------------------------------------------- noticing a switch

/**
 * The script Hindi is written in. Marathi and Nepali share it, which is why a message in it only
 * resolves to Hindi when Hindi is on the dashboard's list.
 */
const DEVANAGARI = /[ऀ-ॿ]/g;
const LATIN = /[a-z]/gi;

/** Below this, a stray word or an emoji-adjacent sign is not a message written in the script. */
const MIN_SCRIPT_CHARS = 2;

/** What each language is called, the ways somebody asking for it types the name. */
const LANGUAGE_NAMES: Record<string, readonly string[]> = {
  hindi: ["hindi", "हिंदी", "हिन्दी"],
  english: ["english", "angrezi", "angreji", "अंग्रेज़ी", "अंग्रेजी", "इंग्लिश"],
  hinglish: ["hinglish", "हिंग्लिश"],
};

/** "In", as it follows a language's name: "Hindi me", "हिंदी में". */
const POSTPOSITION = "me|mein|mai|mei|main|men|में|मे|मैं";

/** Words that may stand around the name in a message that is nothing but the request. */
const FILLER = "sirf|only|keval|please|plz|pls|ji|सिर्फ़|सिर्फ|केवल|जी";

/**
 * Words that make "Hindi me" a request about this conversation rather than a mention of a subject.
 * "Mera Hindi me result kharab aaya" names the language and asks for nothing.
 */
const SPEAKING = new RegExp(
  "(?<![a-z])(?:bat|baat|bol|bata|btao|btaye|likh|reply|jawab|jwab|answer|samjha|talk|speak|" +
    "write|respond|kaho|kahiye|chat)|बात|बोल|बता|लिख|जवाब|उत्तर|समझा|कहि|कहें|रिप्लाई",
  "iu",
);

const POLITE = /(?<![a-z])(?:please|plz|pls)(?![a-z])/i;

/** A request refused in the same breath is not one: "Hindi me mat bolo". */
const NEGATION = /(?<![a-z])(?:mat|mt|nahi|nahin|nhi|dont|don't|not)(?![a-z])|(?<![\p{L}\p{M}])(?:मत|नहीं|नही)(?![\p{L}\p{M}])/iu;

/** A request made in a message this short needs no verb around it: "Hindi me", "in English". */
const SHORT_WORDS = 4;

/** A pattern that matches only whole words, in any script. */
function whole(alternatives: string): string {
  return `(?<![\\p{L}\\p{M}])(?:${alternatives})(?![\\p{L}\\p{M}])`;
}

/** What one message says about the language the reply should be in. */
export interface LanguageSwitch {
  /** Spelled as the dashboard's list spells it. */
  language: string;

  /** True when they asked in words; false when the script they typed in decided it. */
  explicit: boolean;
}

/**
 * The language this message moves the conversation into, or null when it moves nothing.
 *
 * Decided in code, before the model is called, because leaving it to the prompt did not work. A
 * user writing Devanagari to an account set to Hinglish got Hinglish back for three turns: the
 * setting, and a conversation's worth of Roman-letter replies behind it, outweighed one sentence
 * in the system prompt.
 *
 * Two signals, in order:
 *
 * - **An explicit request** — "Hindi me bat kre", "हिंदी में बताएं", "in English please", or a
 *   message that is nothing but the name. "Hindi me" only counts inside a short message or next
 *   to a verb of speaking, so a sentence about a Hindi exam does not change anyone's language.
 * - **The script.** A message mostly in Devanagari is Hindi. Roman letters decide nothing, because
 *   English and Hinglish share them — that case stays with the prompt.
 *
 * A language the dashboard does not offer is never returned, so a switch cannot name something
 * `resolveLanguage` would refuse.
 */
export function detectLanguageSwitch(message: string, config: AppConfig): LanguageSwitch | null {
  const text = message.trim().toLowerCase();
  if (!text) return null;

  const languages = supportedLanguages(config);
  const spelled = (key: string) => languages.find((entry) => entry.toLowerCase() === key);

  const asked = requestedLanguage(text);
  const named = asked ? spelled(asked) : undefined;
  if (named) return { language: named, explicit: true };

  const devanagari = text.match(DEVANAGARI)?.length ?? 0;
  const latin = text.match(LATIN)?.length ?? 0;
  if (devanagari >= MIN_SCRIPT_CHARS && devanagari >= latin) {
    const hindi = spelled("hindi");
    if (hindi) return { language: hindi, explicit: false };
  }

  return null;
}

/** The key of the language [text] asks for, or null. When it names two, the later one wins. */
function requestedLanguage(text: string): string | null {
  if (NEGATION.test(text)) return null;

  const short = text.split(/\s+/).filter((word) => word).length <= SHORT_WORDS;
  const meant = short || SPEAKING.test(text) || POLITE.test(text);

  let found: { key: string; at: number } | null = null;

  for (const [key, names] of Object.entries(LANGUAGE_NAMES)) {
    const name = whole(names.join("|"));

    // Nothing but the name, give or take "please" and "sirf": "हिन्दी", "English please".
    const bare = new RegExp(
      `^(?:${whole(FILLER)}\\s*)*${name}(?:\\s*${whole(`${FILLER}|${POSTPOSITION}`)})*[\\s.!?।]*$`,
      "u",
    );
    if (bare.test(text)) return key;

    if (!meant) continue;

    const phrase = new RegExp(`${name}\\s*${whole(POSTPOSITION)}|${whole("in")}\\s+${name}`, "u")
      .exec(text);
    if (phrase && (found === null || phrase.index > found.at)) {
      found = { key, at: phrase.index };
    }
  }

  return found?.key ?? null;
}
