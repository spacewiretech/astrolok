/**
 * Writes one kundali's reading. Shared by `kundali-worker`, which works through the queue every five
 * minutes, and `kundali`, which starts a paid account's reading the moment it is asked for.
 *
 * A row reaches [generateKundaliReading] already claimed — `status = 'generating'` with its attempt
 * counted — either by `claim_due_kundalis` (the worker) or by [claimKundaliNow] (the request). Both
 * claims only take a row that is still `queued`, so the two callers never write the same reading
 * twice.
 *
 * Nothing here is user-facing, so a failure is simply retried with backoff until
 * `kundali_max_attempts`. The reveal time does not move: a reading that is late past its reveal
 * shows the app's "almost ready" state until it lands.
 */

import { resolveLanguage } from "./chat_language.ts";
import { AppConfig } from "./config.ts";
import { serviceClient } from "./db.ts";
import { asUserRow, graceHoursFrom, isEntitled, USER_COLUMNS } from "./entitlement.ts";
import { GeminiError, geminiSettings, generateJson } from "./gemini.ts";
import { asKundaliRow, KUNDALI_COLUMNS, KundaliRow, kundaliSettings, nextAttemptAt } from "./kundali.ts";
import {
  buildKundaliPrompt,
  KUNDALI_PROMPT_VERSION,
  kundaliSchema,
  kundaliSystemPrompt,
  normaliseKundaliReport,
} from "./kundali_reading.ts";
import { trackServer } from "./mixpanel.ts";
import { firstName } from "./person.ts";

type Db = ReturnType<typeof serviceClient>;

/** A row that has sat unentitled this long is abandoned rather than written for nobody. */
const ABANDON_UNENTITLED_DAYS = 8;

/**
 * Claims a queued row for writing straight away, outside the worker's schedule.
 *
 * One conditional UPDATE: it matches only while the row is still `queued`, so a worker run that
 * claimed it first (`claim_due_kundalis` locks with SKIP LOCKED) leaves nothing for this to take, and
 * this taking it first leaves nothing for the worker. Null when someone else has it.
 */
export async function claimKundaliNow(db: Db, row: KundaliRow): Promise<KundaliRow | null> {
  const { data, error } = await db.from("kundalis")
    .update({ status: "generating", locked_at: new Date().toISOString(), attempts: row.attempts + 1 })
    .eq("id", row.id)
    .eq("status", "queued")
    .is("superseded_at", null)
    .select(KUNDALI_COLUMNS)
    .maybeSingle();
  if (error) {
    console.error(`kundali ${row.id}: instant claim failed`, error);
    return null;
  }
  return data ? asKundaliRow(data) : null;
}

/** Claims [row] and writes its reading, for a request that should not wait for the worker. */
export async function generateKundaliNow(db: Db, config: AppConfig, row: KundaliRow): Promise<void> {
  const claimed = await claimKundaliNow(db, row);
  if (claimed) await generateKundaliReading(db, config, claimed);
}

