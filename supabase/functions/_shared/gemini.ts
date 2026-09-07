/**
 * Gemini, called with the API key held server-side.
 *
 * Same reasoning as `fast2sms.ts`: the key never reaches a device, where it would be
 * extractable from the app bundle. It is read from a private `app_config` row at call time, so
 * rotating it is a dashboard edit rather than a redeploy.
 *
 * This file is the transport and nothing else — one export, [readImage], that takes a prompt and
 * a schema and hands back parsed JSON. What to ask for lives in `palm_reading.ts` and
 * `face_reading.ts`; how to say it lives in `pandit.ts`. Keeping the split means a second
 * reading feature costs a schema and a prompt rather than a second copy of the retry policy,
 * and it keeps the parts where all the correctness lives — the normalisers — testable with no
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
    // model accepts this request shape — see the notes in 0005_palm_models.sql before
    // changing either of these.
    model: configSetting(config, "gemini_model") || "gemini-3.8-flash",
    fallbackModel: configSetting(config, "gemini_model_fallback"),
  };
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

/**
 * What a blocked or filtered response tells the user.
 *
 * Deliberately generic about the subject — "that photo", not "your palm" — so one string serves
 * both features. Never a no-subject-found rejection: see [textFrom].
 */
const UNREADABLE =
  "We couldn't read that photo. Try again in better light, with the subject filling the frame.";

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

/** One turn of a conversation. `model` is Gemini's name for its own side. */
export interface Turn {
  role: "user" | "model";
  text: string;
}

/**
 * The request body, given whatever `contents` the caller has assembled.
 *
 * Parameterised over `contents` rather than over an image, because that array is the only thing
 * a photo reading and a chat turn genuinely disagree about — everything below it is the same
 * generation config and the same safety settings.
 */
