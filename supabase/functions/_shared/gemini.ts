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
 *
 * Two routes to the same model. Direct to Google, or through OpenRouter when `openrouter_use` is
 * true — the same Gemini, billed to a different account. Everything above the wire is shared:
 * the prompt, the schema, the sampling, the token caps and the retry policy, so switching the
 * flag changes who is paid and nothing a user reads. See "the OpenRouter call" below for how
 * each Gemini setting is carried across.
 */

import { AppConfig, configFlag, configSetting } from "./config.ts";

const BASE = "https://generativelanguage.googleapis.com/v1beta";
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

/** High enough that eight paragraphs do not read as eight copies of one paragraph. */
const TEMPERATURE = 0.85;
const TOP_P = 0.95;

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
    // 402 is money: Google's "prepayment credits are depleted", OpenRouter's out-of-credits.
    // Retrying it only spends a second failing call.
    return this.code !== null && [400, 401, 402, 403, 404].includes(this.code);
  }

  /** Overload or outage. Worth one attempt on the fallback model. */
  get isTransient(): boolean {
    // 408 is OpenRouter's provider timeout; Google does not send it.
    return this.code !== null && [408, 429, 500, 502, 503, 504].includes(this.code);
  }

  /**
   * The model's own safety filter refused — the prompt was blocked, or the answer was stopped.
   *
   * Separate from a failure because a chat turn has something better to say than "try again":
   * asking the same thing again is blocked again, and some of what trips the filter is someone
   * in distress. See `blockedReply` in `crisis.ts`.
   */
  get isSafetyBlock(): boolean {
    return this.detail.startsWith("prompt blocked") ||
      /finishReason (SAFETY|PROHIBITED_CONTENT|BLOCKLIST|SPII)/.test(this.detail);
  }
}

export interface GeminiSettings {
  /** Who the request goes to. The model is Gemini either way. */
  provider: "gemini" | "openrouter";
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
 * spellings have to be looked up explicitly rather than matched loosely. `openrouter_api_key` /
 * `OPENROUTER_API_KEY` likewise.
 *
 * With `openrouter_use` on, the models default to OpenRouter's names for the Gemini models
 * already configured — `gemini-3.5-flash` becomes `google/gemini-3.5-flash` — so flipping the flag
 * cannot quietly change which model answers. `openrouter_model` / `openrouter_model_fallback`
 * override that when a different model is wanted on purpose.
 */
export function geminiSettings(config: AppConfig): GeminiSettings {
  // Only a backstop for an empty config row; the value that actually ships lives in
  // `app_config` so a retired model is a dashboard edit rather than a redeploy. Not every
  // model accepts this request shape — see the notes in 0005_palm_models.sql before
  // changing either of these.
  const model = configSetting(config, "gemini_model") || "gemini-3.8-flash";
  const fallbackModel = configSetting(config, "gemini_model_fallback");

  if (configFlag(config, "openrouter_use")) {
    return {
      provider: "openrouter",
      apiKey: configSetting(config, "openrouter_api_key") ||
        configSetting(config, "OPENROUTER_API_KEY"),
      model: configSetting(config, "openrouter_model") || openRouterModel(model),
      fallbackModel: configSetting(config, "openrouter_model_fallback") ||
        (fallbackModel ? openRouterModel(fallbackModel) : ""),
    };
  }

  return {
    provider: "gemini",
    apiKey: configSetting(config, "gemini_api_key") || configSetting(config, "GEMINI_AI_KEY"),
    model,
    fallbackModel,
  };
}

/** OpenRouter names a model by its maker: `gemini-3.5-flash` is `google/gemini-3.5-flash`. */
function openRouterModel(geminiModel: string): string {
  return geminiModel.includes("/") ? geminiModel : `google/${geminiModel}`;
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
      busyStatus(response.status) ? BUSY : UNREADABLE,
      `${model} returned ${response.status}: ${detail.slice(0, 500)}`,
    );
  }

  return await response.json() as GeminiResponse;
}

/**
 * Failures that are the service's, not the photo's — so the user is not sent to retake a photo
 * that was fine. 402 included: credits running out is an outage from where the user stands.
 */
function busyStatus(status: number): boolean {
  return status === 402 || status === 408 || status === 429 || status >= 500;
}

/** One turn of a conversation. `model` is Gemini's name for its own side. */
export interface Turn {
  role: "user" | "model";
  text: string;
}

/** One part of a turn as Gemini's wire format spells it: text, or an inline photo. */
type Part =
  | { text: string }
  | { inline_data: { mime_type: string; data: string } };

