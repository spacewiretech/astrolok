/**
 * What to ask the model about a palm, and how to make sense of what comes back.
 *
 * Split out of `gemini.ts` when face reading arrived: that file is now the transport, `pandit.ts`
 * is the voice, and this is the palm's own schema, prompt and normaliser. [normalisePalmReading]
 * is pure and exported so the whole of it is testable with no network and no key.
 */

import {
  ceremony,
  FOCUS_LABELS,
  FocusKey,
  STATUSES,
  text,
} from "./gemini.ts";
import { panditSystemPrompt, panditVoice, SHARED_LENGTHS } from "./pandit.ts";

export { FOCUS_KEYS, FOCUS_LABELS, focusMismatch, parseFocus } from "./gemini.ts";
export type { FocusKey } from "./gemini.ts";

/** The eight lines, in the order the results screen shows them: the four best-known first. */
export const LINE_KEYS = [
  "heart",
  "life",
  "head",
  "fate",
  "sun",
  "mercury",
  "marriage",
  "mars",
] as const;

export type LineKey = typeof LINE_KEYS[number];

/**
 * Fallback titles, used when the model omits one.
 *
 * Note "Mercury Line", not "Health Line". The Mercury line is traditionally read as
 * communication, wit and everyday vitality; calling it the health line steers the model
 * straight at the medical claims the prompt forbids, and puts a health claim in an app store
 * listing. The reading talks about how someone expresses themselves, never about their body.
 */
export const LINE_TITLES: Record<LineKey, string> = {
  heart: "Heart Line",
  life: "Life Line",
  head: "Head Line",
  fate: "Fate Line",
  sun: "Sun Line",
  mercury: "Mercury Line",
  marriage: "Relationship Line",
  mars: "Mars Line",
};

export const REJECT_REASONS = [
  "none",
  "no_hand",
  "not_a_palm",
  "too_dark",
  "too_blurry",
  "too_far",
  "obstructed",
] as const;

/**
 * The response contract.
 *
 * Two things in here are load-bearing and should not be casually reordered:
 *
 * `propertyOrdering` puts `is_palm` and `hand` before everything else. Structured output is
 * generated in order, so the model states what it can actually see *before* it writes prose
 * that has to cite those observations. Reversed, the observations become a post-hoc
 * rationalisation of a reading already written, and the reading comes out generic. That
 * ordering is most of what makes the output feel like it is about this person's hand.
 *
 * `invocation` sits after `hand` and before `headline` for the same reason: an opening written
 * after the model has looked properly is an opening about this hand.
 *
 * Only `is_palm` and `reject_reason` are required at the top level, so a rejection can be two
 * fields and nothing else — a ~2s round trip instead of twenty seconds spent generating a
 * reading that is then thrown away.
 */
export const PALM_SCHEMA = {
  type: "OBJECT",
  propertyOrdering: [
    "is_palm",
    "reject_reason",
    "hand",
    "focus_echo",
    "invocation",
    "headline",
    "strongest_trait",
    "lines",
    "blessing",
  ],
  required: ["is_palm", "reject_reason"],
  properties: {
    is_palm: { type: "BOOLEAN" },
    reject_reason: { type: "STRING", enum: [...REJECT_REASONS] },

    hand: {
      type: "OBJECT",
      propertyOrdering: [
        "which_hand",
        "skin_texture",
        "firmness",
        "palm_shape",
        "finger_length",
        "visible_marks",
        "observations",
      ],
      properties: {
        which_hand: { type: "STRING", enum: ["left", "right", "unclear"] },
        skin_texture: { type: "STRING", enum: ["smooth", "medium", "coarse"] },
        firmness: { type: "STRING", enum: ["soft", "medium", "firm"] },
        palm_shape: { type: "STRING", enum: ["square", "rectangular", "broad", "narrow"] },
        finger_length: { type: "STRING", enum: ["short", "medium", "long"] },
        visible_marks: {
          type: "STRING",
          enum: ["none", "calluses", "minor_marks", "unclear"],
        },
        // Plain factual sentences about what is visible. Every `detail` below has to draw on
        // these, which is why they are generated first.
        observations: {
          type: "ARRAY",
          minItems: 2,
          maxItems: 4,
          items: { type: "STRING" },
        },
      },
    },

    // Exists only so the normaliser can check the model registered the focus the user picked.
    // On a mismatch the server's own value wins and the disagreement is logged.
    focus_echo: { type: "STRING", enum: ["love", "career", "money", "personality", "life_path"] },

    invocation: { type: "STRING" },
    headline: { type: "STRING" },

    strongest_trait: {
      type: "OBJECT",
      propertyOrdering: ["title", "summary", "detail"],
      properties: {
        title: { type: "STRING" },
        summary: { type: "STRING" },
        detail: { type: "STRING" },
      },
    },

    lines: {
      type: "ARRAY",
      minItems: 8,
      maxItems: 8,
      items: {
        type: "OBJECT",
        propertyOrdering: [
          "key",
          "title",
          "sanskrit",
          "status",
          "summary",
          "detail",
          "meaning",
          "tip",
          "blessing",
        ],
        required: ["key", "title", "status", "summary", "detail"],
        properties: {
          key: { type: "STRING", enum: [...LINE_KEYS] },
          title: { type: "STRING" },
          // The tradition's name for this line, transliterated. Rendered once, beside the
          // title, then never again in that section — see PANDIT_VOICE.
          sanskrit: { type: "STRING" },
          status: { type: "STRING", enum: [...STATUSES] },
          summary: { type: "STRING" },
          detail: { type: "STRING" },
          meaning: {
            type: "ARRAY",
            minItems: 3,
            maxItems: 3,
            items: { type: "STRING" },
          },
          tip: { type: "STRING" },
          blessing: { type: "STRING" },
        },
      },
    },

    blessing: { type: "STRING" },
  },
};

