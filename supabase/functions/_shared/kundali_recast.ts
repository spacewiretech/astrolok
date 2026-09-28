/**
 * Re-casting the kundali after a birth detail is corrected in the chat.
 *
 * Chat v5 saves a corrected date or hour of birth told to Astro in conversation. The kundali is a
 * snapshot of the details it was cast from, and a snapshot of a wrong date would sit beside a
 * corrected chat for good — so the correction is carried over here, through the same
 * `replace_live_kundali` + `generateKundaliNow` path the Kundali screen's form uses in
 * `kundali/index.ts`, and under the same regeneration limit.
 *
 * Only when there is something to re-cast from: a live kundali whose place has coordinates. A
 * place typed in the chat is never geocoded, so without one there is nothing honest to compute a
 * lagna for, and the Kundali screen will cast it from its own form when the user next asks.
 *
 * Never throws. A re-cast that fails is logged; the chat turn it rode in on is not.
 */

import { inBackground } from "./background.ts";
import { localToUtc } from "./birth_timezone.ts";
import { AppConfig } from "./config.ts";
import { serviceClient } from "./db.ts";
import { graceHoursFrom, UserRow } from "./entitlement.ts";
import {
  asKundaliRow,
  KUNDALI_COLUMNS,
  kundaliSettings,
  unlockAtFor,
  waitsForReveal,
} from "./kundali.ts";
import { computeKundaliChart, kundaliChartToJson } from "./kundali_chart.ts";
import { generateKundaliNow } from "./kundali_generate.ts";

export type RecastOutcome = "recast" | "no_kundali" | "no_coordinates" | "limit" | "failed";

export async function recastKundali(
  db: ReturnType<typeof serviceClient>,
  config: AppConfig,
  user: UserRow,
  { dob, birthTime }: { dob: string; birthTime: string | null },
  now: Date,
): Promise<RecastOutcome> {
  try {
    const settings = kundaliSettings(config);

    const [liveResult, usedResult] = await Promise.all([
      db.from("kundalis").select(KUNDALI_COLUMNS).eq("user_id", user.user_id)
        .is("superseded_at", null).maybeSingle(),
      db.from("kundalis").select("id", { count: "exact", head: true }).eq("user_id", user.user_id)
        .not("superseded_at", "is", null),
    ]);
    if (liveResult.error || usedResult.error) return "failed";
    if (!liveResult.data) return "no_kundali";

    const live = asKundaliRow(liveResult.data);
    if (live.birth_lat === null || live.birth_lng === null || !live.birth_tz) {
      return "no_coordinates";
    }
    if (settings.maxRegenerations - (usedResult.count ?? 0) <= 0) return "limit";

    // A date corrected on its own keeps the hour the kundali already had.
    const time = (birthTime ?? live.birth_time ?? "").slice(0, 5);
    const [year, month, day] = dob.split("-").map(Number);
    const [hour, minute] = time.split(":").map(Number);
    if (![year, month, day, hour, minute].every(Number.isFinite)) return "failed";

    const utc = localToUtc({ year, month, day, hour, minute }, live.birth_tz);
    if (!utc) return "failed";

    const chart = computeKundaliChart({
      dob,
      birthTime: time,
      utcOffsetSeconds: utc.offsetSeconds,
      latitude: Number(live.birth_lat),
      longitude: Number(live.birth_lng),
      asOf: now,
    });
    if (!chart) return "failed";

    // A reading already revealed stays revealed: re-locking it for another day because a date was
    // corrected would punish the correction.
    const waits = waitsForReveal(user, graceHoursFrom(config), now);
    const revealed = Date.parse(live.unlock_at) <= now.getTime();
    const holds = waits && !revealed;

    const { data: inserted, error } = await db.rpc("replace_live_kundali", {
      p_user_id: user.user_id,
      p_row: {
        dob,
        birth_time: time,
        birth_place: live.birth_place,
        birth_place_id: live.birth_place_id,
        birth_lat: live.birth_lat,
        birth_lng: live.birth_lng,
        birth_tz: live.birth_tz,
        utc_offset_seconds: utc.offsetSeconds,
        chart: kundaliChartToJson(chart),
        unlock_at: (holds ? new Date(live.unlock_at) : unlockAtFor(false, now, 0)).toISOString(),
        next_attempt_at: (holds
          ? new Date(now.getTime() + settings.generateDelayMinutes * 60_000)
          : now).toISOString(),
      },
    });

    const row = Array.isArray(inserted) ? inserted[0] : inserted;
    if (error || !row) {
      console.error("kundali recast from chat: could not create", error);
      return "failed";
    }

    // Written in the background, never awaited: the chat turn has its own model call to make
    // inside the same thirty seconds.
    if (!holds) await inBackground("kundali recast", generateKundaliNow(db, config, asKundaliRow(row)));
    return "recast";
  } catch (error) {
    console.error("kundali recast from chat failed", error);
    return "failed";
  }
}
