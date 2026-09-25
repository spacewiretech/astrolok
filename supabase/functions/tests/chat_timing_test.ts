import { assert, assertEquals } from "jsr:@std/assert@1";

import { chatTiming, describeTiming, monthYear } from "../_shared/chat_timing.ts";
import { AntardashaPeriod, Chart, computeChart, julianDayOf } from "../_shared/jyotish.ts";

/**
 * The windows chat v4 answers "when" with.
 *
 * Every year the sage names comes from here, so this is where the promise behind v4 is checked:
 * the window is the soonest period the chart favours, it is the same every time, it never opens
 * in the past, and it never times a marriage for a child.
 *
 * Most cases use a hand-built chart, because the rule under test is about the order of periods,
 * and a real birth date would bury that under arithmetic the jyotish tests already cover.
 */

const AS_OF = new Date("2026-09-24T00:00:00Z");
const NOW = julianDayOf(AS_OF);
const YEAR = 365.25;

/** An adult, so no age rule interferes unless a test asks for one. */
const ADULT_DOB = "1990-01-01";

/** Back-to-back periods from [startYears] (relative to now), each [mahadasha, antardasha, years]. */
function periods(
  startYears: number,
  ...spans: Array<[string, string, number]>
): AntardashaPeriod[] {
  let start = NOW + startYears * YEAR;
  return spans.map(([mahadasha, antardasha, years]) => {
    const period = { mahadasha, antardasha, startJd: start, endJd: start + years * YEAR };
    start = period.endJd;
    return period;
  });
}

function chart(moonRashi: string, spans: AntardashaPeriod[]): Chart {
  return {
    moonRashi,
    moonRashiEnglish: null,
    moonRashiCandidates: [moonRashi],
    moonRashiStated: false,
    nakshatra: "Ashwini",
    pada: 1,
    sunRashi: null,
    sunRashiEnglish: null,
    sunRashiCandidates: [],
    precise: true,
    dasha: {
      mahadasha: spans[0].mahadasha,
      mahaPhase: "middle",
      antardasha: spans[0].antardasha,
      antarPhase: "middle",
    },
    periods: spans,
  };
}

function topic(timing: ReturnType<typeof chatTiming>, key: string) {
  return timing!.topics.find((entry) => entry.topic === key)!;
}

// ---------------------------------------------------------------- which grahas time what

Deno.test("a matter is timed by its karakas and by the lord of its house from Chandra", () => {
  // Mesha: the 7th from it is Tula, Shukra's own, so Shukra is both karaka and house lord.
  const mesha = chatTiming(chart("Mesha", periods(-1, ["Shani", "Budh", 5])), {
    dob: ADULT_DOB,
    asOf: AS_OF,
  });
  const marriage = topic(mesha, "marriage");
  assertEquals(Object.keys(marriage.reasons).sort(), ["Guru", "Shukra"]);
  assert(marriage.reasons.Shukra.includes("the graha of love and marriage"));
  assert(marriage.reasons.Shukra.includes("lord of the 7th house from their Chandra"));

  // Makara: the 7th is Karka, so Chandra times a marriage as well.
  const makara = chatTiming(chart("Makara", periods(-1, ["Shani", "Budh", 5])), {
    dob: ADULT_DOB,
    asOf: AS_OF,
  });
  assert(topic(makara, "marriage").reasons.Chandra.includes("lord of the 7th house"));
});

Deno.test("no children topic exists to be timed", () => {
  // Fertility is under BOUNDARIES, so there is nothing here the sage could read a year out of.
  const timing = chatTiming(chart("Mesha", periods(-1, ["Shani", "Budh", 5])), {
    dob: ADULT_DOB,
    asOf: AS_OF,
  })!;
  assertEquals(timing.topics.map((entry) => entry.topic), [
    "marriage",
    "career",
    "money",
    "home",
    "studies",
  ]);
});

// ---------------------------------------------------------------- choosing the window

Deno.test("the window is the soonest favoured sub-period, and never one already past", () => {
  const timing = chatTiming(
    chart(
      "Mesha",
      periods(-3, ["Shani", "Shukra", 2], ["Shani", "Budh", 2], ["Shani", "Ketu", 1], [
        "Budh",
        "Budh",
        2,
      ], ["Budh", "Shukra", 3]),
    ),
    { dob: ADULT_DOB, asOf: AS_OF },
  );

  // Shani/Shukra ended a year ago; the next Shukra opens in four years — inside the long wait.
  const [first] = topic(timing, "marriage").windows;
  assertEquals(first.lords, ["Shukra"]);
  assertEquals(first.level, "antardasha");
  assertEquals(first.now, false);
  assert(Math.abs(first.startJd - (NOW + 4 * YEAR)) < 1);
});

