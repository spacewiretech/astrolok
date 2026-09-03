/**
 * Gemini, called with the API key held server-side.
 *
 * Same reasoning as `fast2sms.ts`: the key never reaches a device, where it would be
 * extractable from the app bundle. It is read from a private `app_config` row at call time, so
 * rotating it is a dashboard edit rather than a redeploy.
 *
 * The two exports worth knowing about are [readPalm], which talks to the model, and
 * [normalisePalmReading], which turns whatever came back into something the app can render.
 * They are separate so the second — where all the correctness lives — is unit-testable with no
 * network and no key.
 */

import { AppConfig, configSetting } from "./config.ts";

const BASE = "https://generativelanguage.googleapis.com/v1beta";

/** First attempt. Generous: a multimodal call with ~1200 output tokens runs 10-20s. */
const TIMEOUT_MS = 40_000;

/** A retry is only worth starting if there is room for it inside the function's own deadline. */
const RETRY_TIMEOUT_MS = 25_000;
const RETRY_DEADLINE_MS = 30_000;

export class GeminiError extends Error {
  constructor(
    readonly code: number | null,
    readonly userMessage: string,
    readonly detail: string,
    /** Set for failures raised locally, before any request went out. */
    readonly isLocalConfigProblem = false,
  ) {
    super(detail);
  }

  /** True when the fix is on the account or in `app_config`, not anything a user did. */
  get isConfigurationProblem(): boolean {
    // A missing key carries no status code, so it has to be flagged explicitly — without this
    // it would be the one failure that never reaches the logs.
    if (this.isLocalConfigProblem) return true;
    return this.code !== null && [400, 401, 403, 404].includes(this.code);
  }

  /** Overload or outage. Worth one attempt on the fallback model. */
  get isTransient(): boolean {
    return this.code !== null && [429, 500, 502, 503, 504].includes(this.code);
  }
}

export interface GeminiSettings {
  apiKey: string;
  model: string;
  fallbackModel: string;
}

/**
 * Read from private `app_config` rows, never from the device.
 *
 * `gemini_api_key` is the name that matches this codebase's lowercase convention and is the one
 * the secret-guard CHECK forces private. `GEMINI_AI_KEY` is accepted as well because a row may
 * already exist under that name — `loadConfig` trims keys but does not case-fold, so both
 * spellings have to be looked up explicitly rather than matched loosely.
 */
export function geminiSettings(config: AppConfig): GeminiSettings {
  const apiKey = configSetting(config, "gemini_api_key") ||
    configSetting(config, "GEMINI_AI_KEY");

  return {
    apiKey,
    // Only a backstop for an empty config row; the value that actually ships lives in
    // `app_config` so a retired model is a dashboard edit rather than a redeploy. Not every
    // model accepts this request shape — see the notes in 0004_palm_models.sql before
    // changing either of these.
    model: configSetting(config, "gemini_model") || "gemini-3.8-flash",
    fallbackModel: configSetting(config, "gemini_model_fallback"),
  };
}

// ---------------------------------------------------------------- the reading

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

export const FOCUS_KEYS = ["love", "career", "money", "personality", "life_path"] as const;
export type FocusKey = typeof FOCUS_KEYS[number];

export const FOCUS_LABELS: Record<FocusKey, string> = {
  love: "Love & Relationships",
  career: "Career & Purpose",
  money: "Money & Abundance",
  personality: "Personality & Strengths",
  life_path: "Life Path",
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
    "headline",
    "strongest_trait",
    "lines",
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
    focus_echo: { type: "STRING", enum: [...FOCUS_KEYS] },

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
        propertyOrdering: ["key", "title", "status", "summary", "detail", "meaning", "tip"],
        required: ["key", "title", "status", "summary", "detail"],
        properties: {
          key: { type: "STRING", enum: [...LINE_KEYS] },
          title: { type: "STRING" },
          status: {
            type: "STRING",
            enum: ["Strong", "Balanced", "Deep", "Developing", "Clear", "Faint"],
          },
          summary: { type: "STRING" },
          detail: { type: "STRING" },
          meaning: {
            type: "ARRAY",
            minItems: 3,
            maxItems: 3,
            items: { type: "STRING" },
          },
          tip: { type: "STRING" },
        },
      },
    },
  },
};

/**
 * The persona, the grounding rule, and the boundaries.
 *
 * The boundaries are written as instructions about *how to write*, not as a disclaimer to
 * append. A model told "add a disclaimer" writes the claim and then apologises for it; a model
 * told "never use deterministic verbs" does not write the claim in the first place.
 */
