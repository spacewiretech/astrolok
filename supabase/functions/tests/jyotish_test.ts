import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";

import {
  ayanamsa,
  chartToJson,
  computeChart,
  DASHA_CYCLE_YEARS,
  DASHA_LORDS,
  describeChart,
  IST_OFFSET_HOURS,
  julianDay,
  moonLongitude,
  NAKSHATRAS,
  rashiFromName,
  RASHIS,
  sunLongitude,
  toSidereal,
  vimshottariDasha,
} from "../_shared/jyotish.ts";

/**
 * The chart is the one thing in this app that is arithmetic rather than language, so it is the
 * one thing that can be *wrong* rather than merely weak — and wrong silently, since a plausible
 * nakshatra looks exactly like a correct one.
 *
 * The anchors below are Meeus's own worked examples, the published reference values for these
 * exact algorithms. If someone later trims the term table to save a few lines, these fail.
 */

// ---------------------------------------------------------------- Julian Day

Deno.test("Julian Day matches Meeus's worked examples", () => {
  // Meeus example 7.a — 1957 October 4.81, the launch of Sputnik 1.
  assertAlmostEquals(julianDay(1957, 10, 4, 0.81 * 24), 2436116.31, 1e-5);

  // The epoch itself: J2000.0 is 2000 January 1 at 12h TT.
  assertAlmostEquals(julianDay(2000, 1, 1, 12), 2451545.0, 1e-9);

  // Meeus example 7.b, a Gregorian date well before the app's range.
  assertAlmostEquals(julianDay(1988, 6, 19, 12), 2447332.0, 1e-9);
});

Deno.test("Julian Day handles January and February, which borrow from the previous year", () => {
  // The month <= 2 branch is the one place this function is not obvious, so it gets its own case.
  assertAlmostEquals(julianDay(2000, 1, 1, 0), 2451544.5, 1e-9);
  assertAlmostEquals(julianDay(2000, 2, 29, 0), 2451603.5, 1e-9);
  assertAlmostEquals(julianDay(1999, 12, 31, 0), 2451543.5, 1e-9);
});

// ---------------------------------------------------------------- the Sun

Deno.test("the Sun's longitude matches Meeus example 25.a", () => {
  // 1992 October 13, 0h TD. Meeus gives an apparent longitude of 199.90988 degrees.
  const jd = julianDay(1992, 10, 13, 0);
  assertAlmostEquals(jd, 2448908.5, 1e-9);

  assertAlmostEquals(sunLongitude(jd), 199.90988, 0.001);
});

Deno.test("the Sun's longitude advances about a degree a day", () => {
  // Sampled across the year, and wrapped: the first version of this test picked the March
  // equinox, where the Sun crosses 0 degrees, and read a one-degree step as minus 359.
  for (const [month, day] of [[1, 15], [3, 20], [6, 21], [9, 23], [12, 22]]) {
    const jd = julianDay(2000, month, day, 0);
    let delta = sunLongitude(jd + 1) - sunLongitude(jd);
    if (delta < 0) delta += 360;

    assert(delta > 0.9 && delta < 1.1, `moved ${delta} degrees on ${month}/${day}`);
  }
});

// ---------------------------------------------------------------- the Moon

Deno.test("the Moon's longitude matches Meeus example 47.a", () => {
  // 1992 April 12, 0h TD. Meeus gives lambda = 133.162655 degrees.
  //
  // This is the single most load-bearing assertion in the file: a nakshatra is 13°20' wide and
  // the whole feature rests on naming the right one. The tolerance is 0.02 degrees — inside it,
  // the term table is complete enough; outside, terms have gone missing.
  const jd = julianDay(1992, 4, 12, 0);
  assertAlmostEquals(jd, 2448724.5, 1e-9);

  assertAlmostEquals(moonLongitude(jd), 133.162655, 0.02);
});

Deno.test("the Moon's longitude advances about thirteen degrees a day", () => {
  // Why the birth *time* is asked for at all: at this speed a nakshatra lasts barely a day.
  const jd = julianDay(2000, 6, 1, 0);
  let previous = moonLongitude(jd);
  let total = 0;

  for (let i = 1; i <= 10; i++) {
    const current = moonLongitude(jd + i);
    let step = current - previous;
    if (step < 0) step += 360;
    total += step;
    previous = current;
  }

  const perDay = total / 10;
  assert(perDay > 12 && perDay < 15, `averaged ${perDay} degrees a day`);
});

