import { assert, assertEquals, assertFalse, assertRejects } from "jsr:@std/assert@1";

import {
  converse,
  GeminiError,
  geminiSettings,
  generateJson,
  jsonSchema,
  openRouterError,
  openRouterText,
  readImage,
} from "../_shared/gemini.ts";
import { PALM_SCHEMA } from "../_shared/palm_reading.ts";
import { FACE_SCHEMA } from "../_shared/face_reading.ts";
import { CHAT_SCHEMA } from "../_shared/astro_chat.ts";
import { CHAT_SCHEMA_V5 } from "../_shared/astro_chat_v5.ts";
import { kundaliSchema } from "../_shared/kundali_reading.ts";
import { computeKundaliChart, kundaliChartToJson } from "../_shared/kundali_chart.ts";

/**
 * The OpenRouter route: the same Gemini, reached through OpenRouter when `openrouter_use` is on.
 * What these pin down is that nothing a user reads can change with the flag — the same prompt,
 * the same schema in the same order, the same sampling, and the same errors for the same
 * failures, so the retry policy and the chat's crisis reply behave exactly as they do direct.
 */

const DIRECT = new Map([
  ["gemini_api_key", "google-key"],
  ["gemini_model", "gemini-3.5-flash"],
  ["gemini_model_fallback", "gemini-3.8-flash"],
]);

const ROUTED = new Map([...DIRECT, ["openrouter_use", "true"], ["openrouter_api_key", "or-key"]]);

// ---------------------------------------------------------------- settings

Deno.test("the flag picks the route, and the route keeps the configured model", () => {
  const direct = geminiSettings(DIRECT);
  assertEquals(direct, {
    provider: "gemini",
    apiKey: "google-key",
    model: "gemini-3.5-flash",
    fallbackModel: "gemini-3.8-flash",
  });

  // Anything but "true" leaves Google in charge.
  assertEquals(geminiSettings(new Map([...ROUTED, ["openrouter_use", "false"]])), direct);
  assertEquals(geminiSettings(new Map([...ROUTED, ["openrouter_use", "yes"]])), direct);

  // On: the same two models under OpenRouter's names, so the switch cannot change who answers.
  assertEquals(geminiSettings(ROUTED), {
    provider: "openrouter",
    apiKey: "or-key",
    model: "google/gemini-3.5-flash",
    fallbackModel: "google/gemini-3.8-flash",
  });
  assertEquals(
    geminiSettings(new Map([...ROUTED, ["openrouter_use", "TRUE"]])).provider,
    "openrouter",
  );
});

Deno.test("OpenRouter's own model rows override, and an empty fallback stays empty", () => {
  const chosen = geminiSettings(
    new Map([
      ...ROUTED,
      ["openrouter_model", "google/gemini-3.8-flash"],
      ["openrouter_model_fallback", "-"],
    ]),
  );
  assertEquals(chosen.model, "google/gemini-3.8-flash");
  // "-" is a placeholder, so the fallback is derived from Gemini's own row.
  assertEquals(chosen.fallbackModel, "google/gemini-3.8-flash");

  const none = geminiSettings(new Map([...ROUTED, ["gemini_model_fallback", ""]]));
  assertEquals(none.fallbackModel, "");

  // A Gemini row already written the OpenRouter way is not prefixed twice.
  assertEquals(
    geminiSettings(new Map([...ROUTED, ["gemini_model", "google/gemini-3.5-flash"]])).model,
    "google/gemini-3.5-flash",
  );
});

Deno.test("the OpenRouter key is read under either spelling, and never falls back to Google's", () => {
  assertEquals(
    geminiSettings(
      new Map([...DIRECT, ["openrouter_use", "true"], ["OPENROUTER_API_KEY", "upper"]]),
    )
      .apiKey,
    "upper",
  );
  assertEquals(
    geminiSettings(new Map([...ROUTED, ["OPENROUTER_API_KEY", "upper"]])).apiKey,
    "or-key",
  );

  // Sending Google's key to OpenRouter would only ever 401; empty fails closed with a log.
  assertEquals(geminiSettings(new Map([...DIRECT, ["openrouter_use", "true"]])).apiKey, "");
  assertEquals(
    geminiSettings(new Map([...ROUTED, ["openrouter_api_key", "tbd"]])).apiKey,
    "",
  );
});