function requestBody(
  contents: unknown[],
  systemPrompt: string,
  schema: unknown,
  maxOutputTokens: number,
) {
  return {
    systemInstruction: { parts: [{ text: systemPrompt }] },
    contents,
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: schema,
      // High enough that eight paragraphs do not read as eight copies of one paragraph.
      temperature: 0.85,
      topP: 0.95,
      maxOutputTokens,
      // Thinking on a structured description task buys little and costs seconds the user is
      // watching tick by on the scan screen.
      thinkingConfig: { thinkingBudget: 0 },
    },
    // A photograph of a human hand or face occasionally trips the default threshold, and a
    // safety block after a twenty-second wait is the worst failure these features have.
    // Loosening the threshold reduces that; it does not eliminate it, so blocks are still
    // handled below.
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
    // Deliberately NOT a nothing-detected rejection. The photo may be a perfectly good palm or
    // face that a filter disliked, and telling the user "no palm detected" would send them into
    // a loop of retaking a photo that was fine.
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

export interface ImageReadRequest {
  imageBase64: string;
  mimeType: string;
  systemPrompt: string;
  userPrompt: string;
  schema: unknown;
}

export interface ChatRequest {
  systemPrompt: string;
  schema: unknown;

  /** Everything said so far, oldest first. The newest user turn is [userPrompt], not this. */
  history: Turn[];

  /** What the user has just said, wrapped by the caller with whatever context it wants to add. */
  userPrompt: string;
}

export interface GeminiRawResult {
  parsed: Record<string, unknown>;
  model: string;
  latencyMs: number;
}

/** The time and token budgets one kind of call gets. */
interface Budget {
  firstTokens: number;
  retryTokens: number;
  timeoutMs: number;
  retryTimeoutMs: number;
  retryDeadlineMs: number;
}

/** A multimodal reading: ~1200 output tokens, 10-20 seconds. */
const READING_BUDGET: Budget = {
  firstTokens: 4096,
  retryTokens: 6144,
  timeoutMs: TIMEOUT_MS,
  retryTimeoutMs: RETRY_TIMEOUT_MS,
  retryDeadlineMs: RETRY_DEADLINE_MS,
};

/**
 * A chat turn: a few hundred output tokens, 2-5 seconds.
 *
 * Its own budget rather than the reading's, because someone is watching a cursor blink. Waiting
 * forty seconds for a sentence would feel broken, and a caller who wanted the reading's patience
 * would be waiting on a request that had already failed.
 */
const CHAT_BUDGET: Budget = {
  firstTokens: 1536,
  retryTokens: 2560,
  timeoutMs: 20_000,
  retryTimeoutMs: 12_000,
  retryDeadlineMs: 14_000,
};

/**
 * The call, the retry, and the rules for when a retry is worth making.
 *
 * Shared by both entry points so the policy exists once: a bigger token cap after a truncation,
 * the fallback model after an overload, or simply another sample after unparseable JSON —
 * temperature is above zero, so a second attempt is genuinely different rather than the same
 * failure repeated.
 */
async function send(
  settings: GeminiSettings,
  contents: unknown[],
  systemPrompt: string,
  schema: unknown,
  budget: Budget,
): Promise<GeminiRawResult> {
  if (!settings.apiKey) {
    throw new GeminiError(
      null,
      "Readings are temporarily unavailable. Please try again later.",
      "gemini_api_key is empty in app_config; paste it in from the dashboard",
      true,
    );
  }

  const startedAt = Date.now();

  const attempt = async (model: string, maxTokens: number, timeoutMs: number) => {
    const response = await post(
      model,
      settings.apiKey,
      requestBody(contents, systemPrompt, schema, maxTokens),
      timeoutMs,
    );
    return JSON.parse(textFrom(response)) as Record<string, unknown>;
  };

  try {
    return {
      parsed: await attempt(settings.model, budget.firstTokens, budget.timeoutMs),
      model: settings.model,
      latencyMs: Date.now() - startedAt,
    };
  } catch (first) {
    const elapsed = Date.now() - startedAt;
    const error = first instanceof GeminiError ? first : null;

    // Out of time, or a failure a second identical call cannot fix.
    if (elapsed > budget.retryDeadlineMs || error?.isConfigurationProblem) throw first;

    const truncated = error?.detail.startsWith("MAX_TOKENS") ?? false;
    const useFallback = (error?.isTransient ?? false) && settings.fallbackModel !== "";
    const model = useFallback ? settings.fallbackModel : settings.model;

    console.warn(
      `gemini retry after ${elapsed}ms on ${model}`,
      error?.detail ?? String(first),
    );

    return {
      parsed: await attempt(
        model,
        truncated ? budget.retryTokens : budget.firstTokens,
        budget.retryTimeoutMs,
      ),
      model,
      latencyMs: Date.now() - startedAt,
    };
  }
}

/** One reading of one photograph. */
export function readImage(
  settings: GeminiSettings,
  request: ImageReadRequest,
): Promise<GeminiRawResult> {
  const contents = [{
    role: "user",
    parts: [
      // Image before text: Gemini's own guidance for single-image prompts, and it visibly
      // improves how well the reading sticks to what is actually in the photo.
      { inline_data: { mime_type: request.mimeType, data: request.imageBase64 } },
      { text: request.userPrompt },
    ],
  }];

  return send(settings, contents, request.systemPrompt, request.schema, READING_BUDGET);
}

/**
 * One turn of a conversation.
 *
 * The history is sent as real alternating turns rather than flattened into one prompt, because
 * that is what the model is trained on: it tracks who said what, and it will not mistake
 * something it said earlier for something the user asserted.
 */
export function converse(
  settings: GeminiSettings,
  request: ChatRequest,
): Promise<GeminiRawResult> {
  const contents = [
    ...request.history.map((turn) => ({
      role: turn.role,
      parts: [{ text: turn.text }],
    })),
    { role: "user", parts: [{ text: request.userPrompt }] },
  ];

  return send(settings, contents, request.systemPrompt, request.schema, CHAT_BUDGET);
}

// ---------------------------------------------------------------- shared normalising

/**
 * Trim, coerce and clamp at a word boundary so a clipped sentence does not end mid-word.
 *
 * Shared by both normalisers — every string either reading shows a user passes through here, so
 * a model that ignores its length budget cannot break a layout.
 */
export function text(value: unknown, max: number): string {
  const raw = String(value ?? "").trim().replace(/\s+/g, " ");
  if (raw.length <= max) return raw;

  const cut = raw.slice(0, max);
  const space = cut.lastIndexOf(" ");
  return (space > max * 0.6 ? cut.slice(0, space) : cut).trimEnd();
}

/** The chip beside a section title. One vocabulary, so palm and face render identically. */
export const STATUSES = [
  "Strong",
  "Balanced",
  "Deep",
  "Developing",
  "Clear",
  "Faint",
] as const;

/** What the user asked the reading to concentrate on. Shared by both features. */
export const FOCUS_KEYS = ["love", "career", "money", "personality", "life_path"] as const;
export type FocusKey = typeof FOCUS_KEYS[number];

export const FOCUS_LABELS: Record<FocusKey, string> = {
  love: "Love & Relationships",
  career: "Career & Purpose",
  money: "Money & Abundance",
  personality: "Personality & Strengths",
  life_path: "Life Path",
};

/**
 * No health option, deliberately, in either feature: offering one would steer the model straight
 * at the claims [BOUNDARIES] forbids, and would put a health claim in an app store listing.
 */
export function parseFocus(raw: unknown): FocusKey {
  return FOCUS_KEYS.includes(raw as FocusKey) ? raw as FocusKey : "life_path";
}

/** True when the model echoed a focus other than the one asked for. Logged, never surfaced. */
export function focusMismatch(raw: unknown, focus: FocusKey): boolean {
  const echo = (raw as Record<string, unknown> | null)?.focus_echo;
  return typeof echo === "string" && echo !== focus;
}

/**
 * The two ceremonial lines every reading opens and closes with.
 *
 * Clamped hard: they sit in fixed-height cards on the results screen and are read aloud first
 * and last, where a rambling one is most noticeable.
 */
export function ceremony(root: Record<string, unknown>) {
  return {
    invocation: text(root.invocation, 200),
    blessing: text(root.blessing, 240),
  };
}