Deno.test("Sun and Moon coincide at a known new moon, and oppose at a known full moon", () => {
  // The strongest check in this file, because it validates both series *against each other* at
  // instants published independently of any formula here. If either the solar or the lunar terms
  // were wrong, these separations would not come out.
  //
  // Syzygies from the published 2024 ephemeris.
  const newMoon = julianDay(2024, 1, 11, 11.95); // 11:57 UT
  assertAlmostEquals(
    Math.abs(sunLongitude(newMoon) - moonLongitude(newMoon)),
    0,
    0.1,
  );

  const fullMoon = julianDay(2024, 1, 25, 17.9); // 17:54 UT
  let separation = Math.abs(sunLongitude(fullMoon) - moonLongitude(fullMoon));
  if (separation > 180) separation = 360 - separation;
  assertAlmostEquals(separation, 180, 0.1);
});

Deno.test("the Sun sits at the cardinal points at the equinoxes and solstices", () => {
  // Sampled at noon rather than the exact instant, so a degree of slack is the sampling, not the
  // series. Enough to catch a sign error or a missing term.
  for (const [month, day, expected] of [[3, 20, 0], [6, 21, 90], [9, 23, 180], [12, 21, 270]]) {
    const longitude = sunLongitude(julianDay(2024, month, day, 12));
    const off = Math.min(
      Math.abs(longitude - expected),
      Math.abs(longitude - expected - 360),
      Math.abs(longitude - expected + 360),
    );
    assert(off < 1.5, `${month}/${day}: Sun at ${longitude}, expected near ${expected}`);
  }
});

Deno.test("longitudes stay inside [0, 360) across a wide span of dates", () => {
  for (let year = 1900; year <= 2030; year += 7) {
    const jd = julianDay(year, 3, 15, 6);
    for (const value of [moonLongitude(jd), sunLongitude(jd)]) {
      assert(value >= 0 && value < 360, `$${value} out of range in ${year}`);
    }
  }
});

// ---------------------------------------------------------------- sidereal

Deno.test("the Lahiri ayanamsa is right at J2000 and precesses about 50 arcseconds a year", () => {
  const j2000 = julianDay(2000, 1, 1, 12);
  assertAlmostEquals(ayanamsa(j2000), 23.85312, 1e-4);

  // A century later it should have grown by 50.2388" x 100 = 1.3955 degrees.
  const j2100 = julianDay(2100, 1, 1, 12);
  assertAlmostEquals(ayanamsa(j2100) - ayanamsa(j2000), 1.39552, 1e-3);

  // Published Lahiri values: about 22.46 in 1900 and about 24.14 in 2020.
  assertAlmostEquals(ayanamsa(julianDay(1900, 1, 1, 12)), 22.46, 0.02);
  assertAlmostEquals(ayanamsa(julianDay(2020, 1, 1, 12)), 24.14, 0.02);
});

Deno.test("the sidereal conversion wraps below zero rather than going negative", () => {
  const jd = julianDay(2020, 1, 1, 12);
  // A tropical longitude smaller than the ayanamsa must come back near 360, not near -14.
  const sidereal = toSidereal(10, jd);

  assert(sidereal > 345 && sidereal < 346, `got $${sidereal}`);
});

// ---------------------------------------------------------------- the chart

Deno.test("a full birth date and time yields a rashi, a nakshatra and a pada", () => {
  const chart = computeChart({ dob: "1996-04-12", birthTime: "07:30" })!;

  assert(chart !== null);
  assert(RASHIS.includes(chart.moonRashi as typeof RASHIS[number]));
  assert(RASHIS.includes(chart.sunRashi as typeof RASHIS[number]));
  assert(NAKSHATRAS.includes(chart.nakshatra as typeof NAKSHATRAS[number]));
  assert(chart.pada !== null && chart.pada >= 1 && chart.pada <= 4);
  assertEquals(chart.precise, true);
  assertEquals((chart.moonRashiEnglish ?? "").length > 0, true);
});

Deno.test("a missing birth time withholds the nakshatra rather than guessing one", () => {
  // The whole reason the sage asks for the hour. A nakshatra lasts about a day, so without a
  // time it cannot be named honestly — and a confident wrong one is worse than none.
  for (const birthTime of [null, undefined, "", "  ", "not a time", "25:00", "12:99"]) {
    const chart = computeChart({ dob: "1996-04-12", birthTime })!;

    assert(chart !== null, `null chart for ${JSON.stringify(birthTime)}`);
    assertEquals(chart.nakshatra, null);
    assertEquals(chart.pada, null);
    assertEquals(chart.precise, false);
    // The rashi survives: the Moon needs over two days to cross one.
    assert(RASHIS.includes(chart.moonRashi as typeof RASHIS[number]));
  }
});