// ---------------------------------------------------------------- the schema

const chart = kundaliChartToJson(
  computeKundaliChart({
    dob: "1990-01-01",
    birthTime: "12:00",
    utcOffsetSeconds: 19800,
    latitude: 28.6139,
    longitude: 77.209,
    asOf: new Date("2026-09-17T10:00:00Z"),
  })!,
);

const SCHEMAS: Record<string, unknown> = {
  palm: PALM_SCHEMA,
  face: FACE_SCHEMA,
  chat_v4: CHAT_SCHEMA,
  chat_v5: CHAT_SCHEMA_V5,
  kundali: kundaliSchema(chart),
};

/** Walks a Gemini schema and its translation side by side. */
function assertTranslated(gemini: unknown, json: unknown, path: string) {
  const from = gemini as Record<string, unknown>;
  const to = json as Record<string, unknown>;

  if (typeof from.type === "string") assertEquals(to.type, from.type.toLowerCase(), path);
  assertFalse("propertyOrdering" in to, `${path}: propertyOrdering left in`);

  for (const key of ["required", "enum", "minItems", "maxItems", "description", "format"]) {
    assertEquals(to[key], from[key], `${path}.${key}`);
  }

  if (from.items) assertTranslated(from.items, to.items, `${path}[]`);

  if (from.properties) {
    const properties = from.properties as Record<string, unknown>;
    const ordering = (from.propertyOrdering ?? []) as string[];
    const keys = Object.keys(to.properties as Record<string, unknown>);

    // The order the model writes in: what it sees before the prose that cites it.
    assertEquals(keys.slice(0, ordering.length), ordering, `${path}: order`);
    assertEquals(new Set(keys), new Set(Object.keys(properties)), `${path}: keys`);

    for (const key of keys) {
      assertTranslated(
        properties[key],
        (to.properties as Record<string, unknown>)[key],
        `${path}.${key}`,
      );
    }
  }
}

Deno.test("every schema crosses with its types, rules and property order intact", () => {
  for (const [name, schema] of Object.entries(SCHEMAS)) {
    const translated = jsonSchema(schema);
    assertTranslated(schema, translated, name);

    // No Gemini-only spelling survives anywhere in the tree.
    const text = JSON.stringify(translated);
    assertFalse(/"(OBJECT|STRING|ARRAY|BOOLEAN|INTEGER|NUMBER)"/.test(text), name);
    assertFalse(text.includes("propertyOrdering"), name);
  }

  // The load-bearing order from PALM_SCHEMA's comment: what is seen, before what is said.
  const palm = jsonSchema(PALM_SCHEMA) as { properties: Record<string, unknown> };
  assertEquals(Object.keys(palm.properties).slice(0, 3), ["is_palm", "reject_reason", "hand"]);
});

Deno.test("the translation does not touch the schema it was given", () => {
  const before = JSON.stringify(PALM_SCHEMA);
  jsonSchema(PALM_SCHEMA);
  assertEquals(JSON.stringify(PALM_SCHEMA), before);
});

Deno.test("a nullable field becomes a null type", () => {
  assertEquals(jsonSchema({ type: "STRING", nullable: true }), { type: ["string", "null"] });
});

// ---------------------------------------------------------------- the wire

interface Sent {
  url: string;
  headers: Record<string, string>;
  body: Record<string, any>;
}

/** Stubs `fetch` with a queue of replies, and records what was sent. */
async function capture(
  replies: Array<{ status?: number; body: unknown }>,
  run: () => Promise<unknown>,
): Promise<{ sent: Sent[]; result?: unknown; error?: unknown }> {
  const original = globalThis.fetch;
  const sent: Sent[] = [];
  globalThis.fetch = ((url: string, init: RequestInit) => {
    sent.push({
      url: String(url),
      headers: init.headers as Record<string, string>,
      body: JSON.parse(String(init.body)),
    });
    const reply = replies.shift() ?? { status: 500, body: {} };
    return Promise.resolve(
      new Response(JSON.stringify(reply.body), { status: reply.status ?? 200 }),
    );
  }) as typeof fetch;

  try {
    return { sent, result: await run() };
  } catch (error) {
    return { sent, error };
  } finally {
    globalThis.fetch = original;
  }
}