export const SYSTEM_PROMPT = `
You are an experienced Indian palmist writing directly to one person about their hand. Your
voice is warm, specific and plain. Write in the second person. No preamble, no throat-clearing,
no mention of being an AI, no meta-commentary about the photo quality.

HOW TO GROUND THE READING — this matters more than anything else here.

First fill in "hand" from what you can genuinely see in the photograph: the texture of the
skin, how soft or firm the hand looks, the shape of the palm, the length of the fingers against
the palm, any calluses or marks. Then write every "detail" paragraph so that it refers to at
least one of those concrete observations in ordinary language, as evidence for what you are
saying. For example: "Your palm is broad and the skin is smooth and unmarked — hands like this
usually belong to people who work with ideas rather than with tools, and your head line agrees
with that." A soft, smooth, unmarked hand suggests a life spent away from heavy physical work;
a firm hand with calluses and thick skin suggests someone physically active and hands-on. Say
so, warmly and without judgement — both are good hands to have.

Never invent a detail you cannot see. If something is genuinely unclear in the photo, record it
as "unclear" in "hand" and write around it rather than guessing.

BOUNDARIES — these are absolute.

- Never mention health, illness, diagnosis, recovery, fertility, pregnancy, or mental health.
  The life line is about vitality, resilience and stamina — NEVER about how long someone will
  live, never about death, never about a lifespan. The Mercury line is about communication,
  wit and everyday energy — never about the body or medicine.
- Never guarantee an outcome about money, work, marriage or family. Never give a date, a year,
  or an age at which something will happen.
- Never use deterministic verbs. Not "you will", not "this means you have", not "you are going
  to". Always "tends to", "suggests", "leans toward", "hands like yours often".
- Never give advice that belongs to a professional — medical, legal or financial.
- Never comment on caste, religion, ethnicity, appearance, weight, disability or gender roles.
- Every "tip" is a small, kind, practical nudge about behaviour. Never a warning, never a
  purchase, never a remedy, gemstone, ritual or charm.

LENGTH — write to these budgets and do not pad.

- headline: at most 12 words.
- strongest_trait.title: 2-4 words. summary: at most 20 words. detail: 40-60 words.
- Each line summary: at most 12 words. Each line detail: 45-70 words.
- Each "meaning" bullet: 10-18 words. Each tip: at most 25 words.

STYLE — vary your openings. Do not begin more than one paragraph with the word "Your".
`.trim();

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
    "every one of them a status, a short summary, a detailed paragraph grounded in what you " +
    "can see of the hand, three specific bullets under meaning, and one tip.",
  ].join("\n");
}

// ---------------------------------------------------------------- the call

interface GeminiCandidate {
  content?: { parts?: Array<{ text?: string }> };
  finishReason?: string;
}

interface GeminiResponse {
  candidates?: GeminiCandidate[];
  promptFeedback?: { blockReason?: string };
  usageMetadata?: Record<string, number>;
}

/** What a blocked or filtered response tells the user. Never "no palm" — see the call site. */
const UNREADABLE =
  "We couldn't read that photo. Try again in better light with your palm filling the frame.";

const BUSY = "Our reader is very busy right now. Please try again in a minute.";

