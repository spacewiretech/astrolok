import { assertEquals } from "jsr:@std/assert@1";

import { isValidTimeZone, localToUtc, offsetSecondsAt } from "../_shared/birth_timezone.ts";

/**
 * India has not always been +5:30, and a kundali computed on the wrong clock has the wrong lagna.
 * These pin the history the runtime's tz database must carry for the charts to be right.
 */

Deno.test("Kolkata keeps its history: wartime +6:30, Madras time before 1906, IST today", () => {
  assertEquals(offsetSecondsAt("Asia/Kolkata", Date.UTC(1943, 5, 1, 6)), 6.5 * 3600);
  assertEquals(offsetSecondsAt("Asia/Kolkata", Date.UTC(2000, 5, 1, 6)), 5.5 * 3600);
  assertEquals(offsetSecondsAt("Asia/Kolkata", Date.UTC(1900, 5, 1, 6)), 5 * 3600 + 21 * 60 + 10);
});

Deno.test("a wall-clock birth time becomes the right instant", () => {
  const born = localToUtc({ year: 1943, month: 6, day: 1, hour: 12, minute: 0 }, "Asia/Kolkata")!;
  assertEquals(born.offsetSeconds, 23400);
  assertEquals(new Date(born.utcMs).toISOString(), "1943-06-01T05:30:00.000Z");

  const today = localToUtc({ year: 2000, month: 1, day: 1, hour: 5, minute: 30 }, "Asia/Kolkata")!;
  assertEquals(new Date(today.utcMs).toISOString(), "2000-01-01T00:00:00.000Z");
});

Deno.test("a time skipped by daylight saving reads on the offset from before the jump", () => {
  // 14 March 2021, 02:30 never happened in New York.
  const gap = localToUtc({ year: 2021, month: 3, day: 14, hour: 2, minute: 30 }, "America/New_York")!;
  assertEquals(gap.offsetSeconds, -5 * 3600);
  assertEquals(new Date(gap.utcMs).toISOString(), "2021-03-14T07:30:00.000Z");
});

Deno.test("a time repeated when the clocks go back is the first of the two", () => {
  // 7 November 2021, 01:30 happened twice in New York; the first was still on EDT.
  const overlap = localToUtc({ year: 2021, month: 11, day: 7, hour: 1, minute: 30 }, "America/New_York")!;
  assertEquals(overlap.offsetSeconds, -4 * 3600);
  assertEquals(new Date(overlap.utcMs).toISOString(), "2021-11-07T05:30:00.000Z");
});

Deno.test("a zone that is not one, or a date that does not exist, is refused", () => {
  assertEquals(isValidTimeZone("Asia/Kolkata"), true);
  assertEquals(isValidTimeZone("Mars/Olympus"), false);
  assertEquals(isValidTimeZone(""), false);
  assertEquals(isValidTimeZone(42), false);
  assertEquals(localToUtc({ year: 2000, month: 1, day: 1, hour: 0, minute: 0 }, "Nowhere/Else"), null);
  assertEquals(localToUtc({ year: 2001, month: 2, day: 29, hour: 0, minute: 0 }, "Asia/Kolkata"), null);
});
