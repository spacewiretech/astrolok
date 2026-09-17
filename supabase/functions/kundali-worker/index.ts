import { eachBounded, inBackground } from "../_shared/background.ts";
import { resolveLanguage } from "../_shared/chat_language.ts";
import { AppConfig, configSetting, loadConfig } from "../_shared/config.ts";
import { corsHeaders, json } from "../_shared/cors.ts";
import { isCronRequest } from "../_shared/cron_auth.ts";
import { serviceClient } from "../_shared/db.ts";
import { asUserRow, graceHoursFrom, isEntitled, USER_COLUMNS } from "../_shared/entitlement.ts";
import { GeminiError, geminiSettings, generateJson } from "../_shared/gemini.ts";
import { asKundaliRow, KundaliRow, kundaliSettings, nextAttemptAt } from "../_shared/kundali.ts";
import {
  buildKundaliPrompt,
  KUNDALI_PROMPT_VERSION,
  kundaliSchema,
  kundaliSystemPrompt,
  normaliseKundaliReport,
} from "../_shared/kundali_reading.ts";
import { configureMixpanel, trackServer } from "../_shared/mixpanel.ts";
import { firstName } from "../_shared/person.ts";

type Db = ReturnType<typeof serviceClient>;

/**
 * Writes the readings for kundalis that are waiting for one. Called every five minutes by pg_cron
 * (`20260917000001_kundali.sql`), authenticated with `x-cron-secret`.
 *
 * Answers 202 at once and does the work after the response: pg_net gives up on a request long
 * before a batch of model calls finishes, and a timed-out cron call must not mean an abandoned
 * batch.
 *
 * Rows are claimed with `claim_due_kundalis`, which locks them with SKIP LOCKED — two overlapping
 * runs cannot write the same reading twice, and a run that died mid-row releases it after ten
 * minutes.
 *
 * Nothing here is user-facing, so a failure is simply retried with backoff until
 * `kundali_max_attempts`. The reveal time does not move: a reading that is late past its reveal
 * shows the app's "almost ready" state until it lands.
 */

/** A row that has sat unentitled this long is abandoned rather than written for nobody. */
const ABANDON_UNENTITLED_DAYS = 8;

/** Stop starting new rows after this, so the batch finishes inside the runtime's wall clock. */
const BATCH_BUDGET_MS = 90_000;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const db = serviceClient();
  const config = await loadConfig(db);
  if (!isCronRequest(req, config)) return new Response("forbidden", { status: 403, headers: corsHeaders });

  configureMixpanel(config, "kundali-worker");
  await inBackground("kundali-worker batch", runBatch(db, config));
  return json({ accepted: true }, 202);
});

async function runBatch(db: Db, config: AppConfig): Promise<void> {
  const startedAt = Date.now();
  const batch = Math.max(1, Math.min(10, Number(configSetting(config, "kundali_worker_batch") || "3") || 3));

  const { data, error } = await db.rpc("claim_due_kundalis", { p_limit: batch, p_stale_minutes: 10 });
  if (error) {
    console.error("kundali-worker: claim failed", error);
    return;
  }

  const rows = (Array.isArray(data) ? data : []).map(asKundaliRow);
  if (rows.length === 0) return;

  const done = await eachBounded(rows, { concurrency: 2, deadline: startedAt + BATCH_BUDGET_MS }, (row) =>
    generate(db, config, row));

  // Claimed but never started: hand them straight back rather than waiting out the stale lock.
  if (done < rows.length) {
    const skipped = rows.slice(done).map((r) => r.id);
    await db.from("kundalis").update({ status: "queued", locked_at: null }).in("id", skipped);
  }

  console.log(`kundali-worker: ${done}/${rows.length} rows in ${Date.now() - startedAt}ms`);
}

async function generate(db: Db, config: AppConfig, row: KundaliRow): Promise<void> {
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
