import {
  buildUserPrompt,
  CHAT_SCHEMA,
  chatSystemPrompt,
  normaliseChatReply,
} from "../_shared/astro_chat.ts";
import { resolveLanguage } from "../_shared/chat_language.ts";
import { configSetting, loadConfig } from "../_shared/config.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer } from "../_shared/db.ts";
import {
  asUserRow,
  graceHoursFrom,
  isEntitled,
  USER_COLUMNS,
} from "../_shared/entitlement.ts";
import { converse, GeminiError, geminiSettings, Turn } from "../_shared/gemini.ts";
import { computeChart } from "../_shared/jyotish.ts";
import { ageFrom, firstName } from "../_shared/person.ts";

/**
 * One turn of a conversation with Astro.
 *
 * The same guard order as `face-reading`, and for the same reason: both endpoints spend money on
 * a metered API, and anyone auditing them should be able to see at a glance that neither has
 * quietly lost a defence the other has.
 *
 * What is different is what it does *after* the model answers. A reading is written once and
 * kept; a conversation accumulates. So this also persists both turns and upserts whatever the
 * sage learned, which is what makes the second conversation better than the first.
 *
 * The user id comes from the session token, never from the request body, so no request can read
 * another account's conversation or bill a turn to it.
 */

/** Long enough for a question, short enough that nobody pastes a novel into the prompt. */
const MAX_MESSAGE_CHARS = 2000;

/** Past this the function is close to Supabase's own ceiling; worth a line in the log. */
const DEADLINE_MS = 30_000;

/** Fallbacks, used only when a config row is empty or nonsense. */
const DEFAULT_PER_DAY = 40;
const DEFAULT_HISTORY_TURNS = 20;
const DEFAULT_FACTS_MAX = 50;

function positiveInt(raw: string | undefined, fallback: number): number {
  const value = Number(raw ?? "");
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : fallback;
}

/**
 * A stored turn, rendered as the model should see it.
 *
 * An Astro turn is stored as the structured reply, but the model wrote it as prose and reads it
 * back best as prose — so the pieces are flattened here rather than fed back as JSON.
 */
function asTurn(row: { role: string; body: Record<string, unknown> }): Turn | null {
  if (row.role === "user") {
    const said = typeof row.body?.text === "string" ? row.body.text : "";
    return said ? { role: "user", text: said } : null;
  }

  const parts: string[] = [];
  // Verdict first, matching how it was written and how it is read. Replaying the reasoning
  // without the answer it was reasoning toward would teach the model, turn by turn, that replies
  // begin with justification.
  const verdict = row.body?.verdict;
  const title = row.body?.title;
  const opening = row.body?.opening;
  if (typeof verdict === "string" && verdict) parts.push(verdict);
  if (typeof title === "string" && title) parts.push(title);
  if (typeof opening === "string" && opening) parts.push(opening);

  for (const entry of Array.isArray(row.body?.sections) ? row.body.sections : []) {
    const section = (entry ?? {}) as Record<string, unknown>;
    if (typeof section.heading === "string" && typeof section.body === "string") {
      parts.push(`${section.heading}: ${section.body}`);
    }
  }

  return parts.length > 0 ? { role: "model", text: parts.join("\n") } : null;
}

