/**
 * A full birth chart: the lagna, all nine grahas, and the twelve houses they fall in.
 *
 * `jyotish.ts` does the astronomy; this assembles it into the thing a kundali is read from. Kept
 * apart so the chat's module does not grow a dependency on a place it has never been given.
 *
 * Conventions, all of them the common North Indian ones:
 *   - sidereal, Lahiri ayanamsa (see `ayanamsa`)
 *   - whole-sign houses: the lagna's rashi is the first house, the next rashi the second, and so on
 *   - mean Rahu, Ketu opposite
 *   - dignity only for the seven visible grahas; the traditions disagree about the nodes
 *
 * Pure, like `jyotish.ts`: the moment of birth arrives as an explicit UTC offset, and "now" (for
 * the dasha and the transit) as an explicit `asOf`, so every chart is reproducible in a test.
 */

import {
  ascendant,
  ayanamsa,
  Graha,
  isRetrograde,
  julianDay,
  julianDayOf,
  mahadashaSequence,
  meanRahu,
  moonLongitude,
  NAKSHATRA_SPAN,
  NAKSHATRAS,
  parseClock,
  planetLongitude,
  RASHIS,
  sunLongitude,
  toSidereal,
  vimshottariDasha,
  wrap360,
} from "./jyotish.ts";

export type PlanetKey =
  | "sun"
  | "moon"
  | "mars"
  | "mercury"
  | "jupiter"
  | "venus"
  | "saturn"
  | "rahu"
  | "ketu";

export interface PlanetInfo {
  key: PlanetKey;
  /** What the chart diagram prints. */
  abbr: string;
  /** The name the tradition uses — and the one `DASHA_LORDS` spells. */
  sanskrit: string;
  english: string;
}

/** In the order a kundali lists them. */
export const PLANETS: readonly PlanetInfo[] = [
  { key: "sun", abbr: "Su", sanskrit: "Surya", english: "Sun" },
  { key: "moon", abbr: "Mo", sanskrit: "Chandra", english: "Moon" },
  { key: "mars", abbr: "Ma", sanskrit: "Mangal", english: "Mars" },
  { key: "mercury", abbr: "Me", sanskrit: "Budh", english: "Mercury" },
  { key: "jupiter", abbr: "Ju", sanskrit: "Guru", english: "Jupiter" },
  { key: "venus", abbr: "Ve", sanskrit: "Shukra", english: "Venus" },
  { key: "saturn", abbr: "Sa", sanskrit: "Shani", english: "Saturn" },
  { key: "rahu", abbr: "Ra", sanskrit: "Rahu", english: "Rahu" },
  { key: "ketu", abbr: "Ke", sanskrit: "Ketu", english: "Ketu" },
];

export const PLANET_KEYS: readonly PlanetKey[] = PLANETS.map((p) => p.key);

const BY_SANSKRIT = new Map(PLANETS.map((p) => [p.sanskrit, p.key]));

/** The Western names, which is how most Indian apps and almanacs gloss a sidereal rashi. */
export const SIGN_NAMES = [
  "Aries",
  "Taurus",
  "Gemini",
  "Cancer",
  "Leo",
  "Virgo",
  "Libra",
  "Scorpio",
  "Sagittarius",
  "Capricorn",
  "Aquarius",
  "Pisces",
] as const;

/** The graha that rules each rashi, Mesha first. */
export const SIGN_LORDS: readonly PlanetKey[] = [
  "mars",
  "venus",
  "mercury",
  "moon",
  "sun",
  "mercury",
  "venus",
  "mars",
  "jupiter",
  "saturn",
  "saturn",
  "jupiter",
];

/** The rashi each graha is exalted in. Debilitation is always the rashi opposite. */
const EXALTATION: Partial<Record<PlanetKey, number>> = {
  sun: 0, // Mesha
  moon: 1, // Vrishabha
  mars: 9, // Makara
  mercury: 5, // Kanya
  jupiter: 3, // Karka
  venus: 11, // Meena
  saturn: 6, // Tula
};

export type Dignity = "exalted" | "debilitated" | "own" | null;

/**
 * Exalted, debilitated, in its own sign, or none of those.
 *
 * Exaltation is checked first, which only matters for Mercury in Kanya — its own sign and its
 * exaltation both.
 */
export function dignityOf(planet: PlanetKey, rashiIndex: number): Dignity {
  const exalted = EXALTATION[planet];
  if (exalted === undefined) return null;
  if (rashiIndex === exalted) return "exalted";
  if (rashiIndex === (exalted + 6) % 12) return "debilitated";
  if (SIGN_LORDS[rashiIndex] === planet) return "own";
  return null;
}

/** 1-12: the house a rashi is, counted from the lagna's rashi. */
export function wholeSignHouse(rashiIndex: number, lagnaRashiIndex: number): number {
  return ((rashiIndex - lagnaRashiIndex + 12) % 12) + 1;
}

export interface Placement {
  /** Sidereal longitude, degrees. */
  longitude: number;
  rashiIndex: number;
  rashi: string;
  sign: string;
  /** Degrees into the rashi, 0 to 30. */
  degree: number;
  nakshatra: string;
  pada: number;
}