Deno.test("seconds are accepted, because Postgres `time` renders them", () => {
  // `users.birth_time` is a `time`, and supabase-js hands it back as "07:30:00".
  const withSeconds = computeChart({ dob: "1996-04-12", birthTime: "07:30:00" })!;
  const without = computeChart({ dob: "1996-04-12", birthTime: "07:30" })!;

  assertEquals(withSeconds.nakshatra, without.nakshatra);
  assertEquals(withSeconds.precise, true);
});

Deno.test("a malformed date of birth yields null rather than a wrong chart", () => {
  for (const dob of ["", "   ", "not a date", "1996-13-01", "1996-04-32", "96-04-12"]) {
    assertEquals(computeChart({ dob }), null, `expected null for ${JSON.stringify(dob)}`);
  }
});

Deno.test("the timezone is applied, and IST is the default", () => {
  // Explicit IST and the default must agree, or the constant is not actually being used.
  const explicit = computeChart({
    dob: "1996-04-12",
    birthTime: "07:30",
    timezoneOffsetHours: IST_OFFSET_HOURS,
  })!;
  const implicit = computeChart({ dob: "1996-04-12", birthTime: "07:30" })!;

  assertEquals(explicit.nakshatra, implicit.nakshatra);
  assertEquals(explicit.pada, implicit.pada);
  assertEquals(IST_OFFSET_HOURS, 5.5);
});

Deno.test("a different timezone actually moves the Moon", () => {
  // Guards against the offset being accepted and then quietly ignored. Twelve hours is about
  // 6.6 degrees of lunar motion, which is half a nakshatra — it has to show up somewhere.
  const ist = computeChart({ dob: "1996-04-12", birthTime: "07:30" })!;
  const far = computeChart({
    dob: "1996-04-12",
    birthTime: "07:30",
    timezoneOffsetHours: -6.5,
  })!;

  assert(
    ist.nakshatra !== far.nakshatra || ist.pada !== far.pada,
    "twelve hours of difference changed nothing",
  );
});

Deno.test("the nakshatra agrees with the pada, and both agree with the rashi", () => {
  // Internal consistency across a year of birthdays: the three indices are derived from one
  // longitude, so they can never disagree unless the arithmetic is wrong.
  for (let day = 1; day <= 28; day++) {
    const chart = computeChart({
      dob: `1996-02-${String(day).padStart(2, "0")}`,
      birthTime: "12:00",
    })!;

    const nakshatraIndex = NAKSHATRAS.indexOf(
      chart.nakshatra as typeof NAKSHATRAS[number],
    );
    const rashiIndex = RASHIS.indexOf(chart.moonRashi as typeof RASHIS[number]);

    assert(nakshatraIndex >= 0, `unknown nakshatra ${chart.nakshatra}`);
    assert(rashiIndex >= 0, `unknown rashi ${chart.moonRashi}`);

    // A nakshatra spans 13°20'; a rashi spans 30°. The nakshatra's midpoint must fall in the
    // rashi the same longitude produced.
    const midpoint = (nakshatraIndex + 0.5) * (360 / 27);
    assertEquals(
      Math.floor(midpoint / 30) === rashiIndex ||
        // A nakshatra can straddle a rashi boundary, so either side is legitimate.
        Math.floor(((nakshatraIndex) * (360 / 27)) / 30) === rashiIndex ||
        Math.floor(((nakshatraIndex + 1) * (360 / 27) - 0.001) / 30) === rashiIndex,
      true,
      `${chart.nakshatra} does not sit in ${chart.moonRashi}`,
    );
  }
});

// ---------------------------------------------------------------- the prompt block

Deno.test("the chart is described as sentences the model can use", () => {
  const described = describeChart(
    computeChart({ dob: "1996-04-12", birthTime: "07:30" }),
  );

  assert(described.includes("Moon (Chandra)"));
  assert(described.includes("rashi"));
  assert(described.includes("Nakshatra:"));
  assert(!described.includes("UNKNOWN"));
});

