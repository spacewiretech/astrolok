import { eachBounded, inBackground } from "../_shared/background.ts";
import { AppConfig, configSetting, loadConfig } from "../_shared/config.ts";
import { corsHeaders, json } from "../_shared/cors.ts";
import { isCronRequest } from "../_shared/cron_auth.ts";
import { serviceClient } from "../_shared/db.ts";
import { asKundaliRow } from "../_shared/kundali.ts";
import { generateKundaliReading } from "../_shared/kundali_generate.ts";
import { configureMixpanel } from "../_shared/mixpanel.ts";

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
 * A paid account's reading is normally started by `kundali` itself, the moment it is asked for;
 * this still picks it up if that attempt failed. The writing lives in `_shared/kundali_generate.ts`.
 */

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
    generateKundaliReading(db, config, row));

  // Claimed but never started: hand them straight back rather than waiting out the stale lock.
  if (done < rows.length) {
    const skipped = rows.slice(done).map((r) => r.id);
    await db.from("kundalis").update({ status: "queued", locked_at: null }).in("id", skipped);
  }

  console.log(`kundali-worker: ${done}/${rows.length} rows in ${Date.now() - startedAt}ms`);
}