/** A sentence about the newest ready reading, for the sage to draw on. */
function summarise(
  kind: string,
  row: Record<string, unknown> | null,
  traitTitle: string,
): string | null {
  if (!row) return null;

  const headline = typeof row.headline === "string" ? row.headline : "";
  const trait = typeof row[traitTitle] === "string" ? row[traitTitle] as string : "";
  if (!headline && !trait) return null;

  return `Their ${kind} reading said: ${[headline, trait].filter((s) => s).join(" — ")}.`;
}

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  const startedAt = Date.now();
  const db = serviceClient();

  const userId = await userIdForBearer(db, req.headers.get("Authorization"));
  if (!userId) {
    return fail("unauthorized", "Please sign in again.", 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail("invalid_request", "Malformed request.", 400);
  }

  const message = typeof body.message === "string" ? body.message.trim() : "";
  if (!message) {
    return fail("invalid_request", "Say something to Astro first.", 400);
  }
  if (message.length > MAX_MESSAGE_CHARS) {
    return fail("invalid_request", "That message is a little long. Try asking it shorter.", 413);
  }

  // Absent on the first turn of a new chat. Never trusted as given — see resolveThread().
  const requestedThread = typeof body.thread_id === "string" ? body.thread_id.trim() : "";

  const config = await loadConfig(db);

  const { data: userRow, error: userError } = await db
    .from("users")
    .select(USER_COLUMNS)
    .eq("user_id", userId)
    .single();

  if (userError || !userRow) {
    console.error("astro-chat: user lookup failed", userError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  const user = asUserRow(userRow);
  if (!isEntitled(user, graceHoursFrom(config))) {
    return fail("not_entitled", "Your subscription has ended. Renew to keep talking.", 402);
  }

  // ------------------------------------------------------------ quota
  //
  // A chat is unbounded in a way a reading is not: a reading is one call per photograph, but
  // nothing stops someone — or a modified client holding a valid token — sending messages all
  // day. Same shape as the readings' ceiling: a rolling 24 hours, and it fails closed.
  const limit = positiveInt(config.get("chat_messages_per_day"), DEFAULT_PER_DAY);
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const { count, error: countError } = await db
    .from("chat_messages")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("role", "user")
    .gte("created_at", since);

  if (countError) {
    console.error("astro-chat: quota check failed", countError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  if ((count ?? 0) >= limit) {
    return fail(
      "limit_reached",
      `You've asked Astro all ${limit} questions for today. Come back tomorrow.`,
      429,
    );
  }

  // ------------------------------------------------------------ the thread
  //
  // After the quota check, so a request that is about to be refused does not leave an empty
  // conversation behind in the sidebar.
  const thread = await resolveThread(db, userId, requestedThread);
  if (!thread) {
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  // ------------------------------------------------------------ context
  //
  // Read *before* the user's turn is written, so the history is what came before this message
  // rather than including it — the message itself is sent separately, as the live prompt.
  //
  // Scoped to the thread, which is the entire point of threads: a question about work must not
  // arrive carrying last week's question about love.
  const historyTurns = positiveInt(config.get("chat_history_turns"), DEFAULT_HISTORY_TURNS);

  const [{ data: recent }, { data: factRows }, { data: palmRow }, { data: faceRow }] =
    await Promise.all([
      db.from("chat_messages")
        .select("role, body")
        .eq("thread_id", thread.id)
        .order("created_at", { ascending: false })
        .limit(historyTurns),
      db.from("user_facts")
        .select("key, value")
        .eq("user_id", userId)
        .order("updated_at", { ascending: false })
        .limit(positiveInt(config.get("chat_facts_max"), DEFAULT_FACTS_MAX)),
      db.from("palm_readings")
        .select("headline, strongest_trait_title")
        .eq("user_id", userId)
        .eq("status", "ready")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle(),
      db.from("face_readings")
        .select("headline, core_trait_title")
        .eq("user_id", userId)
        .eq("status", "ready")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle(),
    ]);

  // Newest-first from the query, oldest-first for the model.
  const history: Turn[] = (recent ?? [])
    .slice()
    .reverse()
    .map((row) => asTurn(row as { role: string; body: Record<string, unknown> }))
    .filter((turn): turn is Turn => turn !== null);

  const facts = (factRows ?? []) as Array<{ key: string; value: string }>;

  const chart = computeChart({
    dob: user.dob ?? "",
    birthTime: user.birth_time ?? null,
  });

  // ------------------------------------------------------------ the turn
  //
  // The user's message goes in before the model is called, so a request that costs money is
  // counted against the day's allowance even if it never comes back. Without that, a failure
  // loop would be free and unbounded against a metered API.
  const { data: pending, error: insertError } = await db
    .from("chat_messages")
    .insert({
      user_id: userId,
      thread_id: thread.id,
      role: "user",
      body: { text: message },
    })
    .select("id, created_at")
    .single();

  if (insertError || !pending) {
    console.error("astro-chat: could not record the question", insertError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  // Both from `app_config`, so the answer's shape and its language are dashboard edits rather
  // than deploys — `chat_prompt_version` is the rollback for the craft, and a language dropped
  // from `chat_languages` degrades this user to the default instead of to nothing.
  const language = resolveLanguage(user.language, config);

  try {
    const settings = geminiSettings(config);
    const result = await converse(settings, {
      systemPrompt: chatSystemPrompt({
        version: configSetting(config, "chat_prompt_version"),
        language,
      }),
      schema: CHAT_SCHEMA,
      history,
      userPrompt: buildUserPrompt(message, {
        name: firstName(user.name),
        age: ageFrom(user.dob),
        chart,
        birthPlace: user.birth_place,
        facts,
        palmSummary: summarise("palm", palmRow, "strongest_trait_title"),
        faceSummary: summarise("face", faceRow, "core_trait_title"),
        opening: history.length === 0,
      }),
    });

    const reply = normaliseChatReply(result.parsed);

    // Never the key, never the prompt, never what either of them said. A conversation with an
    // astrologer is about the most private thing this app holds.
    console.log(
      `astro-chat ${pending.id}: model=${result.model} latency=${result.latencyMs}ms ` +
        `thread=${thread.id} history=${history.length} facts=${facts.length} ` +
        `chart=${chart ? "yes" : "no"} language=${language} ` +
        `sections=${reply?.sections.length ?? "-"} remembered=${reply?.remember.length ?? "-"}`,
    );

    if (!reply) {
      return fail(
        "ai_unavailable",
        "That answer came back empty. Please ask again.",
        503,
      );
    }

    const stored = {
      verdict: reply.verdict,
      title_emoji: reply.titleEmoji,
      title: reply.title,
      opening: reply.opening,
      sections: reply.sections,
      options: reply.options,
      ask_for: reply.askFor,
    };

    const { data: saved, error: saveError } = await db
      .from("chat_messages")
      .insert({
        user_id: userId,
        thread_id: thread.id,
        role: "astro",
        body: stored,
        model: result.model,
        latency_ms: result.latencyMs,
      })
      .select("id, created_at")
      .single();

    if (saveError) {
      // The reply is good and the user is waiting for it, so it is still returned. Only the
      // ability to see it again after a restart is lost, which is not worth failing over.
      console.error(`astro-chat ${pending.id}: could not save the reply`, saveError);
    }

    // Facts last, and never allowed to fail the request: a reply the user can read matters more
    // than a memory they will not notice for another week.
    if (reply.remember.length > 0) {
      await rememberFacts(db, userId, reply.remember, config);
    }

    // Birth details are worth promoting out of the memory and onto the user, where the chart
    // reads them. Astro asks for these in conversation; this is where the answer lands.
    await promoteBirthDetails(db, userId, user, reply.remember);

    // Names the thread, refreshes its one-line preview and moves it to the top of the sidebar.
    // Like the facts above, never allowed to fail the request: a reply the user can read matters
    // more than a title.
    const title = thread.title || threadTitleFrom(reply.title, message);
    await touchThread(db, thread.id, {
      title: thread.title ? null : title,
      preview: reply.verdict || reply.opening,
    });

    return json({
      message: {
        id: saved?.id ?? null,
        created_at: saved?.created_at ?? new Date().toISOString(),
        role: "astro",
        ...stored,
      },
      asked: { id: pending.id, created_at: pending.created_at },
      thread: { id: thread.id, title },
      remaining: Math.max(0, limit - (count ?? 0) - 1),
    });
  } catch (error) {
    if (error instanceof GeminiError) {
      if (error.isConfigurationProblem) {
        console.error(`astro-chat ${pending.id}: configuration`, error.detail);
      } else {
        console.error(`astro-chat ${pending.id}: ${error.detail}`);
      }
      return fail("ai_unavailable", error.userMessage, 503);
    }

    console.error(
      `astro-chat ${pending.id}: failed after ${Date.now() - startedAt}ms`,
      error,
    );
    return fail(
      "ai_unavailable",
      "Astro is deep in thought right now. Please try again in a moment.",
      503,
    );
  } finally {
    if (Date.now() - startedAt > DEADLINE_MS) {
      console.warn(`astro-chat: ran ${Date.now() - startedAt}ms`);
    }
  }
});

/**
 * The conversation this turn belongs to, creating one when there is not one yet.
 *
 * The requested id is checked against `user_id` rather than trusted, and the user id comes from
 * the session token — so a request carrying somebody else's thread id does not read their
 * conversation into a prompt or write a turn into it. An id that does not resolve silently starts
 * a new thread rather than failing: the alternative is a user whose chat is broken because a
 * stale id survived a reinstall.
 *
 * Null only when the database refused, which the caller turns into a 500.
 */
async function resolveThread(
  db: ReturnType<typeof serviceClient>,
  userId: string,
  requested: string,
): Promise<{ id: string; title: string } | null> {
  if (requested) {
    const { data } = await db
      .from("chat_threads")
      .select("id, title")
      .eq("id", requested)
      .eq("user_id", userId)
      .is("deleted_at", null)
      .maybeSingle();

    if (data) return { id: data.id as string, title: (data.title as string) ?? "" };
  }

  const { data: created, error } = await db
    .from("chat_threads")
    .insert({ user_id: userId })
    .select("id, title")
    .single();

  if (error || !created) {
    console.error("astro-chat: could not open a thread", error);
    return null;
  }

  return { id: created.id as string, title: (created.title as string) ?? "" };
}

/** Longest a title may be, matching the column's own check. */
const MAX_TITLE_CHARS = 80;

/**
 * What to call a conversation, given the first reply to it.
 *
 * The model already writes a 2-5 word subject line for every reply — "Your Love Reading", "The
 * Season Ahead" — so a thread names itself from the first one and nobody is ever asked to name it.
 * The user's own words are the fallback, which is better than "New chat" and worse than a title,
 * because a question is usually longer than a name.
 */
function threadTitleFrom(replyTitle: string, message: string): string {
  const title = replyTitle.trim();
  if (title) return title.slice(0, MAX_TITLE_CHARS);

  const said = message.trim().replace(/\s+/g, " ");
  return said.length <= 60 ? said : `${said.slice(0, 59)}…`;
}

/** As much of the newest answer as the sidebar shows under a title. */
const MAX_PREVIEW_CHARS = 100;

/**
 * Moves the thread to the top of the sidebar, refreshes its preview, and names it if it has no
 * name yet.
 *
 * `title` is null when the thread already has one — a conversation is named once, by its opening
 * question, and re-titling it on every turn would make the sidebar rearrange itself under the
 * user's eyes. The preview, by contrast, is always the newest answer: that is what makes the
 * sidebar readable rather than a column of titles.
 */
async function touchThread(
  db: ReturnType<typeof serviceClient>,
  threadId: string,
  { title, preview }: { title: string | null; preview: string },
): Promise<void> {
  const { error } = await db
    .from("chat_threads")
    .update({
      last_message_at: new Date().toISOString(),
      preview: preview.trim().replace(/\s+/g, " ").slice(0, MAX_PREVIEW_CHARS),
      ...(title ? { title } : {}),
    })
    .eq("id", threadId);

  if (error) console.error("astro-chat: could not touch the thread", error);
}

/**
 * Upserts what the sage learned, then trims back to the cap.
 *
 * Upsert rather than insert, because the primary key is `(user_id, key)` — telling Astro you have
 * changed jobs must *correct* `works_as`, not leave two contradictory rows for the prompt to
 * choose between.
 */
async function rememberFacts(
  db: ReturnType<typeof serviceClient>,
  userId: string,
  facts: Array<{ key: string; value: string }>,
  config: Map<string, string>,
): Promise<void> {
  const { error } = await db
    .from("user_facts")
    .upsert(
      facts.map((fact) => ({
        user_id: userId,
        key: fact.key,
        value: fact.value,
        updated_at: new Date().toISOString(),
      })),
      { onConflict: "user_id,key" },
    );

  if (error) {
    console.error("astro-chat: could not save what was learned", error);
    return;
  }

  // The prompt carries every fact, so the cap is what keeps a long-running account from growing
  // an unbounded — and increasingly diluted — prompt.
  const max = positiveInt(config.get("chat_facts_max"), DEFAULT_FACTS_MAX);

  const { data: all } = await db
    .from("user_facts")
    .select("key")
    .eq("user_id", userId)
    .order("updated_at", { ascending: false });

  if (!all || all.length <= max) return;

  const stale = all.slice(max).map((row) => row.key as string);
  const { error: pruneError } = await db
    .from("user_facts")
    .delete()
    .eq("user_id", userId)
    .in("key", stale);

  if (pruneError) console.error("astro-chat: could not prune old facts", pruneError);
}

/**
 * Moves a birth time or place out of the loose memory and onto the user row.
 *
 * The sage is told to record what it hears, and the hour of birth is one of the things it asks
 * for — so it arrives as an ordinary fact. But the chart reads `users.birth_time`, not the
 * memory, and a birth hour sitting only in `user_facts` would be a thing the user answered and
 * the chart never saw.
 *
 * Only ever fills a blank. If a value is already on the row it stays: that one came through
 * validation, and this one came out of a sentence.
 */
async function promoteBirthDetails(
  db: ReturnType<typeof serviceClient>,
  userId: string,
  user: { birth_time?: string | null; birth_place?: string | null },
  facts: Array<{ key: string; value: string }>,
): Promise<void> {
  const update: Record<string, string> = {};

  if (!user.birth_time) {
    const stated = facts.find((f) => f.key === "birth_time" || f.key === "born_at");
    const clock = parseClock(stated?.value);
    if (clock) update.birth_time = clock;
  }

  if (!user.birth_place) {
    const stated = facts.find((f) => f.key === "birth_place" || f.key === "born_in");
    const place = stated?.value.trim();
    if (place && place.length <= 120) update.birth_place = place;
  }

  if (Object.keys(update).length === 0) return;

  const { error } = await db.from("users").update(update).eq("user_id", userId);
  if (error) console.error("astro-chat: could not save the birth details", error);
}

/**
 * A stated time to `HH:MM`, or null.
 *
 * Deliberately narrow. The sage is asked to record what it heard, and what it heard might be
 * "around sunrise" — which is not a time, and guessing one would put a wrong nakshatra in front
 * of the user with all the confidence of a computation.
 */
function parseClock(raw: string | undefined): string | null {
  const match = /(\d{1,2})[:.](\d{2})\s*(am|pm)?/i.exec(raw ?? "");
  if (!match) return null;

  let hours = Number(match[1]);
  const minutes = Number(match[2]);
  const meridiem = match[3]?.toLowerCase();

  if (minutes > 59) return null;
  if (meridiem === "pm" && hours < 12) hours += 12;
  if (meridiem === "am" && hours === 12) hours = 0;
  if (hours > 23) return null;

  return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}`;
}
