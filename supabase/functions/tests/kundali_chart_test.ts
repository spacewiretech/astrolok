import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";

import {
  ascendant,
  greenwichSiderealTime,
  isRetrograde,
  julianDay,
  mahadashaSequence,
  meanObliquity,
  meanRahu,
  planetLongitude,
  RASHIS,
  toSidereal,
  vimshottariDasha,
} from "../_shared/jyotish.ts";
import {
  computeKundaliChart,
  dignityOf,
  kundaliChartToJson,
  PLANET_KEYS,
  SIGN_LORDS,
  wholeSignHouse,
} from "../_shared/kundali_chart.ts";

/**
 * The kundali is arithmetic, and arithmetic can be wrong silently: a planet one sign off looks
 * exactly as plausible as the right one. These pin the new astronomy to published reference values
 * — Meeus's worked examples, and dates when a planet's sidereal sign or direction is a matter of
 * record — so a later "tidy-up" of the element tables fails here rather than in someone's chart.
 */

const signOf = (longitude: number) => RASHIS[Math.floor(longitude / 30) % 12];

// ---------------------------------------------------------------- Meeus anchors

Deno.test("sidereal time at Greenwich matches Meeus 12.a and 12.b", () => {
  // 1987 April 10, 0h UT: 13h10m46.3668s.
  assertAlmostEquals(greenwichSiderealTime(2446895.5), 197.693195, 1e-5);
  // The same day at 19h21m00s UT.
  assertAlmostEquals(greenwichSiderealTime(julianDay(1987, 4, 10, 19 + 21 / 60)), 128.7378734, 1e-4);
});

Deno.test("the mean node matches Meeus 22.a", () => {
  assertAlmostEquals(meanRahu(2446895.5), 11.2531, 1e-3);
});

Deno.test("Venus lands within a few arcseconds of Meeus 33.a", () => {
  // 1992 December 20, 0h TD: apparent λ 313.08102°. The low-precision elements are not apparent
  // positions, so the tolerance is an arcminute — still eight hundred times finer than a nakshatra.
  assertAlmostEquals(planetLongitude("venus", 2448976.5), 313.08102, 1 / 60);
});

Deno.test("Jupiter and Saturn meet at the great conjunction of 21 December 2020", () => {
  const jd = julianDay(2020, 12, 21, 18 + 20 / 60);
  const jupiter = planetLongitude("jupiter", jd);
  const saturn = planetLongitude("saturn", jd);
  assert(Math.abs(jupiter - saturn) < 0.2, `separation ${jupiter - saturn}`);
  // 0°29' Aquarius.
  assertAlmostEquals(jupiter, 300.48, 0.15);
});

// ---------------------------------------------------------------- sidereal signs on record

Deno.test("slow planets sit in the sidereal signs the almanacs give", () => {
  const at = (planet: "jupiter" | "saturn", y: number, m: number, d: number) => {
    const jd = julianDay(y, m, d);
    return signOf(toSidereal(planetLongitude(planet, jd), jd));
  };

  assertEquals(at("saturn", 2021, 6, 1), "Makara");
  assertEquals(at("saturn", 2024, 6, 1), "Kumbha");
  assertEquals(at("jupiter", 2023, 10, 1), "Mesha");
  assertEquals(at("jupiter", 2024, 10, 1), "Vrishabha");

  const jd = julianDay(2024, 6, 1);
  assertEquals(signOf(toSidereal(meanRahu(jd), jd)), "Meena");
  assertEquals(signOf(toSidereal(meanRahu(jd) + 180, jd)), "Kanya");
});

Deno.test("retrograde flags follow the published stations", () => {
  const retro = (planet: "mercury" | "venus" | "mars" | "jupiter" | "saturn", y: number, m: number, d: number) =>
    isRetrograde((jd) => planetLongitude(planet, jd), julianDay(y, m, d));

  // Mercury: 30 Jan – 21 Feb 2021.
  assertEquals(retro("mercury", 2021, 2, 10), true);
  assertEquals(retro("mercury", 2021, 1, 20), false);
  // Mars: 9 Sep – 13 Nov 2020.
  assertEquals(retro("mars", 2020, 10, 13), true);
  assertEquals(retro("mars", 2020, 12, 15), false);
  // Jupiter: 20 Jun – 18 Oct 2021. Venus: 19 Dec 2021 – 29 Jan 2022. Saturn: 17 Jun – 4 Nov 2023.
  assertEquals(retro("jupiter", 2021, 8, 1), true);
  assertEquals(retro("venus", 2022, 1, 10), true);
  assertEquals(retro("saturn", 2023, 8, 1), true);
  assertEquals(retro("saturn", 2024, 2, 1), false);
});

