import { SupabaseClient } from "jsr:@supabase/supabase-js@2";

import { AppConfig, configSetting } from "./config.ts";
import { UserRow } from "./entitlement.ts";

/**
 * The trial allowance for readings: one palm reading and one face reading for as long as the ₹3
 * trial runs.
 *
 * Separate from the daily quota in `palm-reading` and `face-reading`, and counted differently. That
 * ceiling defends the Gemini bill against a looping client, so it counts every attempt. This is a
 * product rule — the trial is a taste of each reading — so it counts only readings the user
 * actually received: a photo that was not a palm, or a model that was down, costs nothing here.
 */

export type ReadingTable = "palm_readings" | "face_readings";

/** The `app_config` row holding each table's allowance. */
export const TRIAL_LIMIT_KEYS: Record<ReadingTable, string> = {
  palm_readings: "trial_palm_readings",
  face_readings: "trial_face_readings",
};

/**
 * How long a `pending` row still counts against the allowance.
 *
 * Past the functions' own 70-second deadline with room to spare, so two requests sent at the same
 * instant cannot both slip under the limit. Capped rather than unbounded, because a function killed
 * mid-request never moves its row out of `pending`, and that must not cost the user their reading.
 */
export const PENDING_HOLD_MS = 3 * 60 * 1000;

/** The allowance, falling back to one for a missing, placeholder or nonsensical row. */
export function trialReadingLimitFrom(config: AppConfig, key: string): number {
  const parsed = Math.floor(Number(configSetting(config, key)));
  return Number.isFinite(parsed) && parsed >= 1 ? parsed : 1;
}

/** What the user is told once the allowance is spent. */
export function trialLimitMessage(noun: "palm" | "face", limit: number): string {
  const times = limit === 1 ? "once" : `${limit} times`;
  return `Trial users can scan their ${noun} only ${times}. ` +
    "Please wait for your trial period to finish to scan again.";
}

/**
 * The PostgREST filter for the rows that count: every `ready` reading, and a `pending` one only
 * while it could still be in flight. `rejected` and `failed` are never named, so they never count.
 *
 * The timestamp is quoted because an ISO string carries characters PostgREST reserves.
 */
export function countedReadingsFilter(now: Date = new Date()): string {
  const pendingSince = new Date(now.getTime() - PENDING_HOLD_MS).toISOString();
  return `status.eq.ready,and(status.eq.pending,created_at.gte."${pendingSince}")`;
}

/**
 * Readings that count against [user]'s trial allowance.
 *
 * Throws when the count cannot be read, so the caller fails closed exactly as it does for the
 * daily quota.
 */
export async function trialReadingsUsed(
  db: SupabaseClient,
  table: ReadingTable,
  user: Pick<UserRow, "user_id" | "trial_started_at">,
  now: Date = new Date(),
): Promise<number> {
  let query = db
    .from(table)
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.user_id)
    .or(countedReadingsFilter(now));

  // This trial's readings only. `trial_started_at` is set when the mandate is authorised, so a null
  // is not expected on a `trial` row — and counting every reading instead gives the same answer,
  // because an account that was never entitled has none.
  if (user.trial_started_at) {
    query = query.gte("created_at", user.trial_started_at);
  }

  const { count, error } = await query;
  if (error) throw error;
  return count ?? 0;
}