const gemini = (text: string) => ({
  candidates: [{ content: { parts: [{ text }] }, finishReason: "STOP" }],
});

const routed = (text: string, finish = "stop", native = "STOP") => ({
  choices: [{
    finish_reason: finish,
    native_finish_reason: native,
    message: { role: "assistant", content: text },
  }],
});

const HISTORY = [
  { role: "user" as const, text: "meri shaadi kab hogi?" },
  { role: "model" as const, text: '{"answer":"2027 ke pehle"}' },
];

Deno.test("a chat turn sends OpenRouter the same prompt, turns and sampling as Google", async () => {
  const chat = () => ({
    systemPrompt: "SYSTEM",
    schema: CHAT_SCHEMA_V5,
    history: HISTORY,
    userPrompt: "aur naukri?",
  });

  const direct = await capture(
    [{ body: gemini('{"answer":"a"}') }],
    () => converse(geminiSettings(DIRECT), chat()),
  );
  const viaOpenRouter = await capture(
    [{ body: routed('{"answer":"a"}') }],
    () => converse(geminiSettings(ROUTED), chat()),
  );

  const google = direct.sent[0].body;
  const [sent] = viaOpenRouter.sent;

  assertEquals(sent.url, "https://openrouter.ai/api/v1/chat/completions");
  assertEquals(sent.headers["Authorization"], "Bearer or-key");
  assertEquals(sent.body.model, "google/gemini-3.5-flash");

  // The system prompt first, then every turn in order, Gemini's `model` as `assistant`.
  assertEquals(sent.body.messages, [
    { role: "system", content: "SYSTEM" },
    { role: "user", content: "meri shaadi kab hogi?" },
    { role: "assistant", content: '{"answer":"2027 ke pehle"}' },
    { role: "user", content: "aur naukri?" },
  ]);
  assertEquals(google.systemInstruction.parts[0].text, "SYSTEM");

  // Sampling and the token cap, value for value.
  assertEquals(sent.body.temperature, google.generationConfig.temperature);
  assertEquals(sent.body.top_p, google.generationConfig.topP);
  assertEquals(sent.body.max_tokens, google.generationConfig.maxOutputTokens);

  // Structured output with the translated schema; the least thinking OpenRouter allows; and no
  // endpoint that would drop any of it.
  assertEquals(sent.body.response_format.type, "json_schema");
  assertEquals(sent.body.response_format.json_schema.strict, true);
  assertEquals(sent.body.response_format.json_schema.schema, jsonSchema(CHAT_SCHEMA_V5));
  assertEquals(sent.body.reasoning, { effort: "minimal", exclude: true });
  assertEquals(sent.body.provider.require_parameters, true);

  // The caller sees the same result either way, bar the model's name.
  assertEquals(
    (viaOpenRouter.result as { parsed: unknown }).parsed,
    (direct.result as { parsed: unknown }).parsed,
  );
  assertEquals((viaOpenRouter.result as { model: string }).model, "google/gemini-3.5-flash");
});

Deno.test("a photo still goes before the words, as a data URL", async () => {
  const { sent } = await capture(
    [{ body: routed('{"is_palm":true}') }],
    () =>
      readImage(geminiSettings(ROUTED), {
        imageBase64: "QUJD",
        mimeType: "image/jpeg",
        systemPrompt: "SYSTEM",
        userPrompt: "read this hand",
        schema: PALM_SCHEMA,
      }),
  );

  assertEquals(sent[0].body.messages[1], {
    role: "user",
    content: [
      { type: "image_url", image_url: { url: "data:image/jpeg;base64,QUJD" } },
      { type: "text", text: "read this hand" },
    ],
  });
  assertEquals(sent[0].body.max_tokens, 4096);
});

