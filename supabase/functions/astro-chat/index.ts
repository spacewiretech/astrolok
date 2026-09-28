import {
  birthHourAsks,
  buildUserPrompt,
  CHAT_SCHEMA,
  chatSystemPrompt,
  effectiveVersion,
  normaliseChatReply,
  PROMPT_V3,
  PROMPT_V4,
  PROMPT_V5,
  promptVersion,
} from "../_shared/astro_chat.ts";
import {
  buildUserPromptV5,
  CHAT_SCHEMA_V5,
  chatSystemPromptV5,
  hasWholeChart,
  isRemedyAccept,
  kundaliLineFor,
  kundaliLineTurn,
  normaliseChatReplyV5,
  onTopicOptions,
  v5Body,
} from "../_shared/astro_chat_v5.ts";
import {
  correctionIntent,
  correctsOwnDate,
  parseDob,
  parseHour,
} from "../_shared/birth_details.ts";
import { readClock } from "../_shared/birth_time.ts";
import { detectLanguageSwitch, isMarathi, resolveLanguage } from "../_shared/chat_language.ts";
import { chatTiming } from "../_shared/chat_timing.ts";
import { transitTiming } from "../_shared/chat_transits.ts";
import { inBackground } from "../_shared/background.ts";
import { AppConfig, configSetting, loadConfig } from "../_shared/config.ts";
import {
  blockedReply,
  crisisLanguageFor,
  CrisisMatch,
  crisisReply,
  detectCrisis,
  fixedReplyBody,
} from "../_shared/crisis.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer, withinCap } from "../_shared/db.ts";
import {
  asUserRow,
  entitlementPayload,
  graceHoursFrom,
  isEntitled,
  USER_COLUMNS,
  UserRow,
} from "../_shared/entitlement.ts";
import { recastKundali } from "../_shared/kundali_recast.ts";
import { planFor } from "../_shared/pricing.ts";
import { converse, GeminiError, geminiSettings, Turn } from "../_shared/gemini.ts";
import { Chart, chartToJson, computeChart } from "../_shared/jyotish.ts";
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
const DEFAULT_RATE_AFTER = 5;

/**
 * How many turns and facts are read before `app_config` has said how many it wants — both are read
 * in the same round as it. Twice what it asks for today (20 and 50), so a dashboard edit has room;
 * past that the read is made again at the size asked (`withinCap`), so it is never cut short. A
 * thread longer than the window, one in twenty, costs twenty rows of transfer, not another hop.
 */
const HISTORY_READ_CAP = 40;
const FACTS_READ_CAP = 100;

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

  // A v5 turn is its messages, in the order they were sent. Its legacy fields repeat them.
  const bubbles = Array.isArray(row.body?.bubbles)
    ? (row.body.bubbles as unknown[]).filter((b): b is string => typeof b === "string" && b !== "")
    : [];
  if (bubbles.length > 0) return { role: "model", text: bubbles.join("\n") };

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

