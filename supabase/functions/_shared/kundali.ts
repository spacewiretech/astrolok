/**
 * The kundali's lifecycle: what a request must contain, when the reading is revealed, and what the
 * app is allowed to see at each point.
 *
 * Pure, so the rule that matters most here is testable without a database: [kundaliPayload] is the
 * only thing that turns a `kundalis` row into a response, and it will not include the chart or the
 * report before `unlock_at`. The app's countdown is a courtesy; this is the lock.
 *
 * For a trial the reveal is deliberately a day after the request (`kundali_unlock_hours`), so the
 * user has a reason to come back. The report itself is written by `kundali-worker` a few minutes
 * after the request and held until then — which is why the copy the app shows says the reading is
 * *revealed* at a time, never that the calculation takes a day.
 *
 * A paying account does not wait: `unlock_at` is the request time and `kundali` starts the reading
 * straight away, so it is revealed as soon as it is written ([waitsForReveal]).
 */

import { AppConfig, configSetting } from "./config.ts";
import { isValidTimeZone, localToUtc } from "./birth_timezone.ts";
import { isInTrial, UserRow } from "./entitlement.ts";
import { KundaliChartJson } from "./kundali_chart.ts";
import { KundaliReport } from "./kundali_reading.ts";

export type KundaliStatus = "queued" | "generating" | "ready" | "failed";

/** What the app is told, derived from the row and the clock. */
export type KundaliState = "waiting" | "delayed" | "ready" | "failed";

export interface KundaliRow {
  id: string;
  user_id: string;
  status: KundaliStatus;
  dob: string;
  /** `HH:MM:SS`, as Postgres returns a `time`. */
  birth_time: string;
  birth_place: string;
  birth_place_id: string | null;
  /** Null once `purge_expired` has cleared coordinates older than Google's caching window. */
  birth_lat: number | null;
  birth_lng: number | null;
  birth_tz: string;
  utc_offset_seconds: number;
  chart: KundaliChartJson;
  report: KundaliReport | null;
  language: string | null;
  requested_at: string;
  unlock_at: string;
  generated_at: string | null;
  first_viewed_at: string | null;
  waiting_last_viewed_at: string | null;
  superseded_at: string | null;
  attempts: number;
}

export const KUNDALI_COLUMNS =
  "id, user_id, status, dob, birth_time, birth_place, birth_place_id, birth_lat, birth_lng, " +
  "birth_tz, utc_offset_seconds, chart, report, language, requested_at, unlock_at, generated_at, " +
  "first_viewed_at, waiting_last_viewed_at, superseded_at, attempts";

export function asKundaliRow(row: unknown): KundaliRow {
  return row as KundaliRow;
}

// ---------------------------------------------------------------- config