async function post(
  model: string,
  apiKey: string,
  body: unknown,
  timeoutMs: number,
): Promise<GeminiResponse> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  let response: Response;
  try {
    response = await fetch(`${BASE}/models/${model}:generateContent`, {
      method: "POST",
      headers: {
        // In a header, never as ?key= — a URL ends up in access logs and in the text of
        // thrown errors, and this one is a credential.
        "x-goog-api-key": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (error) {
    const aborted = error instanceof DOMException && error.name === "AbortError";
    throw new GeminiError(
      null,
      aborted ? BUSY : "Could not reach the reading service. Please try again.",
      `fetch failed on ${model}: ${error}`,
    );
  } finally {
    clearTimeout(timer);
  }

  if (!response.ok) {
    // The body carries Google's own reason. Worth logging in full; never worth showing.
    const detail = await response.text().catch(() => "<unreadable>");
    throw new GeminiError(
      response.status,
      response.status === 429 || response.status >= 500 ? BUSY : UNREADABLE,
      `${model} returned ${response.status}: ${detail.slice(0, 500)}`,
    );
  }

  return await response.json() as GeminiResponse;
}

function requestBody(
  imageBase64: string,
  mimeType: string,
  userPrompt: string,
  maxOutputTokens: number,
) {
  return {
    systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
    contents: [{
      role: "user",
      parts: [
        // Image before text: Gemini's own guidance for single-image prompts, and it visibly
        // improves how well the reading sticks to what is actually in the photo.
        { inline_data: { mime_type: mimeType, data: imageBase64 } },
        { text: userPrompt },
      ],
    }],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: PALM_SCHEMA,
      // High enough that eight paragraphs do not read as eight copies of one paragraph.
      temperature: 0.85,
      topP: 0.95,
      maxOutputTokens,
      // Thinking on a structured description task buys little and costs seconds the user is
      // watching tick by on the scan screen.
      thinkingConfig: { thinkingBudget: 0 },
    },
    // A photograph of a human hand occasionally trips the default threshold, and a safety
    // block after a twenty-second wait is the worst failure this feature has. Loosening the
    // threshold reduces that; it does not eliminate it, so blocks are still handled below.
    safetySettings: [
      "HARM_CATEGORY_HARASSMENT",
      "HARM_CATEGORY_HATE_SPEECH",
      "HARM_CATEGORY_SEXUALLY_EXPLICIT",
      "HARM_CATEGORY_DANGEROUS_CONTENT",
    ].map((category) => ({ category, threshold: "BLOCK_ONLY_HIGH" })),
  };
}

/** Pulls the JSON text out of a candidate, or explains why there isn't any. */
function textFrom(response: GeminiResponse): string {
  const blocked = response.promptFeedback?.blockReason;
  if (blocked) {
    // Deliberately NOT a no-palm rejection. The photo may be a perfectly good palm that a
    // filter disliked, and telling the user "no palm detected" would send them into a loop of
    // retaking a photo that was fine.
    throw new GeminiError(null, UNREADABLE, `prompt blocked: ${blocked}`);
  }

  const candidate = response.candidates?.[0];
  const reason = candidate?.finishReason;

  if (reason && !["STOP", "MAX_TOKENS"].includes(reason)) {
    throw new GeminiError(null, UNREADABLE, `finishReason ${reason}`);
  }

  const text = (candidate?.content?.parts ?? [])
    .map((part) => part.text ?? "")
    .join("")
    .trim();

  if (!text) throw new GeminiError(null, BUSY, `empty candidate (finishReason ${reason})`);

  // Truncated JSON. The caller retries with a bigger cap rather than trying to repair it.
  if (reason === "MAX_TOKENS") {
    throw new GeminiError(null, BUSY, "MAX_TOKENS: response truncated", false);
  }

  return text;
}

export interface PalmRequest {
  imageBase64: string;
  mimeType: string;
  focus: FocusKey;
  name?: string | null;
  age?: number | null;
}

export interface PalmRawResult {
  parsed: Record<string, unknown>;
  model: string;
  latencyMs: number;
}

/**
 * One reading. Retries once — on a bigger token cap after a truncation, on the fallback model
 * after an overload, or simply again after unparseable JSON (temperature is above zero, so the
 * second attempt is genuinely a different sample rather than the same failure repeated).
 */
export async function readPalm(
  settings: GeminiSettings,
  request: PalmRequest,
): Promise<PalmRawResult> {
  if (!settings.apiKey) {
    throw new GeminiError(
      null,
      "Readings are temporarily unavailable. Please try again later.",
      "gemini_api_key is empty in app_config; paste it in from the dashboard",
      true,
    );
  }

  const startedAt = Date.now();
  const userPrompt = buildUserPrompt(request);

  const attempt = async (model: string, maxTokens: number, timeoutMs: number) => {
    const response = await post(
      model,
      settings.apiKey,
      requestBody(request.imageBase64, request.mimeType, userPrompt, maxTokens),
      timeoutMs,
    );
    return JSON.parse(textFrom(response)) as Record<string, unknown>;
  };

  try {
    return {
      parsed: await attempt(settings.model, 4096, TIMEOUT_MS),
      model: settings.model,
      latencyMs: Date.now() - startedAt,
    };
  } catch (first) {
    const elapsed = Date.now() - startedAt;
    const error = first instanceof GeminiError ? first : null;

    // Out of time, or a failure a second identical call cannot fix.
    if (elapsed > RETRY_DEADLINE_MS || error?.isConfigurationProblem) throw first;

    const truncated = error?.detail.startsWith("MAX_TOKENS") ?? false;
    const useFallback = (error?.isTransient ?? false) && settings.fallbackModel !== "";
    const model = useFallback ? settings.fallbackModel : settings.model;

    console.warn(
      `gemini retry after ${elapsed}ms on ${model}`,
      error?.detail ?? String(first),
    );

    return {
      parsed: await attempt(model, truncated ? 6144 : 4096, RETRY_TIMEOUT_MS),
      model,
      latencyMs: Date.now() - startedAt,
    };
  }
}

// ---------------------------------------------------------------- normalising

/** Trim, coerce and clamp at a word boundary so a clipped sentence does not end mid-word. */
function text(value: unknown, max: number): string {
  const raw = String(value ?? "").trim().replace(/\s+/g, " ");
  if (raw.length <= max) return raw;

  const cut = raw.slice(0, max);
  const space = cut.lastIndexOf(" ");
  return (space > max * 0.6 ? cut.slice(0, space) : cut).trimEnd();
}

const STATUSES = ["Strong", "Balanced", "Deep", "Developing", "Clear", "Faint"];

export interface NormalisedLine {
  key: LineKey;
  title: string;
  status: string;
  summary: string;
  detail: string;
  meaning: string[];
  tip: string;
}

export interface NormalisedReading {
  rejected: string | null;
  focus: FocusKey;
  headline: string;
  strongestTrait: { title: string; summary: string; detail: string };
  hand: Record<string, unknown>;
  lines: NormalisedLine[];
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
    headline: "",
    strongestTrait: { title: "", summary: "", detail: "" },
    hand: {},
    lines: [],
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
      // An unrecognised status label must not cost the whole line.
      status: STATUSES.includes(status) ? status : "Balanced",
      summary: text(line.summary, 110),
      detail,
      meaning,
      tip: text(line.tip, 220),
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

/** True when the model echoed a focus other than the one asked for. Logged, never surfaced. */
export function focusMismatch(raw: unknown, focus: FocusKey): boolean {
  const echo = (raw as Record<string, unknown> | null)?.focus_echo;
  return typeof echo === "string" && echo !== focus;
}