// ---------------------------------------------------------------- the ascendant

Deno.test("the ascendant is on the eastern horizon, wherever and whenever", () => {
  const D = Math.PI / 180;
  const places: Array<[number, number, number]> = [
    [28.61, 77.21, 3.5], // Delhi
    [19.07, 72.88, 14], // Mumbai
    [13.08, 80.27, 22], // Chennai
    [51.51, -0.13, 9], // London
    [-33.87, 151.21, 7], // Sydney
  ];

  for (const [lat, lng, hour] of places) {
    const jd = julianDay(2024, 3, 15, hour);
    const asc = ascendant(jd, lat, lng);
    const eps = meanObliquity(jd);

    const ra = Math.atan2(Math.sin(asc * D) * Math.cos(eps * D), Math.cos(asc * D)) / D;
    const dec = Math.asin(Math.sin(eps * D) * Math.sin(asc * D)) / D;
    const hourAngle = (greenwichSiderealTime(jd) + lng - ra) * D;
    const altitude = Math.asin(
      Math.sin(lat * D) * Math.sin(dec * D) + Math.cos(lat * D) * Math.cos(dec * D) * Math.cos(hourAngle),
    ) / D;

    assertAlmostEquals(altitude, 0, 1e-6, `altitude at ${lat},${lng}`);
    assert(Math.sin(hourAngle) < 0, `rising, not setting, at ${lat},${lng}`);
  }
});

Deno.test("at the equator with the equinox overhead, 0° Cancer is rising", () => {
  // RAMC = 0 at the equator puts the ecliptic's 90° point on the eastern horizon.
  const jd = 2451545.0;
  const lng = -greenwichSiderealTime(jd);
  assertAlmostEquals(ascendant(jd, 0, lng), 90, 1e-6);
});

Deno.test("the ascendant runs the whole zodiac once a sidereal day", () => {
  const jd = julianDay(2024, 1, 1);
  let travelled = 0;
  let previous = ascendant(jd, 23, 78);
  for (let minute = 4; minute <= 1436; minute += 4) {
    const next = ascendant(jd + minute / 1440, 23, 78);
    travelled += (next - previous + 360) % 360;
    previous = next;
  }
  assertAlmostEquals(travelled, 360, 2);
});

// ---------------------------------------------------------------- dignity and houses

Deno.test("dignity: exaltation, its opposite, own signs, and nothing for the nodes", () => {
  assertEquals(dignityOf("sun", 0), "exalted");
  assertEquals(dignityOf("sun", 6), "debilitated");
  assertEquals(dignityOf("sun", 4), "own");
  assertEquals(dignityOf("saturn", 6), "exalted");
  assertEquals(dignityOf("saturn", 0), "debilitated");
  assertEquals(dignityOf("saturn", 10), "own");
  // Kanya is both Mercury's own sign and its exaltation. Exaltation wins.
  assertEquals(dignityOf("mercury", 5), "exalted");
  assertEquals(dignityOf("mercury", 2), "own");
  assertEquals(dignityOf("moon", 7), "debilitated");
  assertEquals(dignityOf("jupiter", 1), null);
  assertEquals(dignityOf("rahu", 1), null);
  assertEquals(dignityOf("ketu", 7), null);
});

Deno.test("whole-sign houses count from the lagna's rashi", () => {
  assertEquals(wholeSignHouse(11, 11), 1);
  assertEquals(wholeSignHouse(0, 11), 2);
  assertEquals(wholeSignHouse(10, 11), 12);
  assertEquals(wholeSignHouse(5, 0), 6);
  assertEquals(SIGN_LORDS.length, 12);
});

// ---------------------------------------------------------------- the dasha timeline

Deno.test("the Mahadasha sequence tiles 120 years and agrees with the running period", () => {
  const moon = 45.5; // Rohini, a Chandra nakshatra
  const birth = julianDay(1990, 1, 1, 6.5);
  const periods = mahadashaSequence(moon, birth);

  assertEquals(periods.length, 9);
  assertEquals(periods[0].lord, "Chandra");
  assert(periods[0].startJd <= birth && birth < periods[0].endJd);
  for (let i = 1; i < periods.length; i++) {
    assertAlmostEquals(periods[i].startJd, periods[i - 1].endJd, 1e-9);
  }
  assertAlmostEquals((periods[8].endJd - periods[0].startJd) / 365.25, 120, 1e-6);

  const asOf = julianDay(2026, 9, 17);
  const running = vimshottariDasha(moon, birth, asOf)!;
  const current = periods.find((p) => asOf >= p.startJd && asOf < p.endJd)!;
  assertEquals(running.mahadasha, current.lord);
});