export interface PlacedPlanet extends Placement, PlanetInfo {
  house: number;
  retrograde: boolean;
  dignity: Dignity;
}

export interface House {
  house: number;
  rashiIndex: number;
  rashi: string;
  sign: string;
  lord: PlanetKey;
  occupants: PlanetKey[];
}

export interface DashaSpan {
  lord: string;
  planet: PlanetKey;
  startYear: number;
  endYear: number;
  current: boolean;
}

export interface KundaliChart {
  ayanamsa: number;
  lagna: Placement & { lord: PlanetKey };
  planets: PlacedPlanet[];
  houses: House[];
  dasha: {
    mahadasha: string;
    mahadashaPlanet: PlanetKey;
    mahaPhase: string;
    antardasha: string;
    antardashaPlanet: PlanetKey;
    antarPhase: string;
    sequence: DashaSpan[];
  } | null;
  /** Where Jupiter is at [KundaliInput.asOf], counted from the natal Moon — the "year ahead" anchor. */
  transit: { asOf: string; jupiterRashi: string; jupiterHouseFromMoon: number };
}

export interface KundaliInput {
  /** `YYYY-MM-DD`, local to the birth place. */
  dob: string;
  /** `HH:MM[:SS]`, local to the birth place. Required: there is no lagna without it. */
  birthTime: string;
  /** Seconds east of UTC in force at the birth place at the moment of birth. */
  utcOffsetSeconds: number;
  latitude: number;
  /** Degrees east of Greenwich. */
  longitude: number;
  /** "Now", for the running dasha and the transit. */
  asOf: Date;
}

function place(longitude: number): Placement {
  const lon = wrap360(longitude);
  const rashiIndex = Math.floor(lon / 30) % 12;
  const nakshatraIndex = Math.floor(lon / NAKSHATRA_SPAN) % 27;
  return {
    longitude: lon,
    rashiIndex,
    rashi: RASHIS[rashiIndex],
    sign: SIGN_NAMES[rashiIndex],
    degree: lon - rashiIndex * 30,
    nakshatra: NAKSHATRAS[nakshatraIndex],
    pada: Math.floor((lon % NAKSHATRA_SPAN) / (NAKSHATRA_SPAN / 4)) + 1,
  };
}

function yearOf(jd: number): number {
  return new Date((jd - 2440587.5) * 86_400_000).getUTCFullYear();
}

/**
 * The chart, or null when any input is unusable — a malformed date or time, coordinates off the
 * globe, or an offset no zone has ever had.
 */
export function computeKundaliChart(input: KundaliInput): KundaliChart | null {
  const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(input.dob?.trim() ?? "");
  if (!parts) return null;
  const year = Number(parts[1]);
  const month = Number(parts[2]);
  const day = Number(parts[3]);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  const clock = parseClock(input.birthTime);
  if (clock === null) return null;

  const { latitude, longitude, utcOffsetSeconds } = input;
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) return null;
  if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) return null;
  if (!Number.isFinite(utcOffsetSeconds) || Math.abs(utcOffsetSeconds) > 15 * 3600) return null;
  if (!(input.asOf instanceof Date) || !Number.isFinite(input.asOf.getTime())) return null;

  const jd = julianDay(year, month, day, clock - utcOffsetSeconds / 3600);
  const sidereal = (tropical: number) => toSidereal(tropical, jd);

  const lagna = place(sidereal(ascendant(jd, latitude, longitude)));

  const tropicalAt: Record<PlanetKey, (at: number) => number> = {
    sun: sunLongitude,
    moon: moonLongitude,
    mars: (at) => planetLongitude("mars", at),
    mercury: (at) => planetLongitude("mercury", at),
    jupiter: (at) => planetLongitude("jupiter", at),
    venus: (at) => planetLongitude("venus", at),
    saturn: (at) => planetLongitude("saturn", at),
    rahu: meanRahu,
    ketu: (at) => wrap360(meanRahu(at) + 180),
  };

  const planets: PlacedPlanet[] = PLANETS.map((info) => {
    const placement = place(sidereal(tropicalAt[info.key](jd)));
    const graha = info.key as Graha;
    return {
      ...info,
      ...placement,
      house: wholeSignHouse(placement.rashiIndex, lagna.rashiIndex),
      // The Sun and Moon never go backwards. The mean nodes always do, which is why a chart does
      // not bother marking them — the flag stays true here, and the app decides what to print.
      retrograde: info.key === "rahu" || info.key === "ketu"
        ? true
        : (info.key === "sun" || info.key === "moon")
        ? false
        : isRetrograde((at) => planetLongitude(graha, at), jd),
      dignity: dignityOf(info.key, placement.rashiIndex),
    };
  });

  const houses: House[] = Array.from({ length: 12 }, (_, i) => {
    const rashiIndex = (lagna.rashiIndex + i) % 12;
    return {
      house: i + 1,
      rashiIndex,
      rashi: RASHIS[rashiIndex],
      sign: SIGN_NAMES[rashiIndex],
      lord: SIGN_LORDS[rashiIndex],
      occupants: planets.filter((p) => p.house === i + 1).map((p) => p.key),
    };
  });

  const moon = planets.find((p) => p.key === "moon")!;
  const asOfJd = julianDayOf(input.asOf);

  const running = vimshottariDasha(moon.longitude, jd, asOfJd);
  const periods = mahadashaSequence(moon.longitude, jd);

  const dasha = running
    ? {
      mahadasha: running.mahadasha,
      mahadashaPlanet: BY_SANSKRIT.get(running.mahadasha)!,
      mahaPhase: running.mahaPhase,
      antardasha: running.antardasha,
      antardashaPlanet: BY_SANSKRIT.get(running.antardasha)!,
      antarPhase: running.antarPhase,
      sequence: periods.map((p) => ({
        lord: p.lord,
        planet: BY_SANSKRIT.get(p.lord)!,
        startYear: yearOf(p.startJd),
        endYear: yearOf(p.endJd),
        current: asOfJd >= p.startJd && asOfJd < p.endJd,
      })),
    }
    : null;

  const transitJupiter = place(toSidereal(planetLongitude("jupiter", asOfJd), asOfJd));

  return {
    ayanamsa: ayanamsa(jd),
    lagna: { ...lagna, lord: SIGN_LORDS[lagna.rashiIndex] },
    planets,
    houses,
    dasha,
    transit: {
      asOf: input.asOf.toISOString().slice(0, 10),
      jupiterRashi: transitJupiter.rashi,
      jupiterHouseFromMoon: wholeSignHouse(transitJupiter.rashiIndex, moon.rashiIndex),
    },
  };
}

