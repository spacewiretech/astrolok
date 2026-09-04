/**
 * What to ask the model about a face, and how to make sense of what comes back.
 *
 * Deliberately the same shape as `palm_reading.ts` — same transport, same voice, same status
 * vocabulary, same normalise-don't-throw contract — so the two features cannot drift and the
 * app can render both through one set of widgets.
 *
 * One thing is genuinely different, and it is the reason this file has more prose in it than the
 * palm one: a hand carries almost none of the signals people are judged on, and a face carries
 * all of them. [FACE_CRAFT] therefore names what may be read (shape, set, proportion, expression)
 * and the shared [BOUNDARIES] block names what may not, item by item, rather than trusting the
 * model's own sense of what counts as a comment on someone's appearance.
 */

import { ceremony, FOCUS_LABELS, FocusKey, STATUSES, text } from "./gemini.ts";
import { panditSystemPrompt, SHARED_LENGTHS } from "./pandit.ts";

export { FOCUS_KEYS, FOCUS_LABELS, focusMismatch, parseFocus } from "./gemini.ts";
export type { FocusKey } from "./gemini.ts";

/**
 * The six features, in the order the results screen lists them.
 *
 * The first four are the ones the design ships artwork for; forehead and eyebrows are read by
 * Samudrika Shastra just as centrally and give the results list enough body to be worth
 * scrolling. Declaration order is display order.
 */
export const FACE_KEYS = [
  "eyes",
  "face_shape",
  "nose",
  "lips",
  "forehead",
  "eyebrows",
] as const;

export type FaceKey = typeof FACE_KEYS[number];

/** Fallback titles, used when the model omits one. */
export const FACE_TITLES: Record<FaceKey, string> = {
  eyes: "Eyes",
  face_shape: "Face Shape",
  nose: "Nose",
  lips: "Lips",
  forehead: "Forehead",
  eyebrows: "Eyebrows",
};

/**
 * The four chips under the core trait.
 *
 * A closed vocabulary rather than free text, because each one renders as an icon in a specific
 * colour: a word the app has no glyph for would draw an empty tile. The list is long enough that
 * four picks from it still feel particular to the reading.
 *
 * Every entry is a disposition — how someone tends to act. Nothing here describes a body, a
 * background or a circumstance, which is what keeps the chips inside [BOUNDARIES].
 */
export const TRAIT_KEYS = [
  "independent",
  "observant",
  "warm",
  "determined",
  "patient",
  "expressive",
  "grounded",
  "curious",
  "loyal",
  "generous",
  "disciplined",
  "intuitive",
] as const;

export type TraitKey = typeof TRAIT_KEYS[number];

export const REJECT_REASONS = [
  "none",
  "no_face",
  "not_a_face",
  "too_dark",
  "too_blurry",
  "too_far",
  "obstructed",
] as const;

/**
 * The response contract.
 *
 * `propertyOrdering` puts `is_face` and `face` first for the same load-bearing reason palm does:
 * structured output is generated in order, so the model records what it can actually see before
 * it writes prose that has to cite it. Reversed, the observations become a justification of a
 * reading already written and the whole thing reads like a horoscope.
 *
 * Only `is_face` and `reject_reason` are required, so a rejection is two fields and a ~2s round
 * trip rather than twenty seconds spent on a reading that is then discarded.
 */