Deno.test("the kundali report keeps its larger budget", async () => {
  const { sent } = await capture(
    [{ body: routed('{"headline":"x"}') }],
    () =>
      generateJson(geminiSettings(ROUTED), {
        systemPrompt: "SYSTEM",
        userPrompt: "chart",
        schema: kundaliSchema(chart),
      }),
  );
  assertEquals(sent[0].body.max_tokens, 8192);
  assertEquals(sent[0].body.messages.length, 2);
});

// ---------------------------------------------------------------- the answer

Deno.test("the answer is read the way Gemini's is", () => {
  assertEquals(openRouterText("m", routed('{"a":1}')), '{"a":1}');

  // A fenced block would otherwise cost a retry.
  assertEquals(openRouterText("m", routed('```json\n{"a":1}\n```')), '{"a":1}');

  // Parts rather than a string.
  assertEquals(
    openRouterText("m", {
      choices: [{
        finish_reason: "stop",
        message: { content: [{ text: '{"a"' }, { text: ":1}" }] },
      }],
    }),
    '{"a":1}',
  );
});

/** The error a call raises, for asserting on. */
function raised(run: () => unknown): GeminiError {
  try {
    run();
  } catch (error) {
    assert(error instanceof GeminiError, String(error));
    return error;
  }
  throw new Error("expected a GeminiError");
}

Deno.test("a truncated answer is retried with a bigger cap, not parsed", () => {
  const cut = raised(() => openRouterText("m", routed('{"a":', "length", "MAX_TOKENS")));
  assert(cut.detail.startsWith("MAX_TOKENS"));

  // No native reason: the normalised one is read in Google's words.
  const bare = raised(() =>
    openRouterText("m", { choices: [{ finish_reason: "length", message: { content: '{"a":' } }] })
  );
  assert(bare.detail.startsWith("MAX_TOKENS"));
});

Deno.test("a filtered answer is a safety block, so chat gives its crisis-aware line", () => {
  assert(raised(() => openRouterText("m", routed("", "content_filter", "SAFETY"))).isSafetyBlock);
  assert(
    raised(() => openRouterText("m", routed("", "content_filter", "PROHIBITED_CONTENT")))
      .isSafetyBlock,
  );
  assert(
    raised(() =>
      openRouterText("m", {
        choices: [{ finish_reason: "content_filter", message: { content: "" } }],
      })
    ).isSafetyBlock,
  );

  // RECITATION is a stop Gemini treats as unreadable, and not as a safety block.
  const recited = raised(() => openRouterText("m", routed("{}", "stop", "RECITATION")));
  assertEquals(recited.detail, "finishReason RECITATION");
  assertFalse(recited.isSafetyBlock);
});

Deno.test("an empty answer is busy, and a failure inside a 200 keeps its code", () => {
  const empty = raised(() => openRouterText("m", routed("  ")));
  assert(empty.detail.startsWith("empty candidate"));
  assertEquals(empty.code, null);

  const midway = raised(() =>
    openRouterText("m", {
      error: {
        code: 502,
        message: "Provider disconnected",
        metadata: { error_type: "provider_unavailable" },
      },
    })
  );
  assertEquals(midway.code, 502);
  assert(midway.isTransient);

  const inChoice = raised(() =>
    openRouterText("m", {
      choices: [{ finish_reason: "error", error: { code: 429, message: "Rate limit exceeded" } }],
    })
  );
  assert(inChoice.isTransient);
});

Deno.test("OpenRouter's failures sort into Gemini's categories", () => {
  // Google's filter, reported as a 403: a safety block, never a key problem.
  const blocked = openRouterError("m", 403, {
    code: 403,
    message: "Content blocked",
    metadata: { error_type: "content_policy_violation", provider_name: "Google AI Studio" },
  });
  assert(blocked.isSafetyBlock);
  assertFalse(blocked.isConfigurationProblem);
  assertEquals(blocked.code, null);

  // Out of credits: the fix is in the account, and a retry only spends another call.
  const broke = openRouterError("m", 402, { message: "Insufficient credits" });
  assert(broke.isConfigurationProblem);
  assertFalse(broke.isTransient);
  assertEquals(broke.userMessage, raised(() => openRouterText("m", routed(""))).userMessage);

  for (const status of [400, 401, 404]) {
    assert(openRouterError("m", status, { message: "x" }).isConfigurationProblem, `${status}`);
  }
  const denied = openRouterError("m", 403, {
    message: "Key limit",
    metadata: { error_type: "permission_denied" },
  });
  assert(denied.isConfigurationProblem);
  assertFalse(denied.isSafetyBlock);

  // Overloads and timeouts earn the fallback model.
  for (const status of [408, 429, 500, 502, 503, 504]) {
    assert(openRouterError("m", status, { message: "x" }).isTransient, `${status}`);
  }

  // The log line carries the provider's own reason.
  assert(broke.detail.includes("Insufficient credits"));
});