const round2 = (n: number) => Math.round(n * 100) / 100;

export interface PlacementJson {
  longitude: number;
  rashi_index: number;
  rashi: string;
  sign: string;
  degree: number;
  nakshatra: string;
  pada: number;
}

/** `kundalis.chart`, as written by [kundaliChartToJson] and read by the worker and the app. */
export interface KundaliChartJson {
  version: number;
  ayanamsa: number;
  lagna: PlacementJson & { lord: PlanetKey };
  planets: Array<
    PlacementJson & {
      key: PlanetKey;
      abbr: string;
      name: string;
      english: string;
      house: number;
      retrograde: boolean;
      dignity: Dignity;
    }
  >;
  houses: Array<{
    house: number;
    rashi_index: number;
    rashi: string;
    sign: string;
    lord: PlanetKey;
    occupants: PlanetKey[];
  }>;
  moon: { rashi: string; sign: string; nakshatra: string; pada: number };
  dasha: {
    mahadasha: string;
    mahadasha_planet: PlanetKey;
    maha_phase: string;
    antardasha: string;
    antardasha_planet: PlanetKey;
    antar_phase: string;
    sequence: Array<{ lord: string; planet: PlanetKey; start_year: number; end_year: number; current: boolean }>;
  } | null;
  transit: { as_of: string; jupiter_rashi: string; jupiter_house_from_moon: number };
}

function placementJson(p: Placement): PlacementJson {
  return {
    longitude: round2(p.longitude),
    rashi_index: p.rashiIndex,
    rashi: p.rashi,
    sign: p.sign,
    degree: round2(p.degree),
    nakshatra: p.nakshatra,
    pada: p.pada,
  };
}

/**
 * The chart as `kundalis.chart` stores it and the app reads it. snake_case, degrees to two places.
 * `version` lets a later shape change be recognised in rows written before it.
 */
export function kundaliChartToJson(chart: KundaliChart): KundaliChartJson {
  const moon = chart.planets.find((p) => p.key === "moon")!;
  return {
    version: 1,
    ayanamsa: round2(chart.ayanamsa),
    lagna: { ...placementJson(chart.lagna), lord: chart.lagna.lord },
    planets: chart.planets.map((p) => ({
      key: p.key,
      abbr: p.abbr,
      name: p.sanskrit,
      english: p.english,
      ...placementJson(p),
      house: p.house,
      retrograde: p.retrograde,
      dignity: p.dignity,
    })),
    houses: chart.houses.map((h) => ({
      house: h.house,
      rashi_index: h.rashiIndex,
      rashi: h.rashi,
      sign: h.sign,
      lord: h.lord,
      occupants: h.occupants,
    })),
    moon: { rashi: moon.rashi, sign: moon.sign, nakshatra: moon.nakshatra, pada: moon.pada },
    dasha: chart.dasha
      ? {
        mahadasha: chart.dasha.mahadasha,
        mahadasha_planet: chart.dasha.mahadashaPlanet,
        maha_phase: chart.dasha.mahaPhase,
        antardasha: chart.dasha.antardasha,
        antardasha_planet: chart.dasha.antardashaPlanet,
        antar_phase: chart.dasha.antarPhase,
        sequence: chart.dasha.sequence.map((s) => ({
          lord: s.lord,
          planet: s.planet,
          start_year: s.startYear,
          end_year: s.endYear,
          current: s.current,
        })),
      }
      : null,
    transit: {
      as_of: chart.transit.asOf,
      jupiter_rashi: chart.transit.jupiterRashi,
      jupiter_house_from_moon: chart.transit.jupiterHouseFromMoon,
    },
  };
}