Deno.test("an unknown nakshatra tells the sage to ask rather than to invent", () => {
  const described = describeChart(computeChart({ dob: "1996-04-12" }));

  assert(described.includes("UNKNOWN"));
  assert(described.includes("Do not name one"));
  assert(described.toLowerCase().includes("ask for the hour"));
});

Deno.test("no chart describes as an empty string, so callers can concatenate blindly", () => {
  assertEquals(describeChart(null), "");
});

// ---------------------------------------------------------------- a day the Moon changed sign

/**
 * 17 October 1999, IST. Chandra moves from Dhanu into Makara that evening, and Surya from Kanya
 * into Tula. The account behind this whole block was born at 11:55 that night and was told Dhanu —
 * from a noon chart — before its birth hour was known, then Makara after.
 */
const CHANGEOVER_DAY = "1999-10-17";

Deno.test("without the hour, a sign that changed that day is not named", () => {
  const chart = computeChart({ dob: CHANGEOVER_DAY })!;

  assertEquals(chart.moonRashi, null);
  assertEquals(chart.moonRashiCandidates, ["Dhanu", "Makara"]);
  assertEquals(chart.sunRashi, null);
  assertEquals(chart.sunRashiCandidates, ["Kanya", "Tula"]);
  assertEquals(chart.precise, false);
});

Deno.test("with the hour, the sign is named — and it is the one the noon guess got wrong", () => {
  const night = computeChart({ dob: CHANGEOVER_DAY, birthTime: "23:55" })!;
  assertEquals(night.moonRashi, "Makara");
  assertEquals(night.sunRashi, "Tula");
  assertEquals(night.moonRashiCandidates, ["Makara"]);

  const morning = computeChart({ dob: CHANGEOVER_DAY, birthTime: "06:00" })!;
  assertEquals(morning.moonRashi, "Dhanu");
});

Deno.test("a rashi they told the sage settles a day the Moon changed sign", () => {
  for (const said of ["Makara", "makar", "मकर", "Makar rashi hai", "Capricorn"]) {
    const chart = computeChart({ dob: CHANGEOVER_DAY, statedRashi: said })!;
    assertEquals(chart.moonRashi, "Makara", `"${said}" did not settle it`);
    assertEquals(chart.moonRashiStated, true);
  }
});

Deno.test("a stated rashi never overrules a sign the clock settles", () => {
  // The rashi a person knows is often their naam rashi. It may choose between two; it may not
  // replace one.
  const precise = computeChart({ dob: CHANGEOVER_DAY, birthTime: "23:55", statedRashi: "Dhanu" })!;
  assertEquals(precise.moonRashi, "Makara");
  assertEquals(precise.moonRashiStated, false);

  // The Moon held Makara all day on this date.
  const settledDay = computeChart({ dob: "1996-04-12", statedRashi: "Mesha" })!;
  assertEquals(settledDay.moonRashi, "Makara");

  // Neither of the two: nothing is settled.
  const neither = computeChart({ dob: CHANGEOVER_DAY, statedRashi: "Kumbha" })!;
  assertEquals(neither.moonRashi, null);
});

Deno.test("an uncertain rashi tells the sage not to choose", () => {
  const described = describeChart(computeChart({ dob: CHANGEOVER_DAY }));

  assert(described.includes("UNCERTAIN"));
  assert(described.includes("Dhanu") && described.includes("Makara"));
  assert(described.includes("Do not name either"));
  assert(!described.includes("Moon (Chandra) in"), "an uncertain sign was named anyway");
});

Deno.test("rashi names are read however people type them, and never out of a surname", () => {
  assertEquals(rashiFromName("Makar"), "Makara");
  assertEquals(rashiFromName("वृश्चिक राशि"), "Vrischika");
  assertEquals(rashiFromName("meri rashi kumbh hai"), "Kumbha");
  assertEquals(rashiFromName("Leo"), "Simha");
  assertEquals(rashiFromName("Prashant Singh"), null);
  assertEquals(rashiFromName("Kanyakumari"), null);
  assertEquals(rashiFromName(""), null);
  assertEquals(rashiFromName(null), null);
});

Deno.test("the chart travels with its uncertainty intact", () => {
  const json = chartToJson(computeChart({ dob: CHANGEOVER_DAY }))!;

  assertEquals(json.moon_rashi, null);
  assertEquals(json.moon_rashi_candidates, ["Dhanu", "Makara"]);
  assertEquals(json.mahadasha, null);
  assertEquals(chartToJson(null), null);
});

