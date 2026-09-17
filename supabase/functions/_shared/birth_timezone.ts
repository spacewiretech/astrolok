/**
 * The clock a birth time was read on.
 *
 * `jyotish.ts` assumes IST, which is right for today's India and wrong for plenty of Indian births:
 * the country ran on +6:30 through most of 1942–45, on Madras time (+5:21:10) before 1906, and
 * anyone born abroad was on a different clock altogether. The lagna moves a degree every four
 * minutes, so an hour of error is a different rising sign — a different kundali.
 *
 * The birth place gives an IANA zone (`Asia/Kolkata`), and the runtime's own tz database turns
 * that into the offset in force *at the moment of birth*. Deno ships full ICU data, so history is
 * included; `tests/birth_timezone_test.ts` pins the cases that matter.
 *
 * Offsets are in seconds, not minutes: the pre-1906 Indian zones are not whole minutes, and
 * rounding them would quietly move a lagna.
 */

export interface LocalDateTime {
  year: number;
  month: number; // 1-12
  day: number;
  hour: number;
  minute: number;
  second?: number;
}

/** True when the runtime recognises [id] as a time zone. */
export function isValidTimeZone(id: unknown): id is string {
  if (typeof id !== "string" || id.length === 0 || id.length > 64) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: id });
    return true;
  } catch {
    return false;
  }
}

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatterFor(timeZone: string): Intl.DateTimeFormat {
  let formatter = formatters.get(timeZone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      era: "short",
      year: "numeric",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
    });
    formatters.set(timeZone, formatter);
  }
  return formatter;
}

/**
 * Seconds east of UTC in force in [timeZone] at the instant [instantMs].
 *
 * Formats the instant as that zone's wall clock, reads the wall clock back as if it were UTC, and
 * the difference is the offset — exact to the second, whatever the zone's history.
 */
export function offsetSecondsAt(timeZone: string, instantMs: number): number {
  const parts = formatterFor(timeZone).formatToParts(new Date(instantMs));
  const read = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? NaN);

  let year = read("year");
  // `era` keeps years before 1 AD from reading as positive. No birth is that old; it is here so a
  // corrupt instant cannot come back as a plausible offset.
  if (parts.find((p) => p.type === "era")?.value === "BC") year = 1 - year;

  const wall = Date.UTC(year, read("month") - 1, read("day"), read("hour"), read("minute"), read("second"));
  const whole = Math.floor(instantMs / 1000) * 1000;
  return Math.round((wall - whole) / 1000);
}

/**
 * The UTC instant of a wall-clock time in [timeZone], and the offset that applied.
 *
 * Two awkward cases, both resolved the way calendar software resolves them:
 *   - a time that never happened (a DST gap) is read on the offset from before the jump, which
 *     lands it the length of the gap later;
 *   - a time that happened twice (the hour repeated when clocks go back) is the first of the two.
 *
 * Returns null for a date that does not exist (31 February) or a zone the runtime does not know.
 */
export function localToUtc(
  local: LocalDateTime,
  timeZone: string,
): { utcMs: number; offsetSeconds: number } | null {
  if (!isValidTimeZone(timeZone)) return null;

  const { year, month, day, hour, minute } = local;
  const second = local.second ?? 0;
  const wall = Date.UTC(year, month - 1, day, hour, minute, second);
  if (!Number.isFinite(wall)) return null;

  // Date.UTC rolls 31 Feb over into March; a birth date that rolled is not a birth date.
  const check = new Date(wall);
  if (
    check.getUTCFullYear() !== year || check.getUTCMonth() !== month - 1 ||
    check.getUTCDate() !== day || check.getUTCHours() !== hour || check.getUTCMinutes() !== minute
  ) {
    return null;
  }

  // Any transition near this wall time lies within a day of it, so the offsets a day either side
  // are the only two candidates.
  const day_ms = 86_400_000;
  const before = offsetSecondsAt(timeZone, wall - day_ms);
  const after = offsetSecondsAt(timeZone, wall + day_ms);

  const valid = [...new Set([before, after])]
    .map((offsetSeconds) => ({ offsetSeconds, utcMs: wall - offsetSeconds * 1000 }))
    .filter((c) => offsetSecondsAt(timeZone, c.utcMs) === c.offsetSeconds);

  if (valid.length === 0) {
    // The gap: nothing maps here. Read it on the earlier offset.
    return { offsetSeconds: before, utcMs: wall - before * 1000 };
  }

  // One candidate normally; two in an overlap, where the earlier instant is the first occurrence.
  valid.sort((a, b) => a.utcMs - b.utcMs);
  return valid[0];
}
