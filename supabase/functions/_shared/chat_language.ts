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
 * The last paragraph is the rule that matters most in practice. People switch languages
 * mid-conversation without changing any setting, and a reply that comes back in the wrong one
 * reads as a bug rather than as an honoured preference.
 */
export function languageBlock(name: string): string {
  return `
THE LANGUAGE YOU WRITE IN.

Write every field of your reply in ${name} — the verdict, the title, the opening, every section
heading and body, and every option. Not a mixture of two languages, and never a translation
appended after. The person reads one language; give them that one.

${languageInstruction(name)}

If their message is written in a different language from the one above, answer in the language
they wrote in. The person in front of you outranks the setting: someone who types in English
gets English back, whatever they chose in the app, and someone who types in Hinglish gets
Hinglish.
`.trim();
}