/** One turn as sent. The OpenRouter route translates these rather than building its own. */
interface Content {
  role: "user" | "model";
  parts: Part[];
}

/**
 * The request body, given whatever `contents` the caller has assembled.
 *
 * Parameterised over `contents` rather than over an image, because that array is the only thing
 * a photo reading and a chat turn genuinely disagree about — everything below it is the same
 * generation config and the same safety settings.
 */
function requestBody(
  contents: Content[],
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
      temperature: TEMPERATURE,
      topP: TOP_P,
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

// ---------------------------------------------------------------- the OpenRouter call

/*
 * The same Gemini request in OpenRouter's OpenAI-shaped wire format. Every Gemini setting maps
 * one to one, because the point of this route is that nobody can tell which one answered:
 *
 * - `systemInstruction` → a `system` message, which OpenRouter hands Google as systemInstruction.
 * - `contents` → `messages`, `model` turns as `assistant`, the photo still before the text.
 * - `responseSchema` → `response_format` json_schema, translated by [jsonSchema].
 * - `temperature`, `topP`, `maxOutputTokens` → `temperature`, `top_p`, `max_tokens`.
 * - `thinkingBudget: 0` → `reasoning.effort: "minimal"`. OpenRouter lists these models as
 *   reasoning-mandatory and rejects a zero budget or `effort: "none"` with a 400, so minimal —
 *   Google's lowest thinking level — is the nearest it allows. `exclude` keeps any thoughts out
 *   of the response body.
 * - `provider.require_parameters` → only an endpoint that honours all of the above. Without it an
 *   endpoint that lacks, say, `temperature` (Vertex, for gemini-3.8-flash) still takes the request
 *   and silently drops the setting. AI Studio first: it is the service the direct route calls.
 * - `safetySettings` has no OpenRouter parameter. A block still comes back, as a 403 or a
 *   filtered finish, and [openRouterError] / [openRouterText] turn it into the same
 *   [GeminiError] the direct route raises, so the chat's crisis reply still fires.
 */

/**
 * Gemini's schema dialect as standard JSON Schema, which is what `response_format` takes.
 *
 * Types are lowercased (`OBJECT` → `object`), `nullable` becomes a `null` type, and
 * `propertyOrdering` becomes the order of the keys in `properties` — the order Gemini writes a
 * JSON Schema's properties in. That order is load-bearing (see `PALM_SCHEMA`), so it is carried
 * across rather than dropped. Everything else — `required`, `enum`, `minItems`, `maxItems` — is the
 * same keyword in both dialects and passes through untouched.
 */
export function jsonSchema(node: unknown): unknown {
  if (Array.isArray(node)) return node.map(jsonSchema);
  if (node === null || typeof node !== "object") return node;

  const { type, nullable, propertyOrdering, properties, items, anyOf, ...rest } = node as Record<
    string,
    unknown
  >;
  const out: Record<string, unknown> = {};

  if (typeof type === "string") {
    out.type = nullable === true ? [type.toLowerCase(), "null"] : type.toLowerCase();
  }
  Object.assign(out, rest);
  if (items !== undefined) out.items = jsonSchema(items);
  if (anyOf !== undefined) out.anyOf = jsonSchema(anyOf);

  if (properties !== null && typeof properties === "object") {
    const all = properties as Record<string, unknown>;
    const ordered = Array.isArray(propertyOrdering)
      ? propertyOrdering.filter((key): key is string => typeof key === "string" && key in all)
      : [];
    const keys = [...ordered, ...Object.keys(all).filter((key) => !ordered.includes(key))];
    out.properties = Object.fromEntries(keys.map((key) => [key, jsonSchema(all[key])]));
  }

  return out;
}

function openRouterMessages(systemPrompt: string, contents: Content[]) {
  return [
    { role: "system", content: systemPrompt },
    ...contents.map((turn) => ({
      role: turn.role === "model" ? "assistant" : "user",
      // Plain text as a string; a photo turn as parts, in the order Gemini would have seen them.
      content: turn.parts.every((part) => "text" in part)
        ? turn.parts.map((part) => "text" in part ? part.text : "").join("")
        : turn.parts.map((part) =>
          "text" in part ? { type: "text", text: part.text } : {
            type: "image_url",
            image_url: {
              url: `data:${part.inline_data.mime_type};base64,${part.inline_data.data}`,
            },
          }
        ),
    })),
  ];
}

/** [requestBody], for OpenRouter. */
export function openRouterBody(
  model: string,
  contents: Content[],
  systemPrompt: string,
  schema: unknown,
  maxOutputTokens: number,
) {
  return {
    model,
    messages: openRouterMessages(systemPrompt, contents),
    response_format: {
      type: "json_schema",
      json_schema: { name: "response", strict: true, schema: jsonSchema(schema) },
    },
    temperature: TEMPERATURE,
    top_p: TOP_P,
    max_tokens: maxOutputTokens,
    reasoning: { effort: "minimal", exclude: true },
    provider: { require_parameters: true, order: ["google-ai-studio"] },
  };
}

/** OpenRouter's error envelope, on a failed status or inside a 200. */
interface OpenRouterFailure {
  code?: number | string;
  message?: string;
  metadata?: { error_type?: string; provider_name?: string; raw?: unknown };
}

export interface OpenRouterResponse {
  choices?: Array<{
    finish_reason?: string | null;
    native_finish_reason?: string | null;
    message?: { content?: string | Array<{ text?: string }> | null };
    error?: OpenRouterFailure;
  }>;
  error?: OpenRouterFailure;
}

/** A failure from OpenRouter, as the [GeminiError] the direct route would have raised. */
export function openRouterError(
  model: string,
  status: number,
  failure: OpenRouterFailure | undefined,
  raw = "",
): GeminiError {
  const kind = failure?.metadata?.error_type ?? "";
  // The whole envelope, not just its message: `metadata.raw` is the provider's own reason.
  const body = failure ? JSON.stringify(failure) : raw;
  const detail = `${model} returned ${status}${kind ? ` ${kind}` : ""}: ${body.slice(0, 500)}`;

  // Google's safety filter, which OpenRouter reports as a 403. It is Gemini's `blockReason` in
  // other words — not a key problem, so it must not read as one: a chat turn answers it with the
  // crisis-aware line, and a 403 would have skipped that for an outage message.
  const filtered = kind === "content_policy_violation" || kind === "refusal" ||
    (status === 403 && /SAFETY|PROHIBITED_CONTENT|BLOCKLIST|SPII|blockReason/.test(body));
  if (filtered) return new GeminiError(null, UNREADABLE, `prompt blocked: ${detail}`);

  // Only a rejected request can be the photo's fault. A 401 or 403 is the key — its spending
  // limit ("Key limit exceeded", 30 Sep) most of all — and telling users to retake a good photo
  // sent them round a loop of retakes for as long as it lasted.
  const photoProblem = status === 400 || kind.includes("image");
  return new GeminiError(status, photoProblem ? UNREADABLE : BUSY, detail);
}

/** Google's own finish reasons. OpenRouter passes them on as `native_finish_reason`. */
const GOOGLE_FINISH_REASONS = new Set([
  "STOP",
  "MAX_TOKENS",
  "SAFETY",
  "RECITATION",
  "LANGUAGE",
  "OTHER",
  "BLOCKLIST",
  "PROHIBITED_CONTENT",
  "SPII",
  "IMAGE_SAFETY",
  "MALFORMED_FUNCTION_CALL",
  "FINISH_REASON_UNSPECIFIED",
]);

/** OpenRouter's normalised finish reasons, in Google's words. */
const NORMALISED_FINISH_REASONS: Record<string, string> = {
  stop: "STOP",
  length: "MAX_TOKENS",
  content_filter: "SAFETY",
};

/**
 * Why the answer ended, in the words [textFrom] checks. Google's own reason where OpenRouter
 * passed it on, since only that tells SAFETY from RECITATION; the normalised one otherwise.
 */
function openRouterFinishReason(
  choice: NonNullable<OpenRouterResponse["choices"]>[number] | undefined,
): string | undefined {
  const native = choice?.native_finish_reason?.trim().toUpperCase();
  if (native && GOOGLE_FINISH_REASONS.has(native)) return native;

  const normalised = choice?.finish_reason;
  if (!normalised) return undefined;
  return NORMALISED_FINISH_REASONS[normalised] ?? normalised.toUpperCase();
}

/** [textFrom], for OpenRouter: the same checks, in the same order, raising the same errors. */
export function openRouterText(model: string, response: OpenRouterResponse): string {
  // A 200 can still carry a failure: OpenRouter commits the status before the provider answers.
  if (response.error) {
    throw openRouterError(model, Number(response.error.code) || 502, response.error);
  }

  const choice = response.choices?.[0];
  if (choice?.error) throw openRouterError(model, Number(choice.error.code) || 502, choice.error);

  const reason = openRouterFinishReason(choice);

  if (reason && !["STOP", "MAX_TOKENS"].includes(reason)) {
    throw new GeminiError(null, UNREADABLE, `finishReason ${reason}`);
  }

  const content = choice?.message?.content;
  const text =
    (typeof content === "string"
      ? content
      : (content ?? []).map((part) => part.text ?? "").join(""))
      .trim()
      // Structured output comes back bare, but a fenced block costs a retry if it ever does not.
      .replace(/^```(?:json)?\s*/i, "")
      .replace(/\s*```$/, "");

  if (!text) throw new GeminiError(null, BUSY, `empty candidate (finishReason ${reason})`);

  if (reason === "MAX_TOKENS") {
    throw new GeminiError(null, BUSY, "MAX_TOKENS: response truncated", false);
  }

  return text;
}

/** [post], for OpenRouter. */
async function postOpenRouter(
  model: string,
  apiKey: string,
  body: unknown,
  timeoutMs: number,
): Promise<OpenRouterResponse> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  let status: number;
  let raw: string;
  try {
    const response = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    status = response.status;
    // Read inside the timeout, unlike [post]: OpenRouter can send its headers before the model
    // has answered, so the wait is in the body as often as before it.
    raw = await response.text();
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

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    parsed = null;
  }

  if (status < 200 || status > 299) {
    const failure = (parsed as { error?: OpenRouterFailure } | null)?.error;
    throw openRouterError(model, status, failure, raw);
  }

  if (parsed === null || typeof parsed !== "object") {
    throw new GeminiError(
      null,
      BUSY,
      `${model} returned ${status} with no JSON: ${raw.slice(0, 200)}`,
    );
  }

  return parsed as OpenRouterResponse;
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
 * A kundali report: a long structured document, written by the background worker.
 *
 * Nobody is watching a progress bar — the report is revealed a day later — so it gets the most
 * patience of the three: a larger token budget and a minute for the first attempt. The deadline
 * still has to fit inside the worker's own wall-clock budget, which is why the retry window is
 * bounded rather than open.
 */
const REPORT_BUDGET: Budget = {
  firstTokens: 8192,
  retryTokens: 12288,
  timeoutMs: 60_000,
  retryTimeoutMs: 45_000,
  retryDeadlineMs: 70_000,
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
  contents: Content[],
  systemPrompt: string,
  schema: unknown,
  budget: Budget,
): Promise<GeminiRawResult> {
  const viaOpenRouter = settings.provider === "openrouter";

  if (!settings.apiKey) {
    throw new GeminiError(
      null,
      "Readings are temporarily unavailable. Please try again later.",
      `${viaOpenRouter ? "openrouter_api_key" : "gemini_api_key"} is empty in app_config; ` +
        "paste it in from the dashboard",
      true,
    );
  }

  const startedAt = Date.now();

  // The only fork between the two routes. Everything around it — the retry, the fallback, the
  // parse — is shared, so they cannot drift apart.
  const attempt = async (model: string, maxTokens: number, timeoutMs: number) => {
    const text = viaOpenRouter
      ? openRouterText(
        model,
        await postOpenRouter(
          model,
          settings.apiKey,
          openRouterBody(model, contents, systemPrompt, schema, maxTokens),
          timeoutMs,
        ),
      )
      : textFrom(
        await post(
          model,
          settings.apiKey,
          requestBody(contents, systemPrompt, schema, maxTokens),
          timeoutMs,
        ),
      );
    return JSON.parse(text) as Record<string, unknown>;
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
      `${settings.provider} retry after ${elapsed}ms on ${model}`,
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
  const contents: Content[] = [{
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
  const contents: Content[] = [
    ...request.history.map((turn) => ({
      role: turn.role,
      parts: [{ text: turn.text }],
    })),
    { role: "user", parts: [{ text: request.userPrompt }] },
  ];

  return send(settings, contents, request.systemPrompt, request.schema, CHAT_BUDGET);
}

export interface DocumentRequest {
  systemPrompt: string;
  userPrompt: string;
  schema: unknown;
}

/** One structured document from text alone — no image, no history. The kundali report. */
export function generateJson(
  settings: GeminiSettings,
  request: DocumentRequest,
): Promise<GeminiRawResult> {
  const contents: Content[] = [{ role: "user", parts: [{ text: request.userPrompt }] }];
  return send(settings, contents, request.systemPrompt, request.schema, REPORT_BUDGET);
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