/** The value of the first of [keys] the memory holds, or null. */
function factValue(facts: Array<{ key: string; value: string }>, ...keys: string[]): string | null {
  for (const key of keys) {
    const fact = facts.find((entry) => entry.key === key);
    if (fact?.value.trim()) return fact.value;
  }
  return null;
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
  const authedAt = Date.now();

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

  // Absent on the first turn of a new chat. Never trusted as given — see findThread().
  const requestedThread = typeof body.thread_id === "string" ? body.thread_id.trim() : "";

  // ------------------------------------------------------------ safety
  //
  // Before every other check on purpose. Someone telling Astro they want to die must not be told
  // their message is too long, that their subscription has lapsed, or that today's questions are
  // used up — and must not wait on a model that can be blocked, time out, or answer with a
  // reading. The reply is fixed text, and no model is called.
  const crisis = detectCrisis(message);
  if (crisis) {
    return await answerCrisis(db, userId, requestedThread, message, crisis);
  }

  if (message.length > MAX_MESSAGE_CHARS) {
    return fail("invalid_request", "That message is a little long. Try asking it shorter.", 413);
  }

  // ------------------------------------------------------------ one round of reads
  //
  // Everything the guards and the prompt need, read at once. None of it waits on another part of
  // it — each read is keyed by the user id from the token or the thread id as sent — so the turn
  // waits on the slowest read rather than on the sum of them. These were six hops, one after
  // another, and with the sign-in before them and the question's write after they were most of the
  // wait outside the model: about 1.2 s a turn at normal load, and 10–30 s in the PostgREST surge of
  // 2026-09-25, when every hop queued for 1–3 s.
  //
  // Nothing in it writes, so a request refused below leaves nothing behind: the thread is opened
  // only once every guard has passed. The guards read the results in the order they always ran.
  const [
    config,
    { data: userRow, error: userError },
    flagged,
    { count, error: countError },
    found,
    historyRead,
    factsRead,
    { data: palmRow },
    { data: faceRow },
    feedbackRead,
  ] = await Promise.all([
    loadConfig(db),
    // With `chart`, the snapshot the sage was last given (`correctionBetween`). It was a read of
    // its own, allowed to fail while `20260915000001_chat_chart` had not run everywhere; it has.
    db.from("users").select(`${USER_COLUMNS}, chart`).eq("user_id", userId).single(),
    requestedThread ? recentlyFlagged(db, userId, requestedThread) : false,
    questionsToday(db, userId),
    requestedThread ? findThread(db, userId, requestedThread) : null,
    // Before `app_config` says how many turns it wants, so under a cap, and cut to size below.
    requestedThread ? readHistory(db, userId, requestedThread, HISTORY_READ_CAP) : [],
    readFacts(db, userId, FACTS_READ_CAP),
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
    // Allowed to fail. It reads a table added after the chat shipped, and a project whose
    // migration has not run yet must keep answering — it simply gets no rating card.
    db.from("chat_feedback").select("user_id").eq("user_id", userId).maybeSingle(),
  ]);

  if (userError || !userRow) {
    console.error("astro-chat: user lookup failed", userError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  // The snapshot kept apart, so `user` is the row every other function reads and nothing more.
  const { chart: snapshot, ...userColumns } = userRow as Record<string, unknown>;
  const user = asUserRow(userColumns);

  // A conversation where someone said they wanted to die, in the last day. Neither the paywall
  // nor the day's allowance stands between them and a reply while it lasts.
  if (!flagged && !isEntitled(user, graceHoursFrom(config))) {
    return fail("not_entitled", "Your subscription has ended. Renew to keep talking.", 402);
  }

  // ------------------------------------------------------------ quota
  //
  // A chat is unbounded in a way a reading is not: a reading is one call per photograph, but
  // nothing stops someone — or a modified client holding a valid token — sending messages all
  // day. Same shape as the readings' ceiling: a rolling 24 hours, and it fails closed.
  const limit = dailyLimit(config);

  if (countError) {
    console.error("astro-chat: quota check failed", countError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  if (!flagged && (count ?? 0) >= limit) {
    return fail(
      "limit_reached",
      `You've asked Astro all ${limit} questions for today. Come back tomorrow.`,
      429,
    );
  }

  // ------------------------------------------------------------ context
  //
  // Read *before* the user's turn is written, so the history is what came before this message
  // rather than including it — the message itself is sent separately, as the live prompt.
  //
  // Scoped to the thread, which is the entire point of threads: a question about work must not
  // arrive carrying last week's question about love. It was read beside the check on that thread
  // rather than after it — by `user_id` as well, and kept only if the check found the thread
  // theirs. An id that did not resolve gets a new thread below, and a new thread has no history.
  const historyTurns = positiveInt(config.get("chat_history_turns"), DEFAULT_HISTORY_TURNS);
  const factsMax = positiveInt(config.get("chat_facts_max"), DEFAULT_FACTS_MAX);

  const recentRows: HistoryRow[] = !found ? [] : withinCap(historyRead, {
    limit: historyTurns,
    cap: HISTORY_READ_CAP,
  }) ?? await readHistory(db, userId, found.id, historyTurns);

  // Newest-first from the query, oldest-first for the model.
  const history: Turn[] = recentRows
    .slice()
    .reverse()
    .map(asTurn)
    .filter((turn): turn is Turn => turn !== null);

  const facts = withinCap(factsRead, { limit: factsMax, cap: FACTS_READ_CAP }) ??
    await readFacts(db, userId, factsMax);

  // Which chat screen is asking: `chat_ui: 2` is the WhatsApp-style one, and only it gets v5.
  const chatUi = Number(body.chat_ui) || 1;
  const entry = typeof body.entry === "string" ? body.entry.trim() : "";
  const version = effectiveVersion(configSetting(config, "chat_prompt_version"), chatUi);
  const v4 = version === PROMPT_V4;
  const v5 = version === PROMPT_V5;

  const now = new Date();

  // v5: what they have typed or tapped in this thread, this message included. None of it is
  // offered back to them as a chip (`onTopicOptions`).
  const saidInThread = [
    message,
    ...recentRows.filter((row) => row.role === "user").map((row) => String(row.body?.text ?? "")),
  ];

  // v5: an accepted upay is served from the offer that already wrote it — no model call, and no
  // question used. Anything but a clear yes goes on as an ordinary turn.
  const lastAstro = recentRows.find((row) => row.role === "astro")?.body ?? null;
  if (v5 && found && lastAstro?.offer === "remedy" && isRemedyAccept(message)) {
    return await serveRemedy(db, {
      userId,
      thread: found,
      lastAstro,
      message,
      said: saidInThread,
      version,
      remaining: flagged ? Math.max(1, limit - (count ?? 0)) : Math.max(0, limit - (count ?? 0)),
      askRating: !flagged && await ratingDue(db, {
        feedback: feedbackRead,
        threadId: found.id,
        recent: recentRows,
        historyTurns,
        threshold: positiveInt(config.get("chat_rating_after_messages"), DEFAULT_RATE_AFTER),
      }),
    });
  }

  // v5: a birth detail Astro asked for is read from this reply and saved before the model is
  // called, so the answer it writes already comes from the corrected chart. What was on file
  // before it is kept, to tell whether this is the turn that completed the chart.
  const before = { dob: user.dob ?? "", birthTime: user.birth_time ?? null };
  const capture = v5 ? await captureBirthDetails(db, config, user, recentRows, message, now) : null;

  const chart = computeChart({
    dob: user.dob ?? "",
    birthTime: user.birth_time ?? null,
    // Only ever used to settle a day the Moon changed sign; see `BirthDetails.statedRashi`.
    statedRashi: factValue(facts, "rashi"),
    asOf: now,
  });

  // v4 answers "when" with a window computed from the dasha, and asks for the hour once. Both are
  // worked out here, in code, so neither is left to a model that does not see its own `ask_for`.
  const timing = v4 || v5 ? chatTiming(chart, { dob: user.dob, asOf: now, v5 }) : null;
  const hourAsks = v4 || v5 ? birthHourAsks(recentRows, message) : undefined;

  // v5: the season from Guru's transit over the Moon's rashi — the settled one, or a stated one
  // only where it settled a day the Moon changed sign (`computeChart`). The answer without the
  // hour; with it, the answer only for a matter whose dasha window is years off (`nearerSeasons`).
  const transits = v5 && chart ? transitTiming(chart.moonRashi, now) : null;

  // v5: once Astro has their whole chart it says so, and how the time ahead looks — in the first
  // reply, or in the turn whose captured detail completed the chart, once in a thread. Owed but
  // held back from a message about a death or an illness, it waits for their next question.
  const firstReply = !recentRows.some((row) => row.role === "astro");
  const completed = capture?.captured != null && !hasWholeChart(computeChart(before));
  const lineQuestion = capture?.captured?.question ?? message;
  const lineTurn = v5 &&
    kundaliLineTurn(recentRows, { chart, completed, care: flagged, question: lineQuestion });
  const kundaliLine = lineTurn
    ? kundaliLineFor(chart, {
      timing,
      transits,
      birthPlace: user.birth_place,
      question: lineQuestion,
    })
    : null;

  const previousChart = (snapshot ?? null) as Record<string, unknown> | null;
  const chartCorrection = correctionBetween(previousChart, chart);

  // A time they said without morning or night sits in the memory but never reached the chart.
  // Saying so is what gets it asked about, rather than read as settled.
  const statedTime = factValue(facts, "birth_time", "born_at");
  const unsettledBirthTime = capture?.unsettled ??
    (!user.birth_time && statedTime && readClock(statedTime).ambiguous ? statedTime : null);

  // ------------------------------------------------------------ the language
  //
  // Decided here rather than left to the prompt, which is where it used to be decided and where
  // it failed: someone set to Hinglish wrote in Devanagari, asked for Hindi in words, and got
  // Hinglish back for three turns. See `detectLanguageSwitch`.
  const settledLanguage = resolveLanguage(user.language, config);
  const switched = detectLanguageSwitch(message, config, { v5 });
  const language = switched?.language ?? settledLanguage;

  // ------------------------------------------------------------ the thread and the turn
  //
  // The thread is opened only now, after every guard, so a request that is refused does not leave
  // an empty conversation behind in the sidebar.
  //
  // The user's message is what counts a request that costs money against the day's allowance even
  // if it never comes back. Without that, a failure loop would be free and unbounded against a
  // metered API. It is written while the model answers rather than before — the model needs
  // neither its id nor the thread's, and the first turn of a new chat waited on both writes — but
  // no reply goes out without it: if either write fails, the reply is thrown away and the request
  // fails as it did when the writes came first.
  const asking = (found ? Promise.resolve(found) : openThread(db, userId))
    .then(async (thread) => {
      if (!thread) return null;
      const { data: pending, error } = await db
        .from("chat_messages")
        .insert({
          user_id: userId,
          thread_id: thread.id,
          role: "user",
          body: { text: message },
        })
        .select("id, created_at")
        .single();
      if (error || !pending) {
        console.error("astro-chat: could not record the question", error);
        return null;
      }
      return { thread, pending: pending as { id: string; created_at: string } };
    })
    // A write that throws rather than returning its error fails the turn the same way.
    .catch((error) => {
      console.error("astro-chat: could not record the question", error);
      return null;
    });

  // ------------------------------------------------------------ the model
  //
  // Started beside the writes above rather than after them. It fails where it always did — a
  // prompt that cannot be built, or a model that errs, is thrown from `await answering` in the
  // `try` below — but only once the question is known to have been written.
  const modelAt = Date.now();
  const answering = (async () => {
    const settings = geminiSettings(config);
    return await converse(settings, v5 ? {
      systemPrompt: chatSystemPromptV5({ language }),
      schema: CHAT_SCHEMA_V5,
      history,
      userPrompt: buildUserPromptV5(message, {
        name: firstName(user.name),
        age: ageFrom(user.dob),
        chart,
        timing,
        transits,
        statedRashi: factValue(facts, "rashi"),
        chartCorrection,
        unsettledBirthTime,
        birthHourAsks: hourAsks!,
        facts,
        palmSummary: summarise("palm", palmRow, "strongest_trait_title"),
        faceSummary: summarise("face", faceRow, "core_trait_title"),
        firstReply,
        remediesGiven: remediesGiven(recentRows),
        upaysOffered: upaysOffered(recentRows),
        hookGiven: hookGivenRecently(recentRows, now),
        planEnabled: configSetting(config, "chat_plan_3m_enabled").toLowerCase() === "true",
        care: flagged,
        appOpener: isAppOpener(entry, message) ? language : null,
        marathi: isMarathi(message) && switched?.language.toLowerCase() !== "marathi",
        captured: capture?.captured ?? null,
        captureFailed: capture?.failed ?? null,
        kundaliLine,
      }),
    } : {
      // Both from `app_config`, so the answer's shape and its language are dashboard edits rather
      // than deploys — `chat_prompt_version` is the rollback for the craft, and a language dropped
      // from `chat_languages` degrades this user to the default instead of to nothing.
      systemPrompt: chatSystemPrompt({ version, language }),
      schema: CHAT_SCHEMA,
      history,
      userPrompt: buildUserPrompt(message, {
        name: firstName(user.name),
        age: ageFrom(user.dob),
        chart,
        // Only v3 and v4 are told what a dasha is; a rollback to v2 must not be handed one.
        dasha: version === PROMPT_V3 || v4,
        version,
        ...(v4 ? { timing, birthHourAsks: hourAsks } : {}),
        statedRashi: factValue(facts, "rashi"),
        chartCorrection,
        unsettledBirthTime,
        birthPlace: user.birth_place,
        facts,
        palmSummary: summarise("palm", palmRow, "strongest_trait_title"),
        faceSummary: summarise("face", faceRow, "core_trait_title"),
        opening: history.length === 0,
      }),
    });
  })();

  // Both settled before either is looked at, and the write first: a question that could not be
  // counted fails the turn whatever the model said.
  const [written] = await Promise.all([asking, answering.catch(() => null)]);
  const answeredAt = Date.now();
  if (!written) {
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }
  const { thread, pending } = written;

  try {
    const result = await answering;

    const hourAsked = (hourAsks?.asked ?? 0) > 0 || (hourAsks?.declined ?? false);
    const replyV5 = v5
      ? normaliseChatReplyV5(result.parsed, {
        // A Marathi message is answered in Marathi whether or not the dashboard offers it, so the
        // yes chip and any top-up are Marathi too.
        language: isMarathi(message) ? "Marathi" : language,
        hourAsked,
        // The last reply's chips as well: one they passed over is not offered to them again.
        asked: [...saidInThread, ...strings(lastAstro?.options)],
        care: flagged,
      })
      : null;
    const reply = v5 ? null : normaliseChatReply(result.parsed);

    // v5: the model gave a helpline to words the crisis lists did not catch. From this turn on it
    // is a flagged conversation, as if `answerCrisis` had answered it.
    const cared = replyV5?.kind === "care";
    const guarded = flagged || cared;

    // Never the key, never the prompt, never what either of them said. A conversation with an
    // astrologer is about the most private thing this app holds. Written once the reply is
    // stored, so it can say how long each part of the turn took (`phases`).
    const logTurn = (storedAt: number | null) =>
      console.log(
        `astro-chat ${pending.id}: model=${result.model} latency=${result.latencyMs}ms ` +
          `thread=${thread.id} history=${history.length} facts=${facts.length} ` +
          `chart=${chart ? "yes" : "no"} version=${version} ui=${chatUi} language=${language} ` +
          `switch=${switched ? (switched.explicit ? "asked" : "script") : "-"} ` +
          `corrected=${chartCorrection ? "yes" : "no"} ` +
          (v4 || v5
            ? `timing=${timing ? "dasha" : transits ? "transit" : "no"} ` +
              `hour_asks=${hourAsks!.asked}${hourAsks!.declined ? "/declined" : ""} `
            : "") +
          (v5
            ? `kind=${replyV5?.kind ?? "-"} topic=${replyV5?.topic ?? "-"} ` +
              `bubbles=${replyV5?.bubbles.length ?? "-"} offer=${replyV5?.offer ?? "-"} ` +
              `captured=${capture?.captured?.field ?? capture?.failed ?? "-"} ` +
              `kundali=${
                kundaliLine ? (kundaliLine.hopeful ? "good" : "yog") : lineTurn ? "owed" : "-"
              } `
            : `sections=${reply?.sections.length ?? "-"} `) +
          `remembered=${(replyV5 ?? reply)?.remember.length ?? "-"} ` +
          phases({ startedAt, authedAt, modelAt, answeredAt, storedAt }),
      );

    if (!reply && !replyV5) {
      logTurn(null);
      return fail(
        "ai_unavailable",
        "That answer came back empty. Please ask again.",
        503,
      );
    }

    const stored: Record<string, unknown> = replyV5
      ? v5Body(replyV5, {
        version,
        // The hook rides in the upay turn, once a session — see `hookGivenRecently`.
        remedyHook: replyV5.offer === "remedy" && !hookGivenRecently(recentRows, now),
        kundaliLine: kundaliLine !== null,
        kundaliLineOwed: lineTurn && kundaliLine === null,
        saved: capture?.saved ?? null,
      })
      : {
        verdict: reply!.verdict,
        title_emoji: reply!.titleEmoji,
        title: reply!.title,
        opening: reply!.opening,
        sections: reply!.sections,
        options: reply!.options,
        ask_for: reply!.askFor,
        // Which prompt wrote it, so a rating is recorded against that and not the dashboard value.
        v: version,
      };
    const remembered = (replyV5 ?? reply)!.remember;
    const replyTitle = (replyV5 ?? reply)!.title;
    const preview = replyV5 ? replyV5.bubbles[0] : reply!.verdict || reply!.opening;

    // The reply is awaited — the next turn's history is read from it — and so is anything the
    // response reports, beside it rather than after it.
    const [{ data: saved, error: saveError }, savedLanguage, askRating] = await Promise.all([
      db
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
        .single(),
      // Saved only once the reply exists, so the setting never moves on a turn the person did not
      // see answered in the new language.
      switched && switched.language !== settledLanguage
        ? saveLanguage(db, userId, switched.language)
        : null,
      // Never in a conversation where someone said they wanted to die: a five-face card under that
      // would read as asking them to score it.
      !guarded && ratingDue(db, {
        feedback: feedbackRead,
        threadId: thread.id,
        recent: recentRows,
        historyTurns,
        threshold: positiveInt(config.get("chat_rating_after_messages"), DEFAULT_RATE_AFTER),
      }),
    ]);
    logTurn(Date.now());

    if (saveError) {
      // The reply is good and the user is waiting for it, so it is still returned. Only the
      // ability to see it again after a restart is lost, which is not worth failing over.
      console.error(`astro-chat ${pending.id}: could not save the reply`, saveError);
    }

    // Never their words for a care reply's thread: see [NEUTRAL_TITLE].
    const title = thread.title || (cared ? NEUTRAL_TITLE : threadTitleFrom(replyTitle, message));

    // Everything else waits for nothing: none of it is in the response, and each was already never
    // allowed to fail the request, so none of it is allowed to hold the reply up either. These
    // finish after the response has gone.
    await inBackground(
      "astro-chat after the reply",
      Promise.all([
        // What the sage learned. A reply the user can read matters more than a memory they will
        // not notice for another week.
        remembered.length > 0 ? rememberFacts(db, userId, remembered, config) : null,
        // Birth details are worth promoting out of the memory and onto the user, where the chart
        // reads them. Astro asks for these in conversation; this is where the answer lands. Not
        // in the response: its `user` is the row a captured detail was saved to, before this ran.
        promoteBirthDetails(db, userId, user, remembered),
        // What the sage was just given becomes what the next turn is compared against. After the
        // reply rather than before it, so a turn that failed owes the correction again next time.
        chart && !previousChart?.error && !sameChart(previousChart, chart)
          ? rememberChart(db, userId, chart)
          : null,
        // Names the thread, refreshes its one-line preview and moves it to the top of the
        // sidebar — which the app has already done for itself from the response (`noteTurn`).
        touchThread(db, thread.id, {
          title: thread.title ? null : title,
          preview,
        }),
        cared && !flagged
          ? flagHelplineReply(db, { userId, threadId: thread.id, messageId: pending.id, language })
          : null,
      ]),
    );

    // The upay waiting behind an offer stays on the server until they say yes.
    const { remedy_bubbles: _upay, remedy_hook: _hook, ...visible } = stored;

    return json({
      message: {
        id: saved?.id ?? null,
        created_at: saved?.created_at ?? new Date().toISOString(),
        role: "astro",
        ...visible,
      },
      ...(capture?.user ? { user: capture.user } : {}),
      asked: { id: pending.id, created_at: pending.created_at },
      thread: { id: thread.id, title },
      remaining: remainingAfter(limit, count, guarded),
      language,
      ...(savedLanguage ? { saved_language: savedLanguage } : {}),
      ask_rating: askRating,
    });
  } catch (error) {
    // The model's filter refused. Asking again is refused again, so rather than "try again" the
    // turn gets a fixed line in their language — one that keeps a helpline within reach without
    // assuming anything, because some of what trips the filter is someone in distress.
    if (error instanceof GeminiError && error.isSafetyBlock) {
      console.warn(`astro-chat ${pending.id}: safety block (${error.detail})`);
      const answered = await storeFixedReply(db, {
        userId,
        threadId: thread.id,
        bubbles: blockedReply(crisisLanguageFor(language)),
        version,
        threadTitle: thread.title,
      });
      return json({
        message: answered,
        asked: { id: pending.id, created_at: pending.created_at },
        thread: { id: thread.id, title: thread.title || NEUTRAL_TITLE },
        remaining: remainingAfter(limit, count, flagged),
        language,
        ask_rating: false,
      });
    }

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

/** A conversation, as a turn needs it. */
type Thread = { id: string; title: string };

/**
 * The conversation [requested] names, when it is this user's and not deleted — or null.
 *
 * The requested id is checked against `user_id` rather than trusted, and the user id comes from
 * the session token — so a request carrying somebody else's thread id does not read their
 * conversation into a prompt or write a turn into it. An id that does not resolve silently starts
 * a new thread rather than failing (`openThread`): the alternative is a user whose chat is broken
 * because a stale id survived a reinstall.
 */
async function findThread(
  db: ReturnType<typeof serviceClient>,
  userId: string,
  requested: string,
): Promise<Thread | null> {
  const { data } = await db
    .from("chat_threads")
    .select("id, title")
    .eq("id", requested)
    .eq("user_id", userId)
    .is("deleted_at", null)
    .maybeSingle();

  return data ? { id: data.id as string, title: (data.title as string) ?? "" } : null;
}

/** A new, empty conversation. Null only when the database refused, which the caller turns into a 500. */
async function openThread(
  db: ReturnType<typeof serviceClient>,
  userId: string,
): Promise<Thread | null> {
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

/** The conversation this turn belongs to, creating one when there is not one yet. */
async function resolveThread(
  db: ReturnType<typeof serviceClient>,
  userId: string,
  requested: string,
): Promise<Thread | null> {
  return (requested ? await findThread(db, userId, requested) : null) ?? await openThread(db, userId);
}

/**
 * A thread's newest [limit] turns, newest first — by `user_id` as well as the thread, because this
 * is read beside the check that the thread is theirs rather than after it. A failed read is no
 * history, as it always was.
 */
async function readHistory(
  db: ReturnType<typeof serviceClient>,
  userId: string,
  threadId: string,
  limit: number,
): Promise<HistoryRow[]> {
  const { data } = await db
    .from("chat_messages")
    .select("role, body, created_at")
    .eq("thread_id", threadId)
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(limit);
  return (data ?? []) as HistoryRow[];
}

/** The memory, most recently learned first. A failed read is no memory, as it always was. */
async function readFacts(
  db: ReturnType<typeof serviceClient>,
  userId: string,
  limit: number,
): Promise<Array<{ key: string; value: string }>> {
  const { data } = await db
    .from("user_facts")
    .select("key, value")
    .eq("user_id", userId)
    .order("updated_at", { ascending: false })
    .limit(limit);
  return (data ?? []) as Array<{ key: string; value: string }>;
}

/**
 * `phases=auth:110ms,reads:190ms,model:2400ms,store:90ms,total:2790ms` — where one turn's time
 * went, for the log line. Consecutive, so they add up to the total: `reads` is everything between
 * the session check and the model call (the round of reads, and a captured birth detail's write),
 * `model` is the model and the question's write together, whichever finished last, and `store` is
 * the reply's write. The model's own time is `latency` on the same line.
 */
function phases({ startedAt, authedAt, modelAt, answeredAt, storedAt }: {
  startedAt: number;
  authedAt: number;
  modelAt: number;
  answeredAt: number;
  storedAt: number | null;
}): string {
  const end = storedAt ?? answeredAt;
  return `phases=auth:${authedAt - startedAt}ms,reads:${modelAt - authedAt}ms,` +
    `model:${answeredAt - modelAt}ms,store:${storedAt === null ? "-" : `${storedAt - answeredAt}ms`},` +
    `total:${end - startedAt}ms`;
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
 * validation, and this one came out of a sentence. Which is exactly why an ambiguous time is not
 * promoted at all — see [readClock].
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
    const { time } = readClock(stated?.value);
    if (time) update.birth_time = time;
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
 * The correction the sage owes, when the Moon's rashi has moved since it was last given a chart.
 *
 * Only a sign that was named and is now a different sign. A chart that was UNCERTAIN before told
 * the sage not to name one, so there is nothing said to take back.
 */
function correctionBetween(
  previous: Record<string, unknown> | null,
  chart: Chart | null,
): { from: string; to: string } | null {
  const from = typeof previous?.moon_rashi === "string" ? previous.moon_rashi : null;
  const to = chart?.moonRashi ?? null;
  return from && to && from !== to ? { from, to } : null;
}

/** The fields a snapshot is compared on. Not a JSON string compare: `jsonb` reorders keys. */
const SNAPSHOT_FIELDS = [
  "moon_rashi",
  "sun_rashi",
  "nakshatra",
  "pada",
  "precise",
  "mahadasha",
  "antardasha",
] as const;

function sameChart(previous: Record<string, unknown> | null, chart: Chart): boolean {
  if (!previous) return false;
  const next = chartToJson(chart)!;
  return SNAPSHOT_FIELDS.every((field) => (previous[field] ?? null) === (next[field] ?? null));
}

/** Writes the snapshot. Never allowed to fail the request. */
async function rememberChart(
  db: ReturnType<typeof serviceClient>,
  userId: string,
  chart: Chart,
): Promise<void> {
  const { error } = await db.from("users").update({ chart: chartToJson(chart) }).eq(
    "user_id",
    userId,
  );
  if (error) console.error("astro-chat: could not save the chart snapshot", error);
}

/**
 * Stores a language this message switched to, and returns it — or null when the write failed,
 * so the app is not told about a setting that did not stick.
 *
 * The same column Profile's picker writes, through the same spelling rule: `detectLanguageSwitch`
 * only ever returns a name as the dashboard's list spells it.
 */
async function saveLanguage(
  db: ReturnType<typeof serviceClient>,
  userId: string,
  language: string,
): Promise<string | null> {
  const { error } = await db.from("users").update({ language }).eq("user_id", userId);
  if (error) {
    console.error("astro-chat: could not save the language", error);
    return null;
  }
  return language;
}

/**
 * Whether to ask this account, now, to rate the chat.
 *
 * Once per account, and only in a conversation that has reached [threshold] questions. A failed
 * lookup is a no: a card whose answer might not be saveable would come back on every reply.
 *
 * The history window already holds the conversation's recent turns, so the question count comes
 * from there without another query whenever the whole conversation fits in it.
 */
async function ratingDue(
  db: ReturnType<typeof serviceClient>,
  { feedback, threadId, recent, historyTurns, threshold }: {
    feedback: { data: unknown; error: unknown };
    threadId: string;
    recent: Array<{ role: string }>;
    historyTurns: number;
    threshold: number;
  },
): Promise<boolean> {
  if (feedback.error || feedback.data) return false;

  // Counted before this message was written, so this one is the +1.
  const asked = recent.filter((row) => row.role === "user").length + 1;
  if (asked >= threshold) return true;
  if (recent.length < historyTurns) return false;

  const { count, error } = await db
    .from("chat_messages")
    .select("id", { count: "exact", head: true })
    .eq("thread_id", threadId)
    .eq("role", "user");

  return !error && (count ?? 0) >= threshold;
}

// ---------------------------------------------------------------- safety

/**
 * What a conversation is called when the first thing in it was a crisis, or a turn the model
 * refused. Never the message: the sidebar would otherwise show someone's darkest sentence as a
 * title every time they opened it.
 */
const NEUTRAL_TITLE = "Astro";

/** The day's allowance, as `chat_messages_per_day` sets it. */
function dailyLimit(config: AppConfig): number {
  return positiveInt(config.get("chat_messages_per_day"), DEFAULT_PER_DAY);
}

/**
 * Questions asked in the last 24 hours that count against the allowance.
 *
 * `metered` is false on a turn that cost no model call — a crisis message and the fixed reply to
 * it — so reaching out in distress never uses up someone's questions.
 */
function questionsToday(db: ReturnType<typeof serviceClient>, userId: string) {
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  return db
    .from("chat_messages")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("role", "user")
    .eq("metered", true)
    .gte("created_at", since);
}

/**
 * Questions left after this turn, for the composer.
 *
 * Never zero in a conversation flagged in the last day: the app closes the composer at zero, and
 * someone who has just been given a helpline number must still be able to answer "you misread
 * me", or say more.
 */
function remainingAfter(limit: number, count: number | null, flagged: boolean): number {
  const left = Math.max(0, limit - (count ?? 0) - 1);
  return flagged ? Math.max(1, left) : left;
}

/** True when this thread had a crisis message in the last 24 hours. Fails open to false. */
async function recentlyFlagged(
  db: ReturnType<typeof serviceClient>,
  userId: string,
  threadId: string,
): Promise<boolean> {
  try {
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { data, error } = await db
      .from("chat_safety_flags")
      .select("id")
      .eq("user_id", userId)
      .eq("thread_id", threadId)
      .gte("created_at", since)
      .limit(1);
    return !error && (data?.length ?? 0) > 0;
  } catch {
    return false;
  }
}

/**
 * Stores one fixed Astro turn and returns it in the shape a reply is sent in.
 *
 * Never throws. A reply that could not be saved is still sent — the person is waiting for it,
 * and this is the one reply that matters most to arrive.
 */
async function storeFixedReply(
  db: ReturnType<typeof serviceClient>,
  { userId, threadId, bubbles, version, threadTitle }: {
    userId: string;
    threadId: string | null;
    bubbles: string[];
    version: string;
    threadTitle: string;
  },
): Promise<Record<string, unknown>> {
  const stored = fixedReplyBody(bubbles, { kind: "care", version });

  let saved: { id: string; created_at: string } | null = null;
  if (threadId) {
    try {
      const { data, error } = await db
        .from("chat_messages")
        .insert({ user_id: userId, thread_id: threadId, role: "astro", body: stored })
        .select("id, created_at")
        .single();
      if (error) console.error("astro-chat: could not save a fixed reply", error);
      saved = data ?? null;

      await touchThread(db, threadId, {
        title: threadTitle ? null : NEUTRAL_TITLE,
        preview: bubbles[0] ?? "",
      });
    } catch (error) {
      console.error("astro-chat: could not save a fixed reply", error);
    }
  }

  return {
    id: saved?.id ?? null,
    created_at: saved?.created_at ?? new Date().toISOString(),
    role: "astro",
    ...stored,
  };
}

/**
 * The turn for a message that says they want to die.
 *
 * Every step after the reply is composed is allowed to fail — no thread, no row, no flag — and
 * the reply is still returned. The flag is a record for a person to review, and a missing table
 * must never be the reason somebody did not see a helpline number.
 */
async function answerCrisis(
  db: ReturnType<typeof serviceClient>,
  userId: string,
  requestedThread: string,
  message: string,
  crisis: CrisisMatch,
): Promise<Response> {
  const bubbles = crisisReply(crisis.language);

  let config: AppConfig | null = null;
  try {
    config = await loadConfig(db);
  } catch {
    // The reply does not depend on config; only the version stamp and the count do.
  }
  const version = promptVersion(config ? configSetting(config, "chat_prompt_version") : "");

  const thread = await resolveThread(db, userId, requestedThread).catch(() => null);

  let asked: { id: string; created_at: string } | null = null;
  if (thread) {
    try {
      const { data, error } = await db
        .from("chat_messages")
        .insert({
          user_id: userId,
          thread_id: thread.id,
          role: "user",
          body: { text: message.slice(0, MAX_MESSAGE_CHARS) },
          metered: false,
        })
        .select("id, created_at")
        .single();
      if (error) console.error("astro-chat: could not record a crisis turn", error);
      asked = data ?? null;
    } catch (error) {
      console.error("astro-chat: could not record a crisis turn", error);
    }
  }

  const answered = await storeFixedReply(db, {
    userId,
    threadId: thread?.id ?? null,
    bubbles,
    version,
    threadTitle: thread?.title ?? "",
  });

  // For a person to review. Rule and language only — the words stay in the conversation, where
  // deleting the conversation deletes them.
  try {
    const { error } = await db.from("chat_safety_flags").insert({
      user_id: userId,
      thread_id: thread?.id ?? null,
      message_id: asked?.id ?? null,
      rule: crisis.rule,
      language: crisis.language,
    });
    if (error) console.error("astro-chat: could not flag a crisis turn", error);
  } catch (error) {
    console.error("astro-chat: could not flag a crisis turn", error);
  }

  // Deliberately without the rule, the language or anything else about the person.
  console.log(`astro-chat: crisis reply sent (thread=${thread?.id ?? "-"})`);

  // This turn cost nothing, so nothing is taken off — and never zero, which would close the
  // composer on someone who has just been handed a helpline number.
  let remaining: number | null = null;
  if (config) {
    const { count, error } = await questionsToday(db, userId);
    if (!error) remaining = Math.max(1, dailyLimit(config) - (count ?? 0));
  }

  return json({
    message: answered,
    asked: asked ?? { id: null, created_at: new Date().toISOString() },
    thread: thread
      ? { id: thread.id, title: thread.title || NEUTRAL_TITLE }
      : { id: requestedThread || null, title: NEUTRAL_TITLE },
    remaining,
    ask_rating: false,
  });
}

/**
 * Flags a conversation whose v5 reply gave a helpline to words the crisis lists did not catch.
 * From here it is flagged like one `answerCrisis` answered — the paywall and the allowance waived,
 * no rating card, no kundali line, the prompt's care block — and a person reviews it, which
 * is also how the lists learn what they missed. `rule` says the model saw it, not a list. Never
 * throws.
 */
async function flagHelplineReply(
  db: ReturnType<typeof serviceClient>,
  { userId, threadId, messageId, language }: {
    userId: string;
    threadId: string;
    messageId: string;
    language: string;
  },
): Promise<void> {
  try {
    const { error } = await db.from("chat_safety_flags").insert({
      user_id: userId,
      thread_id: threadId,
      message_id: messageId,
      rule: "model_reply",
      language: crisisLanguageFor(language),
    });
    if (error) console.error("astro-chat: could not flag a helpline reply", error);
  } catch (error) {
    console.error("astro-chat: could not flag a helpline reply", error);
  }
}

// ---------------------------------------------------------------- v5

/** One stored turn, as the history query reads it. */
type HistoryRow = { role: string; body: Record<string, unknown>; created_at?: string };

/** The non-empty strings of a stored list field — a row's `options`, say — or none. */
function strings(value: unknown): string[] {
  return (Array.isArray(value) ? value : [])
    .filter((entry): entry is string => typeof entry === "string" && entry !== "");
}

/** Topics whose upay was offered in the turns read and has not been served since. */
function upaysOffered(rows: HistoryRow[]): string[] {
  const given = new Set(remediesGiven(rows));
  const topics = rows
    .filter((row) => row.role === "astro" && row.body?.offer === "remedy")
    .map((row) => String(row.body?.topic ?? ""))
    .filter((topic) => topic !== "" && !given.has(topic));
  return [...new Set(topics)];
}

/** How long an invitation to come back holds: once in this long is "once a session". */
const HOOK_SESSION_MS = 12 * 60 * 60 * 1000;

/** Topics whose upay was already served in the turns read — so the same upay is not offered twice. */
function remediesGiven(rows: HistoryRow[]): string[] {
  const topics = rows
    .filter((row) => row.role === "astro" && row.body?.kind === "remedy")
    .map((row) => String(row.body?.topic ?? ""))
    .filter((topic) => topic !== "");
  return [...new Set(topics)];
}

/** Whether a turn in the last [HOOK_SESSION_MS] already invited them back. */
function hookGivenRecently(rows: HistoryRow[], now: Date): boolean {
  return rows.some((row) =>
    row.role === "astro" && row.body?.hook === true &&
    now.getTime() - Date.parse(row.created_at ?? "") < HOOK_SESSION_MS
  );
}

/**
 * The English sentences the app's own buttons send — a topic pill, "Ask Astro" under a reading.
 * They are not how the person writes, so the reply is in their chat language, not in English.
 */
const APP_OPENERS =
  /^(?:I want to know about my (?:love life|career)\.|What does the season ahead hold for me\?|I could use some guidance\.|Tell me more about (?:what my (?:palm|face) reading means|my .+ and what it means for me)\.|I just read my Kundali)/;

function isAppOpener(entry: string, message: string): boolean {
  return entry === "topic" || entry === "reading" || APP_OPENERS.test(message.trim());
}

/**
 * The upay turn, served from the offer that wrote it.
 *
 * No model call — the upay was written with the answer, in the same voice and against the same
 * chart — and the user turn is not metered: accepting what Astro offered should not use up a
 * question.
 */
async function serveRemedy(
  db: ReturnType<typeof serviceClient>,
  { userId, thread, lastAstro, message, said, version, remaining, askRating }: {
    userId: string;
    thread: { id: string; title: string };
    lastAstro: Record<string, unknown>;
    message: string;
    /** What they have typed or tapped in this thread, this yes included. */
    said: string[];
    version: string;
    remaining: number;
    askRating: boolean;
  },
): Promise<Response> {
  const bubbles = strings(lastAstro.remedy_bubbles);
  const topic = String(lastAstro.topic ?? "general");
  // The offer's own follow-ups, minus the yes that was just tapped — through the same guard they
  // were written under, which also holds an offer stored before that guard existed to it. Not
  // topped up: the offer's were, when it was written, and the row does not say in what language.
  const options = onTopicOptions(lastAstro.options, { topic, asked: said });

  const { data: asked } = await db.from("chat_messages")
    .insert({ user_id: userId, thread_id: thread.id, role: "user", body: { text: message }, metered: false })
    .select("id, created_at")
    .single();

  const stored = v5Body({
    kind: "remedy",
    topic,
    bubbles,
    offer: "none",
    options,
    askFor: "none",
  }, { version, hook: lastAstro.remedy_hook === true });

  const { data: saved, error } = await db.from("chat_messages")
    .insert({ user_id: userId, thread_id: thread.id, role: "astro", body: stored })
    .select("id, created_at")
    .single();
  if (error) console.error("astro-chat: could not save the upay turn", error);

  // After the response, as in an ordinary turn: nothing in it depends on the sidebar row.
  await inBackground(
    "astro-chat after the upay",
    touchThread(db, thread.id, { title: null, preview: bubbles[0] ?? "" }),
  );
  console.log(`astro-chat: upay served from the offer (thread=${thread.id})`);

  return json({
    message: {
      id: saved?.id ?? null,
      created_at: saved?.created_at ?? new Date().toISOString(),
      role: "astro",
      ...stored,
    },
    asked: asked ?? { id: null, created_at: new Date().toISOString() },
    thread: { id: thread.id, title: thread.title },
    remaining,
    ask_rating: askRating,
  });
}

const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

/** "1998-08-15" as "15 August 1998" — how it is said back to them. */
function spokenDate(dob: string): string {
  const [y, m, d] = dob.split("-").map(Number);
  return `${d} ${MONTH_NAMES[m - 1]} ${y}`;
}

/** "19:30" as "7:30 PM". */
function spokenTime(time: string): string {
  const [h, m] = time.split(":").map(Number);
  return `${h % 12 === 0 ? 12 : h % 12}:${String(m).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
}

interface Capture {
  captured?: { field: "dob" | "birth_time"; said: string; question: string | null };
  failed?: "dob" | "birth_time";
  /** A time said without morning or night — asked about, never guessed. */
  unsettled?: string;
  saved?: { field: string; from: string | null; to: string };
  /** The refreshed account, for the app to install the way Profile does. */
  user?: Record<string, unknown>;
}

/**
 * Reads a birth detail out of the reply to Astro asking for it, and saves it.
 *
 * - The hour fills a blank, or replaces a saved one only when they said the saved one is wrong.
 * - The date is only ever taken on a correction: DOB is required before anyone reaches the chat,
 *   so a date here always replaces one — and a date in a question about someone else is not
 *   theirs at all. What it replaced is stored on the reply (`saved.from`) so it can be undone.
 * - The date alone is also taken unasked, from a message that says the saved one is wrong and
 *   gives theirs (`correctsOwnDate`). Nothing else is ever read without Astro having asked.
 * - A reply with no date or time in it is not an answer to the question at all, and goes on as an
 *   ordinary turn.
 *
 * Mutates [user] so everything after this in the turn — the chart, the timing, the promotion of
 * remembered facts — works from what was just saved.
 */
async function captureBirthDetails(
  db: ReturnType<typeof serviceClient>,
  config: AppConfig,
  user: UserRow,
  rows: HistoryRow[],
  message: string,
  now: Date,
): Promise<Capture | null> {
  const lastAstro = rows.find((row) => row.role === "astro")?.body;
  // "Meri DOB galat save hai, sahi 3 January 2000 hai", before Astro could ask. Left to the model,
  // that was answered "note kar li hai" with nothing saved, and every window after it was wrong.
  const unasked = lastAstro?.ask_for !== "dob" && lastAstro?.ask_for !== "birth_time" &&
    correctsOwnDate(message);
  const asked = unasked ? "dob" : lastAstro?.ask_for;
  if (asked !== "dob" && asked !== "birth_time") return null;

  const userTurns = rows.filter((row) => row.role === "user")
    .map((row) => String(row.body?.text ?? ""));
  // Unasked, it answers nothing said before it: the question is whatever else this message asks.
  const question = unasked ? null : userTurns[0] || null;
  const intent = correctionIntent(message) || userTurns.slice(0, 2).some(correctionIntent);
  const hasDigits = /[\d०-९೦-೯௦-௯౦-౯൦-൯]/u
    .test(message);

  const update: { dob?: string; birth_time?: string } = {};
  let saved: Capture["saved"];
  let captured: Capture["captured"];

  if (asked === "dob") {
    const found = parseDob(message, now);
    // Nobody asked, so there is no "could not be read" to tell them — the model asks for it.
    if (!found) return hasDigits && !unasked ? { failed: "dob" } : null;
    if (!intent) return null;
    update.dob = found.dob;
    saved = { field: "dob", from: user.dob, to: found.dob };
    captured = { field: "dob", said: spokenDate(found.dob), question };
  }

  // Unasked, only the date: an hour in the same breath waits for Astro to ask for it.
  const hour = unasked ? { time: null, ambiguous: false } : parseHour(message, now);
  if (hour.time && (!user.birth_time || intent)) {
    update.birth_time = hour.time;
    if (asked === "birth_time") {
      saved = { field: "birth_time", from: user.birth_time ?? null, to: hour.time };
      captured = { field: "birth_time", said: spokenTime(hour.time), question };
    }
  } else if (asked === "birth_time") {
    if (hour.ambiguous) return { unsettled: message.slice(0, 40) };
    if (!hour.time) return hasDigits ? { failed: "birth_time" } : null;
    return null; // A time on file, and no word that it is wrong: left as it is.
  }

  if (Object.keys(update).length === 0 || !captured) return null;

  const { data: row, error } = await db.from("users").update(update).eq("user_id", user.user_id)
    .select(USER_COLUMNS).single();
  if (error || !row) {
    console.error("astro-chat: could not save the birth details", error);
    return null;
  }
  Object.assign(user, update);
  console.log(`astro-chat: ${Object.keys(update).join("+")} saved from the chat`);

  // The kundali follows, when there is one to re-cast — in the background, never awaited.
  await inBackground(
    "kundali recast",
    recastKundali(db, config, user, { dob: user.dob!, birthTime: user.birth_time ?? null }, now)
      .then((outcome) => console.log(`astro-chat: kundali after the correction: ${outcome}`)),
  );

  const refreshed = asUserRow(row);
  return {
    captured,
    saved,
    user: entitlementPayload(refreshed, graceHoursFrom(config), planFor(config, refreshed.plan_variant)),
  };
}