export async function generateKundaliReading(db: Db, config: AppConfig, row: KundaliRow): Promise<void> {
  const settings = kundaliSettings(config);
  const now = new Date();
  const compactId = row.id.replace(/-/g, "");

  const { data: userRow, error: userError } = await db
    .from("users")
    .select(USER_COLUMNS)
    .eq("user_id", row.user_id)
    .single();
  if (userError || !userRow) {
    console.error(`kundali ${row.id}: user lookup failed`, userError);
    await release(db, row, now, "user lookup failed", settings.maxAttempts);
    return;
  }
  const user = asUserRow(userRow);

  // A lapsed account is not written for yet — the model call costs money — but it is not given up
  // on straight away either: a renewal the next day should still find its reading coming.
  if (!isEntitled(user, graceHoursFrom(config), now)) {
    const ageDays = (now.getTime() - Date.parse(row.requested_at)) / 86_400_000;
    if (ageDays > ABANDON_UNENTITLED_DAYS) {
      await db.from("kundalis").update({ status: "failed", locked_at: null, last_error: "not_entitled" })
        .eq("id", row.id);
    } else {
      await db.from("kundalis").update({
        status: "queued",
        locked_at: null,
        // The claim counted an attempt; waiting on a renewal is not one.
        attempts: Math.max(0, row.attempts - 1),
        next_attempt_at: new Date(now.getTime() + 6 * 3600_000).toISOString(),
      }).eq("id", row.id);
    }
    return;
  }

  const language = resolveLanguage(user.language, config);

  try {
    const result = await generateJson(geminiSettings(config), {
      systemPrompt: kundaliSystemPrompt(language),
      userPrompt: buildKundaliPrompt(row.chart, { firstName: firstName(user.name) }),
      schema: kundaliSchema(row.chart),
    });

    const normalised = normaliseKundaliReport(result.parsed, row.chart);
    if (!normalised.usable) {
      throw new Error(`unusable report: ${normalised.problems.join("; ")}`);
    }

    const generatedAt = new Date();
    const { error } = await db.from("kundalis").update({
      status: "ready",
      report: normalised.report,
      language,
      model: result.model,
      latency_ms: result.latencyMs,
      prompt_version: KUNDALI_PROMPT_VERSION,
      generated_at: generatedAt.toISOString(),
      locked_at: null,
      last_error: normalised.problems.length ? normalised.problems.join("; ").slice(0, 500) : null,
    }).eq("id", row.id).is("superseded_at", null);

    if (error) throw new Error(`could not save: ${error.message}`);

    console.log(
      `kundali ${row.id}: ready model=${result.model} latency=${result.latencyMs}ms attempts=${row.attempts} ` +
        `problems=${normalised.problems.length}`,
    );

    await trackServer({
      event: "Kundali Generated",
      distinctId: row.user_id,
      insertId: `kg:${compactId}`,
      properties: {
        kundali_id: row.id,
        model: result.model,
        latency_ms: result.latencyMs,
        attempts: row.attempts,
        language,
        prompt_version: KUNDALI_PROMPT_VERSION,
        minutes_after_request: Math.round((generatedAt.getTime() - Date.parse(row.requested_at)) / 60_000),
        minutes_before_unlock: Math.round((Date.parse(row.unlock_at) - generatedAt.getTime()) / 60_000),
        // No wait between the request and the reveal: a paid account, which is shown the reading as
        // soon as it is written.
        instant: Date.parse(row.unlock_at) - Date.parse(row.requested_at) < 60_000,
        problem_count: normalised.problems.length,
      },
    });
  } catch (error) {
    const detail = error instanceof GeminiError ? error.detail : String(error);
    if (error instanceof GeminiError && error.isConfigurationProblem) {
      console.error(`kundali ${row.id}: configuration`, detail);
    } else {
      console.error(`kundali ${row.id}: attempt ${row.attempts} failed`, detail);
    }
    await release(db, row, now, detail, settings.maxAttempts);
  }
}

/** Back to the queue with backoff, or to `failed` once the attempts are spent. */
async function release(db: Db, row: KundaliRow, now: Date, detail: string, maxAttempts: number) {
  const terminal = row.attempts >= maxAttempts;
  await db.from("kundalis").update({
    status: terminal ? "failed" : "queued",
    locked_at: null,
    last_error: detail.slice(0, 500),
    next_attempt_at: nextAttemptAt(row.attempts, now).toISOString(),
  }).eq("id", row.id);

  await trackServer({
    event: "Kundali Generation Failed",
    distinctId: row.user_id,
    insertId: `kf:${row.id.replace(/-/g, "")}:${row.attempts}`,
    properties: {
      kundali_id: row.id,
      attempt: row.attempts,
      terminal,
      error_class: detail.startsWith("unusable") ? "unusable" : detail.includes("MAX_TOKENS") ? "truncated" : "model",
    },
  });
}