// ---------------------------------------------------------------- the dasha

const JULIAN_YEAR = 365.25;

/** J2000.0, as good a birth moment as any for the pure arithmetic below. */
const BIRTH_JD = 2451545;

Deno.test("the Vimshottari lords run in their fixed order, and make a 120-year cycle", () => {
  assertEquals(
    DASHA_LORDS.map(([lord]) => lord),
    ["Ketu", "Shukra", "Surya", "Chandra", "Mangal", "Rahu", "Guru", "Shani", "Budh"],
  );
  assertEquals(DASHA_LORDS.reduce((sum, [, years]) => sum + years, 0), DASHA_CYCLE_YEARS);
});

Deno.test("a Moon at the very start of Ashwini opens in Ketu, with all seven years to run", () => {
  const opening = vimshottariDasha(0.0001, BIRTH_JD, BIRTH_JD + 1)!;
  assertEquals(opening.mahadasha, "Ketu");
  assertEquals(opening.antardasha, "Ketu");
  assertEquals(opening.mahaPhase, "early");

  // Seven years on, Shukra's twenty begin, and its first sub-period is its own.
  const later = vimshottariDasha(0.0001, BIRTH_JD, BIRTH_JD + 7 * JULIAN_YEAR + 30)!;
  assertEquals(later.mahadasha, "Shukra");
  assertEquals(later.antardasha, "Shukra");
});

Deno.test("the balance at birth is whatever is left of the nakshatra", () => {
  // Halfway through Rohini, which is Chandra's: five of its ten years remain, so Mangal is next
  // at five.
  const halfwayThroughRohini = 3.5 * (360 / 27);

  assertEquals(
    vimshottariDasha(halfwayThroughRohini, BIRTH_JD, BIRTH_JD + 4.9 * JULIAN_YEAR)!.mahadasha,
    "Chandra",
  );
  assertEquals(
    vimshottariDasha(halfwayThroughRohini, BIRTH_JD, BIRTH_JD + 5.1 * JULIAN_YEAR)!.mahadasha,
    "Mangal",
  );
});

Deno.test("sub-periods open with the Mahadasha's own lord, each at its share of it", () => {
  // Inside Ketu's seven years: Ketu for 7×7/120 ≈ 0.41, Shukra for 7×20/120 ≈ 1.17 (to ≈ 1.58),
  // then Surya for 7×6/120 = 0.35 (to ≈ 1.93).
  assertEquals(vimshottariDasha(0.0001, BIRTH_JD, BIRTH_JD + 0.3 * JULIAN_YEAR)!.antardasha, "Ketu");
  assertEquals(
    vimshottariDasha(0.0001, BIRTH_JD, BIRTH_JD + 0.5 * JULIAN_YEAR)!.antardasha,
    "Shukra",
  );
  assertEquals(
    vimshottariDasha(0.0001, BIRTH_JD, BIRTH_JD + 1.7 * JULIAN_YEAR)!.antardasha,
    "Surya",
  );
});

Deno.test("no dasha without the hour, without a moment to count to, or before birth", () => {
  assertEquals(computeChart({ dob: "1996-04-12", asOf: new Date("2026-09-14") })!.dasha, null);
  assertEquals(computeChart({ dob: "1996-04-12", birthTime: "07:30" })!.dasha, null);
  assertEquals(vimshottariDasha(10, BIRTH_JD, BIRTH_JD - 1), null);
});

Deno.test("a chart with the hour carries the dasha, and describes it without a single year", () => {
  const chart = computeChart({
    dob: CHANGEOVER_DAY,
    birthTime: "23:55",
    asOf: new Date("2026-09-14T00:00:00Z"),
  })!;

  // Uttara Ashadha is Surya's, so this life opened in Surya's six years, then Chandra's ten,
  // Mangal's seven — which puts late 2026, at almost twenty-seven, in Rahu's eighteen.
  assertEquals(chart.nakshatra, "Uttara Ashadha");
  assertEquals(chart.dasha?.mahadasha, "Rahu");

  const described = describeChart(chart, { dasha: true });
  assert(described.includes("Mahadasha of Rahu"));
  assert(described.includes("Never give the year"));
  assert(!/\b(19|20)\d{2}\b/.test(described), "a year leaked into the chart description");

  assert(
    !describeChart(chart).includes("Mahadasha"),
    "the dasha reached a prompt that did not ask for it",
  );
});