/** Palm-specific craft notes, slotted into the shared pandit prompt. */
const PALM_CRAFT = `
WHAT A HAND TELLS YOU.

Work from the texture of the skin, how soft or firm the hand looks, the shape of the palm, the
length of the fingers against the palm, and any calluses or marks. A soft, smooth, unmarked hand
suggests a life spent away from heavy physical work; a firm hand with calluses and thick skin
suggests someone physically active and hands-on. Say so, warmly and without judgement — both are
good hands to have, and neither is a comment on the person's standing.

For example: "Your palm is broad and the skin is smooth and unmarked — hands like this usually
belong to people who work with ideas rather than with tools, and your head line agrees with that."

The Life line is about vitality, resilience and stamina — NEVER about how long someone will live,
never about death, never about a lifespan. The Mercury line is about communication, wit and
everyday energy — never about the body or medicine.
`.trim();

const PALM_LENGTHS = [
  "LENGTH — write to these budgets and do not pad.",
  "",
  SHARED_LENGTHS,
  "- strongest_trait.title: 2-4 words. summary: at most 20 words. detail: 40-60 words.",
  "- Each line summary: at most 12 words. Each line detail: 45-70 words.",
  '- Each "meaning" bullet: 10-18 words. Each tip: at most 25 words.',
  "- Each line blessing: at most 18 words.",
  "- sanskrit: one or two words, transliterated, no gloss (the app writes the gloss).",
].join("\n");

/** The prompt as it was before readings could be written in anything but English. */
export const SYSTEM_PROMPT = palmSystemPrompt();

/**
 * The palm prompt, written to answer in [language].
 *
 * A function for the same reason the chat's is: the reply's language is a per-user setting now,
 * so the prompt cannot be a module constant. No language keeps [PANDIT_VOICE] exactly as it was,
 * which is what `SYSTEM_PROMPT` above still is.
 */
export function palmSystemPrompt(language?: string | null): string {
  return panditSystemPrompt({
    craft: PALM_CRAFT,
    lengths: PALM_LENGTHS,
    voice: panditVoice(language),
  });
}

/**
 * When to refuse, stated as narrowly as possible.
 *
 * An early version said only "if this is not clearly an open palm, reject". That turned out to
 * reject real palms: the same photograph came back readable on one call and "obstructed" on
 * the next, because a second hand was visible behind the first. A false rejection is much the
 * worse error here — the user is sent back to retake a photograph that was fine, having
 * already waited, on a feature they pay for — so the bar for refusing is set high and the
 * things that are *not* reasons to refuse are listed explicitly.
 */
const REJECTION_POLICY = [
  "Refuse only when you genuinely cannot read a palm: there is no hand in the image at all, " +
  "the back of the hand is facing the camera instead of the palm, the image is too dark or " +
  "too blurred to make out any creases, or the palm surface itself is covered by a glove or " +
  "an object.",
  "",
  "These are NOT reasons to refuse. Read the palm as normal in every one of these cases:",
  "- More than one hand is visible. Read the clearest, most fully visible palm.",
  "- Fingers or the wrist are cropped by the edge of the frame.",
  "- There are objects, patterns or other people in the background.",
  "- The hand wears rings, bangles, mehndi, nail polish, or has scars or marks.",
  "- The lighting is uneven, or part of the palm is in shadow.",
  "",
  "If you are in any doubt, proceed with the reading rather than refusing. When you do " +
  "refuse, return only is_palm: false with the matching reject_reason and stop.",
].join("\n");