Deno.test("a window already running starts now, not when its period began", () => {
  const timing = chatTiming(chart("Mesha", periods(-1, ["Shani", "Shukra", 3])), {
    dob: ADULT_DOB,
    asOf: AS_OF,
  });

  const [first] = topic(timing, "marriage").windows;
  assertEquals(first.now, true);
  assertEquals(first.startJd, NOW);
});

Deno.test("favoured periods back to back are one window, not two", () => {
  // Guru then Shani, both favoured for money from Mesha (Guru the karaka, Shani the 11th lord).
  const timing = chatTiming(
    chart("Mesha", periods(0.5, ["Rahu", "Guru", 2], ["Rahu", "Shani", 3], ["Rahu", "Budh", 2])),
    { dob: ADULT_DOB, asOf: AS_OF },
  );

  const windows = topic(timing, "money").windows;
  assertEquals(windows.length, 1);
  assertEquals(windows[0].lords, ["Guru", "Shani"]);
  assertEquals(windows[0].antardashas, ["Guru", "Shani"]);
  assert(Math.abs(windows[0].endJd - (NOW + 5.5 * YEAR)) < 1);
});

Deno.test("a period about to close is not offered as now — unless it runs into another", () => {
  const closing = chatTiming(
    chart("Mesha", periods(-2, ["Ketu", "Shukra", 2 + 30 / YEAR], ["Ketu", "Surya", 1], [
      "Ketu",
      "Chandra",
      1,
    ], ["Ketu", "Shukra", 2])),
    { dob: ADULT_DOB, asOf: AS_OF },
  );
  const [first] = topic(closing, "marriage").windows;
  assertEquals(first.now, false, "offered a window with a month left in it");

  // The same closing Shukra, straight into a Guru: one long window, and it is running now.
  const continuing = chatTiming(
    chart("Mesha", periods(-2, ["Ketu", "Shukra", 2 + 30 / YEAR], ["Ketu", "Guru", 2])),
    { dob: ADULT_DOB, asOf: AS_OF },
  );
  const [running] = topic(continuing, "marriage").windows;
  assertEquals(running.now, true);
  assertEquals(running.lords, ["Shukra", "Guru"]);
});

Deno.test("a long wait is bridged by a favoured Mahadasha running now", () => {
  // The case that prompted the rule: 21, in the last years of Guru's Mahadasha, and the next
  // Shukra sub-period eight years off. "2035" is a verdict, not a window.
  const timing = chatTiming(
    chart(
      "Mesha",
      periods(-1, ["Guru", "Rahu", 2.5], ["Shani", "Shani", 3], ["Shani", "Budh", 2.7], [
        "Shani",
        "Ketu",
        1.1,
      ], ["Shani", "Shukra", 3.2]),
    ),
    { dob: ADULT_DOB, asOf: AS_OF },
  );

  const [first, second] = topic(timing, "marriage").windows;
  assertEquals(first.level, "mahadasha");
  assertEquals(first.lords, ["Guru"]);
  assertEquals(first.antardashas, ["Rahu"]);
  assertEquals(first.now, true);

  // The sub-period of its own still follows, as the answer to "and if not then?"
  assertEquals(second.level, "antardasha");
  assertEquals(second.lords, ["Shukra"]);
});

Deno.test("a favoured sub-period within reach is not displaced by a Mahadasha", () => {
  const timing = chatTiming(
    chart("Mesha", periods(-1, ["Guru", "Rahu", 2.5], ["Shani", "Shani", 0.5], ["Shani", "Shukra", 3])),
    { dob: ADULT_DOB, asOf: AS_OF },
  );

  const [first] = topic(timing, "marriage").windows;
  assertEquals(first.level, "antardasha");
  assertEquals(first.lords, ["Shukra"]);
});

Deno.test("never more than two windows", () => {
  const timing = chatTiming(
    chart(
      "Mesha",
      periods(0, ["Shukra", "Shukra", 1], ["Shukra", "Surya", 1], ["Shukra", "Guru", 1], [
        "Shukra",
        "Ketu",
        1,
      ], ["Shukra", "Shukra", 1], ["Shukra", "Surya", 1], ["Shukra", "Guru", 1]),
    ),
    { dob: ADULT_DOB, asOf: AS_OF },
  );

  for (const entry of timing!.topics) assert(entry.windows.length <= 2, entry.topic);
});