// ---------------------------------------------------------------- the retry policy

Deno.test("an overload retries once on the fallback model", async () => {
  const { sent, result } = await capture(
    [
      { status: 429, body: { error: { code: 429, message: "Rate limit exceeded" } } },
      { body: routed('{"answer":"b"}') },
    ],
    () =>
      converse(geminiSettings(ROUTED), {
        systemPrompt: "S",
        schema: CHAT_SCHEMA_V5,
        history: [],
        userPrompt: "Q",
      }),
  );
  assertEquals(sent.map((call) => call.body.model), [
    "google/gemini-3.5-flash",
    "google/gemini-3.8-flash",
  ]);
  assertEquals((result as { model: string }).model, "google/gemini-3.8-flash");
});

Deno.test("a truncated chat reply retries with the bigger cap", async () => {
  const { sent } = await capture(
    [{ body: routed('{"answer":', "length", "MAX_TOKENS") }, { body: routed('{"answer":"c"}') }],
    () =>
      converse(geminiSettings(ROUTED), {
        systemPrompt: "S",
        schema: CHAT_SCHEMA_V5,
        history: [],
        userPrompt: "Q",
      }),
  );
  assertEquals(sent.map((call) => call.body.max_tokens), [1536, 2560]);
});

Deno.test("no credit and no key are not retried", async () => {
  const broke = await capture(
    [{ status: 402, body: { error: { code: 402, message: "Insufficient credits" } } }],
    () =>
      converse(geminiSettings(ROUTED), {
        systemPrompt: "S",
        schema: {},
        history: [],
        userPrompt: "Q",
      }),
  );
  assertEquals(broke.sent.length, 1);
  assert((broke.error as GeminiError).isConfigurationProblem);

  const keyless = new Map([...ROUTED, ["openrouter_api_key", ""]]);
  await assertRejects(
    () =>
      converse(geminiSettings(keyless), {
        systemPrompt: "S",
        schema: {},
        history: [],
        userPrompt: "Q",
      }),
    GeminiError,
    "openrouter_api_key is empty",
  );
});

Deno.test("a blocked chat turn still reaches the caller as a safety block", async () => {
  const block = {
    status: 403,
    body: {
      error: {
        code: 403,
        message: "Content blocked",
        metadata: { error_type: "content_policy_violation" },
      },
    },
  };
  // One more sample, as the direct route takes, then the block the caller answers.
  const { sent, error } = await capture(
    [block, block],
    () =>
      converse(geminiSettings(ROUTED), {
        systemPrompt: "S",
        schema: {},
        history: [],
        userPrompt: "Q",
      }),
  );
  assertEquals(sent.length, 2);
  assert((error as GeminiError).isSafetyBlock);
});

Deno.test("a key over its spending limit is an outage, never a bad photo", () => {
  // Verbatim from 30 Sep, when the key's $100 cap ran out.
  const capped = openRouterError("m", 403, {
    code: 403,
    message:
      "Key limit exceeded (total limit). Manage it using https://openrouter.ai/workspaces/default/keys/x",
  });
  assert(capped.isConfigurationProblem);
  assertFalse(capped.isSafetyBlock);
  assertEquals(capped.userMessage, openRouterError("m", 503, { message: "x" }).userMessage);
  assertEquals(
    openRouterError("m", 401, { message: "User not found." }).userMessage,
    capped.userMessage,
  );

  // A rejected request can still be the photo.
  const image = openRouterError("m", 400, {
    message: "x",
    metadata: { error_type: "invalid_image" },
  });
  assert(image.userMessage.includes("photo"));
});