export function buildUserPrompt(
  { name, age, focus }: { name?: string | null; age?: number | null; focus: FocusKey },
): string {
  const who = name?.trim()
    ? `This reading is for ${name.trim()}${age ? `, who is ${age}` : ""}.`
    : "You do not know this person's name; do not invent one or address them by name.";

  return [
    REJECTION_POLICY,
    "",
    who,
    `Their chosen focus is "${FOCUS_LABELS[focus]}". The strongest_trait and at least three ` +
    "of the eight line details must speak to that focus directly.",
    "",
    "Read all eight lines: heart, life, head, fate, sun, mercury, marriage and mars. Give " +
    "every one of them its traditional name, a status, a short summary, a detailed paragraph " +
    "grounded in what you can see of the hand, three specific bullets under meaning, one tip, " +
    "and one short blessing.",
  ].join("\n");
}

// ---------------------------------------------------------------- normalising

export interface NormalisedLine {
  key: LineKey;
  title: string;
  sanskrit: string;
  status: string;
  summary: string;
  detail: string;
  meaning: string[];
  tip: string;
  blessing: string;
}

export interface NormalisedReading {
  rejected: string | null;
  focus: FocusKey;
  invocation: string;
  headline: string;
  strongestTrait: { title: string; summary: string; detail: string };
  hand: Record<string, unknown>;
  lines: NormalisedLine[];
  blessing: string;
}

/**
 * Turns whatever the model returned into something the app can render, or says it cannot.
 *
 * Never throws on a merely imperfect payload — a reading missing one bullet is still a good
 * reading, and after a twenty-second wait the user is far better served by seven solid lines
 * than by an error. It gives up only when there is too little left to be worth showing.
 *
 * Pure and exported so the whole of this can be tested without a network or a key.
 */
export function normalisePalmReading(
  raw: unknown,
  focus: FocusKey,
): NormalisedReading {
  const root = (raw ?? {}) as Record<string, unknown>;

  const reject = () => ({
    rejected: REJECT_REASONS.includes(root.reject_reason as typeof REJECT_REASONS[number])
      ? String(root.reject_reason)
      : "not_a_palm",
    focus,
    invocation: "",
    headline: "",
    strongestTrait: { title: "", summary: "", detail: "" },
    hand: {},
    lines: [],
    blessing: "",
  });

  if (root.is_palm !== true) return reject();
  // "is_palm: true" alongside a real rejection reason is a contradiction; trust the reason.
  if (root.reject_reason && root.reject_reason !== "none") return reject();

  const seen = new Set<string>();
  const byKey = new Map<LineKey, NormalisedLine>();

  for (const entry of Array.isArray(root.lines) ? root.lines : []) {
    const line = (entry ?? {}) as Record<string, unknown>;
    const key = String(line.key ?? "") as LineKey;

    // An unknown key is dropped rather than defaulted: rendering a "Heart Line" row for
    // something the model called girdle_of_venus is worse than showing seven rows.
    if (!LINE_KEYS.includes(key) || seen.has(key)) continue;

    const detail = text(line.detail, 900);
    if (!detail) continue;
    seen.add(key);

    const meaning = (Array.isArray(line.meaning) ? line.meaning : [])
      .map((bullet) => text(bullet, 200))
      .filter((bullet) => bullet.length > 0)
      .slice(0, 3);

    const status = String(line.status ?? "");

    byKey.set(key, {
      key,
      title: text(line.title, 40) || LINE_TITLES[key],
      // Two words at most, so a model that answers with a whole shloka cannot push the title
      // row into a second line on a phone.
      sanskrit: text(line.sanskrit, 32),
      // An unrecognised status label must not cost the whole line.
      status: (STATUSES as readonly string[]).includes(status) ? status : "Balanced",
      summary: text(line.summary, 110),
      detail,
      meaning,
      tip: text(line.tip, 220),
      blessing: text(line.blessing, 180),
    });
  }

  // Canonical display order, not the order the model happened to emit.
  const lines = LINE_KEYS.map((key) => byKey.get(key)).filter((line): line is NormalisedLine =>
    line !== undefined
  );

  if (lines.length < 6) {
    return { ...reject(), rejected: "incomplete" };
  }

  const trait = (root.strongest_trait ?? {}) as Record<string, unknown>;

  return {
    rejected: null,
    // The server's own value wins; `focus_echo` exists only to notice a disagreement.
    focus,
    ...ceremony(root),
    headline: text(root.headline, 120),
    strongestTrait: {
      title: text(trait.title, 60),
      summary: text(trait.summary, 160),
      detail: text(trait.detail, 600),
    },
    hand: (root.hand ?? {}) as Record<string, unknown>,
    lines,
  };
}