// ---------------------------------------------------------------- age

Deno.test("no marriage is timed for someone under 18, and everything else still is", () => {
  const timing = chatTiming(chart("Mesha", periods(-1, ["Shani", "Shukra", 3], ["Shani", "Surya", 1])), {
    dob: "2010-06-01",
    asOf: AS_OF,
  });

  const marriage = topic(timing, "marriage");
  assertEquals(marriage.withheld, true);
  assertEquals(marriage.windows, []);

  assertEquals(topic(timing, "career").withheld, false);
  assert(topic(timing, "career").windows.length > 0);
});

Deno.test("no marriage window opens before 21", () => {
  // 19 now, with Shukra running: the window waits for the 21st birthday rather than starting today.
  const dob = "2007-06-01";
  const timing = chatTiming(chart("Mesha", periods(-1, ["Shani", "Shukra", 5])), {
    dob,
    asOf: AS_OF,
  });

  const [first] = topic(timing, "marriage").windows;
  const twentyFirst = julianDayOf(new Date(Date.UTC(2028, 5, 1)));
  assertEquals(first.now, false);
  assertEquals(first.startJd, twentyFirst);

  // Career has no such floor.
  assertEquals(topic(timing, "career").windows[0]?.now ?? true, true);
});

// ---------------------------------------------------------------- nothing to time from

Deno.test("no dated periods, no timing", () => {
  assertEquals(chatTiming(null, { dob: ADULT_DOB, asOf: AS_OF }), null);
  assertEquals(
    chatTiming(computeChart({ dob: "1996-04-12", asOf: AS_OF }), { dob: "1996-04-12", asOf: AS_OF }),
    null,
    "a chart without the hour was timed",
  );
});

Deno.test("the same chart gives the same windows every time", () => {
  // The whole point of computing them: ask twice, hear the same years.
  const dob = "1999-10-17";
  const once = chatTiming(computeChart({ dob, birthTime: "23:55", asOf: AS_OF }), { dob, asOf: AS_OF });
  const twice = chatTiming(computeChart({ dob, birthTime: "23:55", asOf: AS_OF }), { dob, asOf: AS_OF });

  assert(once !== null);
  assertEquals(once, twice);
});

// ---------------------------------------------------------------- the prompt block

Deno.test("an unknown timing says so, and forbids a year", () => {
  const noHour = describeTiming(null, { hasChart: true });
  assert(noHour.includes("THE TIMING: UNKNOWN"));
  assert(noHour.includes("hour of birth is not on file"));
  assert(noHour.includes("Name no year, no month and no age"));

  assert(describeTiming(null, { hasChart: false }).includes("date of birth is not on file"));
});

Deno.test("a known timing names today, each matter's window in months and years, and the rule", () => {
  const dob = "1999-10-17";
  const timing = chatTiming(computeChart({ dob, birthTime: "23:55", asOf: AS_OF }), {
    dob,
    asOf: AS_OF,
  });
  const block = describeTiming(timing, { hasChart: true });

  assert(block.includes("today is September 2026"));
  assert(block.includes("- Marriage, a life partner"));
  assert(block.includes("The periods ahead, in order:"));
  assert(block.includes("never as a day or a date"));
  assert(block.includes("Give the same window every time you are asked"));
  // A month and a year, never a day of the month.
  const months = "January|February|March|April|May|June|July|August|September|October|" +
    "November|December";
  assert(!new RegExp(`\\b\\d{1,2} (${months})\\b`).test(block), "a day of the month leaked");
});

Deno.test("an under-18 marriage line says to name no time", () => {
  const timing = chatTiming(chart("Mesha", periods(-1, ["Shani", "Shukra", 3])), {
    dob: "2010-06-01",
    asOf: AS_OF,
  });
  const block = describeTiming(timing, { hasChart: true });
  assert(block.includes("they are under 18. Name no time for marriage"));
});

Deno.test("a month and a year, read off a Julian Day", () => {
  assertEquals(monthYear(julianDayOf(new Date("2027-03-15T00:00:00Z"))), "March 2027");
  assertEquals(monthYear(julianDayOf(new Date("2030-12-31T23:00:00Z"))), "December 2030");
});