// ---------------------------------------------------------------- the assembled chart

const DELHI_1990 = {
  dob: "1990-01-01",
  birthTime: "12:00",
  utcOffsetSeconds: 19800,
  latitude: 28.6139,
  longitude: 77.209,
  asOf: new Date("2026-09-17T00:00:00Z"),
};

Deno.test("a chart places every graha in exactly one house", () => {
  const chart = computeKundaliChart(DELHI_1990)!;
  assertEquals(chart.planets.map((p) => p.key), [...PLANET_KEYS]);
  assertEquals(chart.houses.length, 12);

  const occupants = chart.houses.flatMap((h) => h.occupants).sort();
  assertEquals(occupants, [...PLANET_KEYS].sort());

  for (const planet of chart.planets) {
    assertEquals(planet.house, wholeSignHouse(planet.rashiIndex, chart.lagna.rashiIndex));
    assert(planet.degree >= 0 && planet.degree < 30);
    assert(planet.pada >= 1 && planet.pada <= 4);
  }

  // Rahu and Ketu are always six houses apart.
  const rahu = chart.planets.find((p) => p.key === "rahu")!;
  const ketu = chart.planets.find((p) => p.key === "ketu")!;
  assertEquals((rahu.rashiIndex + 6) % 12, ketu.rashiIndex);
});

Deno.test("noon in Delhi on 1 January 1990 has Meena rising and the Sun in the tenth", () => {
  // A winter noon puts the Sun near the meridian — the tenth house — which is a check a reader can
  // do in their head. Sun in Dhanu around 17°; Saturn in Dhanu; Jupiter in Mithuna.
  const chart = computeKundaliChart(DELHI_1990)!;
  const at = (key: string) => chart.planets.find((p) => p.key === key)!;

  assertEquals(chart.lagna.rashi, "Meena");
  assertEquals(at("sun").rashi, "Dhanu");
  assertEquals(at("sun").house, 10);
  assertAlmostEquals(at("sun").degree, 16.87, 0.1);
  assertEquals(at("saturn").rashi, "Dhanu");
  assertEquals(at("jupiter").rashi, "Mithuna");
  assertEquals(at("jupiter").retrograde, true);
  assertEquals(chart.houses[0].lord, "jupiter");
});

Deno.test("the offset moves the moment: noon on +6:30 is eleven o'clock on +5:30", () => {
  const wartimeNoon = computeKundaliChart({ ...DELHI_1990, utcOffsetSeconds: 23400 })!;
  const istEleven = computeKundaliChart({ ...DELHI_1990, birthTime: "11:00" })!;
  const istNoon = computeKundaliChart(DELHI_1990)!;

  assertAlmostEquals(wartimeNoon.lagna.longitude, istEleven.lagna.longitude, 1e-9);
  assertAlmostEquals(wartimeNoon.planets[1].longitude, istEleven.planets[1].longitude, 1e-9);
  // And an hour is not nothing: the lagna has moved on by well over ten degrees.
  assert((istNoon.lagna.longitude - wartimeNoon.lagna.longitude + 360) % 360 > 10);
});

Deno.test("unusable input is refused rather than guessed", () => {
  assertEquals(computeKundaliChart({ ...DELHI_1990, birthTime: "" }), null);
  assertEquals(computeKundaliChart({ ...DELHI_1990, birthTime: "25:00" }), null);
  assertEquals(computeKundaliChart({ ...DELHI_1990, dob: "1990-13-01" }), null);
  assertEquals(computeKundaliChart({ ...DELHI_1990, latitude: 91 }), null);
  assertEquals(computeKundaliChart({ ...DELHI_1990, longitude: NaN }), null);
  assertEquals(computeKundaliChart({ ...DELHI_1990, utcOffsetSeconds: 20 * 3600 }), null);
});

Deno.test("the stored JSON carries what the app draws, and dates only in the timeline", () => {
  const json = kundaliChartToJson(computeKundaliChart(DELHI_1990)!) as Record<string, any>;

  assertEquals(json.version, 1);
  assertEquals(json.planets.length, 9);
  assertEquals(json.houses.length, 12);
  assertEquals(typeof json.lagna.rashi_index, "number");
  assertEquals(json.planets[0].abbr, "Su");
  assertEquals(json.moon.nakshatra, json.planets[1].nakshatra);
  assertEquals(json.dasha.sequence.length, 9);
  assertEquals(json.dasha.sequence.filter((s: { current: boolean }) => s.current).length, 1);
  assert(json.transit.jupiter_house_from_moon >= 1 && json.transit.jupiter_house_from_moon <= 12);
});