function positiveNumber(config: AppConfig, key: string, fallback: number): number {
  const parsed = Number(configSetting(config, key));
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

export interface KundaliSettings {
  unlockHours: number;
  generateDelayMinutes: number;
  maxRegenerations: number;
  maxAttempts: number;
  stageFractions: number[];
}

export const DEFAULT_STAGE_FRACTIONS = [0.02, 0.10, 0.55, 1];

export function kundaliSettings(config: AppConfig): KundaliSettings {
  return {
    unlockHours: positiveNumber(config, "kundali_unlock_hours", 24),
    generateDelayMinutes: positiveNumber(config, "kundali_generate_delay_minutes", 10),
    maxRegenerations: Math.floor(positiveNumber(config, "kundali_max_regenerations", 2)),
    maxAttempts: Math.max(1, Math.floor(positiveNumber(config, "kundali_max_attempts", 8))),
    stageFractions: parseStageFractions(configSetting(config, "kundali_stage_fractions")),
  };
}

/**
 * Four increasing fractions of the wait, the last one 1. Anything else falls back to the default,
 * because a typo in a dashboard cell must not tick every stage off in the first second.
 */
export function parseStageFractions(raw: string): number[] {
  const values = raw.split(",").map((part) => Number(part.trim()));
  const valid = values.length === 4 &&
    values.every((v) => Number.isFinite(v) && v > 0 && v <= 1) &&
    values.every((v, i) => i === 0 || v > values[i - 1]) &&
    values[3] === 1;
  return valid ? values : [...DEFAULT_STAGE_FRACTIONS];
}

// ---------------------------------------------------------------- the request

export interface KundaliPlace {
  placeId: string | null;
  label: string;
  latitude: number;
  longitude: number;
  timeZoneId: string;
}

export interface KundaliRequest {
  dob: string;
  /** `HH:MM`. */
  birthTime: string;
  place: KundaliPlace;
  utcOffsetSeconds: number;
  birthInstantMs: number;
}

const round4 = (n: number) => Math.round(n * 10_000) / 10_000;

/**
 * A request out of an untrusted body, or a message saying what is wrong with it.
 *
 * The coordinates come from the app, which got them from `place-search`. They are not re-fetched
 * here: a client that sends someone else's coordinates only miscasts its own chart.
 */
export function parseKundaliRequest(
  body: unknown,
  now: Date,
): { ok: true; value: KundaliRequest } | { ok: false; message: string } {
  const b = (typeof body === "object" && body !== null ? body : {}) as Record<string, unknown>;

  const dob = typeof b.dob === "string" ? b.dob.trim() : "";
  const dateParts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dob);
  if (!dateParts || dob < "1900-01-01") return { ok: false, message: "Please enter a valid date of birth." };

  const clock = /^([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?$/.exec(
    typeof b.birth_time === "string" ? b.birth_time.trim() : "",
  );
  if (!clock) return { ok: false, message: "Please enter your time of birth." };

  const p = (typeof b.place === "object" && b.place !== null ? b.place : {}) as Record<string, unknown>;
  const label = typeof p.label === "string" ? p.label.trim().replace(/\s+/g, " ") : "";
  const latitude = Number(p.lat);
  const longitude = Number(p.lng);
  const timeZoneId = typeof p.time_zone_id === "string" ? p.time_zone_id.trim() : "";
  const placeId = typeof p.place_id === "string" && p.place_id.trim().length > 0 &&
      p.place_id.trim().length <= 300
    ? p.place_id.trim()
    : null;

  if (
    !label || label.length > 120 ||
    typeof p.lat !== "number" || !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
    typeof p.lng !== "number" || !Number.isFinite(longitude) || longitude < -180 || longitude > 180 ||
    !isValidTimeZone(timeZoneId)
  ) {
    return { ok: false, message: "Please choose your birth place from the list." };
  }

  const instant = localToUtc({
    year: Number(dateParts[1]),
    month: Number(dateParts[2]),
    day: Number(dateParts[3]),
    hour: Number(clock[1]),
    minute: Number(clock[2]),
  }, timeZoneId);

  if (!instant) return { ok: false, message: "Please enter a valid date of birth." };
  if (instant.utcMs > now.getTime()) return { ok: false, message: "That birth time is in the future." };

  return {
    ok: true,
    value: {
      dob,
      birthTime: `${clock[1]}:${clock[2]}`,
      place: { placeId, label, latitude: round4(latitude), longitude: round4(longitude), timeZoneId },
      utcOffsetSeconds: instant.offsetSeconds,
      birthInstantMs: instant.utcMs,
    },
  };
}

/**
 * Whether a request is for the chart a row already holds — a double tap, or an unchanged "edit" —
 * so the endpoint can return it rather than spending a regeneration on nothing.
 */
export function sameBirthInputs(row: KundaliRow, request: KundaliRequest): boolean {
  if (row.dob !== request.dob) return false;
  if (row.birth_time.slice(0, 5) !== request.birthTime) return false;
  if (row.birth_tz !== request.place.timeZoneId) return false;

  if (row.birth_place_id && request.place.placeId) return row.birth_place_id === request.place.placeId;
  if (row.birth_lat === null || row.birth_lng === null) return row.birth_place === request.place.label;
  return Math.abs(row.birth_lat - request.place.latitude) < 0.01 &&
    Math.abs(row.birth_lng - request.place.longitude) < 0.01;
}

// ---------------------------------------------------------------- the clock

export const STAGE_KEYS = ["positions", "lagna", "dasha", "insights"] as const;

/** When each waiting-screen stage ticks off: a share of the wait, the last one at the reveal. */
export function stageTimeline(
  requestedAt: string,
  unlockAt: string,
  fractions: number[] = DEFAULT_STAGE_FRACTIONS,
): Array<{ key: typeof STAGE_KEYS[number]; completes_at: string }> {
  const start = Date.parse(requestedAt);
  const span = Math.max(0, Date.parse(unlockAt) - start);
  return STAGE_KEYS.map((key, i) => ({
    key,
    completes_at: new Date(start + span * (fractions[i] ?? 1)).toISOString(),
  }));
}

/** Retry backoff for a generation that failed: five minutes, doubling, never more than three hours. */
export function nextAttemptAt(attempts: number, now: Date): Date {
  const minutes = Math.min(5 * 2 ** Math.max(0, attempts - 1), 180);
  return new Date(now.getTime() + minutes * 60_000);
}

/**
 * Whether this account waits for the reveal. Only a trial does: the day between asking and seeing is
 * a reason to come back while someone is still deciding whether to stay. A paying account — `active`,
 * or `cancelled` with paid time left — is shown its reading the moment it is written.
 */
export function waitsForReveal(user: UserRow, graceHours: number, now: Date): boolean {
  return isInTrial(user, graceHours, now);
}

/** When a kundali asked for now is revealed: a day from now for a trial, straight away otherwise. */
export function unlockAtFor(waits: boolean, now: Date, unlockHours: number): Date {
  return waits ? new Date(now.getTime() + unlockHours * 3600_000) : new Date(now.getTime());
}

/**
 * Whether a live kundali's wait should end now: it was asked for during a trial, and the account has
 * paid since. Checked on every status and report call, so converting reveals it on the next look.
 */
export function shouldLiftLock(
  row: Pick<KundaliRow, "status" | "unlock_at" | "superseded_at">,
  waits: boolean,
  now: Date,
): boolean {
  return !waits && row.superseded_at === null && row.status !== "failed" &&
    now.getTime() < Date.parse(row.unlock_at);
}

export function kundaliState(row: Pick<KundaliRow, "status" | "unlock_at">, now: Date): KundaliState {
  if (row.status === "failed") return "failed";
  if (now.getTime() < Date.parse(row.unlock_at)) return "waiting";
  return row.status === "ready" ? "ready" : "delayed";
}

// ---------------------------------------------------------------- the response

export interface PayloadOptions {
  now: Date;
  entitled: boolean;
  includeReport: boolean;
  regenerationsLeft: number;
  unlockHours: number;
  stageFractions?: number[];
}

/**
 * A `kundalis` row as the app receives it. The only serializer — there is no other path from the
 * table to a response — so the lock lives here and nowhere else:
 *
 * the chart and the report are included only when the caller asked for them, is entitled, the
 * reveal time has passed, and the reading has actually been written.
 */
export function kundaliPayload(row: KundaliRow, options: PayloadOptions): Record<string, unknown> {
  const state = kundaliState(row, options.now);

  const payload: Record<string, unknown> = {
    id: row.id,
    state,
    requested_at: row.requested_at,
    unlock_at: row.unlock_at,
    server_now: options.now.toISOString(),
    unlock_hours: options.unlockHours,
    birth: {
      dob: row.dob,
      birth_time: row.birth_time.slice(0, 5),
      place_label: row.birth_place,
      place_id: row.birth_place_id,
      time_zone_id: row.birth_tz,
    },
    // The Moon's sign and nakshatra are shown straight away, as a taste of what is coming. Pure
    // arithmetic, not model text, so showing them early gives nothing of the reading away.
    teaser: {
      moon_rashi: row.chart?.moon?.rashi ?? null,
      moon_sign: row.chart?.moon?.sign ?? null,
      nakshatra: row.chart?.moon?.nakshatra ?? null,
      pada: row.chart?.moon?.pada ?? null,
    },
    stages: stageTimeline(row.requested_at, row.unlock_at, options.stageFractions),
    viewed: row.first_viewed_at !== null,
    regenerations_left: Math.max(0, options.regenerationsLeft),
  };

  if (options.includeReport && options.entitled && state === "ready" && row.report) {
    payload.chart = row.chart;
    payload.report = row.report;
    payload.language = row.language;
  }

  return payload;
}