export const FACE_SCHEMA = {
  type: "OBJECT",
  propertyOrdering: [
    "is_face",
    "reject_reason",
    "face",
    "focus_echo",
    "invocation",
    "headline",
    "core_trait",
    "traits",
    "parts",
    "blessing",
  ],
  required: ["is_face", "reject_reason"],
  properties: {
    is_face: { type: "BOOLEAN" },
    reject_reason: { type: "STRING", enum: [...REJECT_REASONS] },

    /**
     * What is actually visible. Every `detail` below has to draw on one of these.
     *
     * Note what is absent and must stay absent: complexion, skin tone, apparent age, apparent
     * gender, attractiveness. Those are not observations this reading is entitled to make, and
     * leaving them out of the schema is the cheapest way to make sure they never appear.
     */
    face: {
      type: "OBJECT",
      propertyOrdering: [
        "face_shape",
        "forehead_height",
        "eyebrow_thickness",
        "eye_set",
        "nose_bridge",
        "lip_fullness",
        "expression",
        "observations",
      ],
      properties: {
        face_shape: {
          type: "STRING",
          enum: ["oval", "round", "square", "heart", "long", "diamond", "unclear"],
        },
        forehead_height: { type: "STRING", enum: ["low", "medium", "high", "unclear"] },
        eyebrow_thickness: { type: "STRING", enum: ["fine", "medium", "thick", "unclear"] },
        eye_set: { type: "STRING", enum: ["close", "balanced", "wide", "unclear"] },
        nose_bridge: { type: "STRING", enum: ["soft", "straight", "prominent", "unclear"] },
        lip_fullness: { type: "STRING", enum: ["thin", "medium", "full", "unclear"] },
        expression: {
          type: "STRING",
          enum: ["calm", "warm", "intense", "reserved", "unclear"],
        },
        observations: {
          type: "ARRAY",
          minItems: 2,
          maxItems: 4,
          items: { type: "STRING" },
        },
      },
    },

    focus_echo: { type: "STRING", enum: ["love", "career", "money", "personality", "life_path"] },

    invocation: { type: "STRING" },
    headline: { type: "STRING" },

    /** The hero card: "Your core Trait — Naturally Intuitive". */
    core_trait: {
      type: "OBJECT",
      propertyOrdering: ["title", "summary", "detail"],
      properties: {
        title: { type: "STRING" },
        summary: { type: "STRING" },
        detail: { type: "STRING" },
      },
    },

    traits: {
      type: "ARRAY",
      minItems: 4,
      maxItems: 4,
      items: { type: "STRING", enum: [...TRAIT_KEYS] },
    },

    parts: {
      type: "ARRAY",
      minItems: 6,
      maxItems: 6,
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
          key: { type: "STRING", enum: [...FACE_KEYS] },
          title: { type: "STRING" },
          sanskrit: { type: "STRING" },
          status: { type: "STRING", enum: [...STATUSES] },
          summary: { type: "STRING" },
          detail: { type: "STRING" },
          meaning: {
            type: "ARRAY",
            minItems: 3,
            maxItems: 4,
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

/**
 * Face-specific craft notes.
 *
 * The traditional terms are given explicitly rather than left to the model, so the same feature
 * is called the same thing on every reading — a user who reads their face twice should not find
 * their eyes named Netra one week and something else the next.
 */
const FACE_CRAFT = `
WHAT A FACE TELLS YOU.

You are reading Mukha Samudrika — the face as the old texts read it. The traditional names, which
you should use for the "sanskrit" field exactly as written here:

- eyes: Netra          - face_shape: Mukha Akriti
- nose: Nasika         - lips: Adhara
- forehead: Lalata     - eyebrows: Bhru

What each is traditionally read for:

- Netra (eyes) — feeling, intuition, and how someone takes other people in. Read how they are
  set, how wide or steady the gaze is, how much of the lid shows.
- Mukha Akriti (face shape) — temperament and the overall cast of the personality. Read the
  proportion of the three zones: forehead, mid-face, jaw.
- Nasika (nose) — drive, initiative and how someone spends their energy. Read the bridge and the
  proportion against the mid-face.
- Adhara (lips) — expression, warmth, and how someone is in close company. Read fullness and the
  set of the mouth at rest.
- Lalata (forehead) — reflection, memory and the long view. Read height and breadth.
- Bhru (eyebrows) — will, focus and how someone meets resistance. Read thickness, arch and how
  evenly they run.

Read shape, set, proportion and the expression the face is holding. Those are the whole of your
evidence. You may say a jaw is broad or a gaze is steady; you may not say anything about
complexion, skin tone, apparent age, apparent gender, or how attractive a face is — those are
not readings, and they are forbidden outright.

An example of the right level: "Your Lalata — the forehead — is high and open, and the brow sits
unhurried above the eyes. Faces carrying that proportion tend to belong to people who think a
thing through before committing to it, and who are slow to be rushed."

Where two features disagree, say so. A steady gaze above a mobile mouth is a real and interesting
combination, and naming the tension is more useful than smoothing it away.
`.trim();

const FACE_LENGTHS = [
  "LENGTH — write to these budgets and do not pad.",
  "",
  SHARED_LENGTHS,
  "- core_trait.title: 2-3 words. summary: at most 24 words. detail: 40-60 words.",
  "- Each part summary: at most 14 words. Each part detail: 50-80 words.",
  '- Each "meaning" bullet: 10-20 words. Each tip: at most 25 words.',
  "- Each part blessing: at most 18 words.",
  "- sanskrit: the traditional name given above, nothing else.",
].join("\n");

export const SYSTEM_PROMPT = panditSystemPrompt({
  craft: FACE_CRAFT,
  lengths: FACE_LENGTHS,
});

/**
 * When to refuse, stated as narrowly as possible.
 *
 * The palm version of this list had to be rewritten once, after real palms came back rejected
 * because a second hand was visible behind the first. The lesson transfers: a false rejection is
 * much the worse error — the user is sent back to retake a photograph that was fine, having
 * already waited, on a feature they pay for.
 *
 * The "not reasons to refuse" list matters more here than it did for palms. Glasses, a beard, a
 * turban, a dupatta and a hijab are all ordinary, and a reader that quietly refuses some faces
 * and not others is a far worse failure than a mediocre reading.
 */
const REJECTION_POLICY = [
  "Refuse only when you genuinely cannot read a face: there is no person in the image at all, " +
  "the back or side of the head is turned to the camera so that the features cannot be seen, " +
  "the image is too dark or too blurred to make out any features, or the face is covered by a " +
  "mask, a hand or an object.",
  "",
  "These are NOT reasons to refuse. Read the face as normal in every one of these cases:",
  "- More than one person is visible. Read the largest, clearest, most front-facing one.",
  "- Spectacles or sunglasses pushed up; a beard, moustache or stubble; make-up.",
  "- A turban, cap, dupatta, hijab or any head covering that leaves the face itself visible.",
  "- Jewellery, a bindi, piercings, tattoos, scars or marks.",
  "- Hair falling across the forehead, or the ears or crown cropped by the frame.",
  "- The head is slightly turned or tilted rather than perfectly square to the camera.",
  "- The lighting is uneven, or one side of the face is in shadow.",
  "",
  "If you are in any doubt, proceed with the reading rather than refusing. When you do refuse, " +
  "return only is_face: false with the matching reject_reason and stop.",
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
    `Their chosen focus is "${FOCUS_LABELS[focus]}". The core_trait and at least three of the ` +
    "six part details must speak to that focus directly.",
    "",
    "Read all six features: eyes, face_shape, nose, lips, forehead and eyebrows. Give every " +
    "one of them its traditional name, a status, a short summary, a detailed paragraph " +
    "grounded in what you can see of the face, three or four specific bullets under meaning, " +
    "one tip, and one short blessing.",
    "",
    "Then choose exactly four traits from the allowed list that this face actually supports. " +
    "Do not pick four that say the same thing.",
  ].join("\n");
}

// ---------------------------------------------------------------- normalising

export interface NormalisedPart {
  key: FaceKey;
  title: string;
  sanskrit: string;
  status: string;
  summary: string;
  detail: string;
  meaning: string[];
  tip: string;
  blessing: string;
}

export interface NormalisedFaceReading {
  rejected: string | null;
  focus: FocusKey;
  invocation: string;
  headline: string;
  coreTrait: { title: string; summary: string; detail: string };
  traits: TraitKey[];
  face: Record<string, unknown>;
  parts: NormalisedPart[];
  blessing: string;
}

/**
 * Turns whatever the model returned into something the app can render, or says it cannot.
 *
 * Same contract as [normalisePalmReading]: never throws on a merely imperfect payload, because
 * after a twenty-second wait a user is far better served by five solid sections than by an
 * error. It gives up only below four, where the results screen would look broken rather than
 * short.
 *
 * Pure and exported so all of it is testable without a network or a key.
 */
export function normaliseFaceReading(
  raw: unknown,
  focus: FocusKey,
): NormalisedFaceReading {
  const root = (raw ?? {}) as Record<string, unknown>;

  const reject = () => ({
    rejected: REJECT_REASONS.includes(root.reject_reason as typeof REJECT_REASONS[number])
      ? String(root.reject_reason)
      : "not_a_face",
    focus,
    invocation: "",
    headline: "",
    coreTrait: { title: "", summary: "", detail: "" },
    traits: [] as TraitKey[],
    face: {},
    parts: [] as NormalisedPart[],
    blessing: "",
  });

  if (root.is_face !== true) return reject();
  // "is_face: true" alongside a real rejection reason is a contradiction; trust the reason.
  if (root.reject_reason && root.reject_reason !== "none") return reject();

  const seen = new Set<string>();
  const byKey = new Map<FaceKey, NormalisedPart>();

  for (const entry of Array.isArray(root.parts) ? root.parts : []) {
    const part = (entry ?? {}) as Record<string, unknown>;
    const key = String(part.key ?? "") as FaceKey;

    // An unknown key is dropped rather than defaulted: an "Eyes" row holding a reading of
    // something else is worse than five rows.
    if (!FACE_KEYS.includes(key) || seen.has(key)) continue;

    const detail = text(part.detail, 900);
    if (!detail) continue;
    seen.add(key);

    const meaning = (Array.isArray(part.meaning) ? part.meaning : [])
      .map((bullet) => text(bullet, 200))
      .filter((bullet) => bullet.length > 0)
      .slice(0, 4);

    const status = String(part.status ?? "");

    byKey.set(key, {
      key,
      title: text(part.title, 40) || FACE_TITLES[key],
      sanskrit: text(part.sanskrit, 32),
      // An unrecognised status label must not cost the whole section.
      status: (STATUSES as readonly string[]).includes(status) ? status : "Balanced",
      summary: text(part.summary, 120),
      detail,
      meaning,
      tip: text(part.tip, 220),
      blessing: text(part.blessing, 180),
    });
  }

  // Canonical display order, not the order the model happened to emit.
  const parts = FACE_KEYS.map((key) => byKey.get(key)).filter((part): part is NormalisedPart =>
    part !== undefined
  );

  if (parts.length < 4) {
    return { ...reject(), rejected: "incomplete" };
  }

  // Unknown trait words are dropped rather than passed through: the app draws an icon per trait,
  // and a word it has no glyph for is an empty tile. Duplicates go too — four chips saying the
  // same thing reads as a bug.
  const traits: TraitKey[] = [];
  for (const entry of Array.isArray(root.traits) ? root.traits : []) {
    const trait = String(entry ?? "").trim().toLowerCase() as TraitKey;
    if (TRAIT_KEYS.includes(trait) && !traits.includes(trait)) traits.push(trait);
    if (traits.length === 4) break;
  }

  const trait = (root.core_trait ?? {}) as Record<string, unknown>;

  return {
    rejected: null,
    // The server's own value wins; `focus_echo` exists only to notice a disagreement.
    focus,
    ...ceremony(root),
    headline: text(root.headline, 120),
    coreTrait: {
      title: text(trait.title, 60),
      summary: text(trait.summary, 180),
      detail: text(trait.detail, 600),
    },
    traits,
    face: (root.face ?? {}) as Record<string, unknown>,
    parts,
  };
}
