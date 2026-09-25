/**
 * The part of a reading that is arithmetic rather than language.
 *
 * Everything else this app says is written by a model. This is not: given a birth date and time
 * it computes where the Sun and Moon actually were, and which rashi and nakshatra that puts them
 * in. The sage is then instructed to cite the result, exactly as a palm reading is instructed to
 * cite something visible on the hand — see CHAT_GROUNDING in `astro_chat.ts`. A chart the model
 * invented would be indistinguishable from a horoscope column; one it has to work from is not.
 *
 * Pure: no network, no key, no clock of its own. All of it is testable, and
 * `tests/jyotish_test.ts` anchors it on Meeus's own published worked examples.
 *
 * The algorithms are from Jean Meeus, *Astronomical Algorithms* (2nd ed.):
 *   - Sun's apparent longitude — chapter 25
 *   - Moon's longitude — chapter 47, the largest terms of the ELP-2000/82 series
 *
 * Accuracy is far better than this application needs. The Moon terms below land inside ~0.02°,
 * against a nakshatra 13°20' wide and a pada 3°20' wide. That margin is not gold-plating: the
 * Moon travels ~13.2° a day, so a nakshatra lasts barely a day, and a lazy series would routinely
 * name the one next door.
 */

const DEG = Math.PI / 180;

/** Normalises to [0, 360). */
export function wrap360(degrees: number): number {
  const x = degrees % 360;
  return x < 0 ? x + 360 : x;
}

function sin(degrees: number): number {
  return Math.sin(degrees * DEG);
}

function cos(degrees: number): number {
  return Math.cos(degrees * DEG);
}

/** atan2 in degrees, wrapped to [0, 360). */
function atan2d(y: number, x: number): number {
  return wrap360(Math.atan2(y, x) / DEG);
}

// ---------------------------------------------------------------- time

/**
 * India Standard Time, in hours.
 *
 * Every account is Indian: `users.mobile_no` carries a CHECK of `^[6-9][0-9]{9}$`, and OTP is
 * sent through Fast2SMS, which is India-only. So a birth time typed into this app is IST unless
 * something changes.
 *
 * A named constant rather than a bare 5.5 in the arithmetic, because this is the assumption most
 * likely to become wrong and least likely to announce itself when it does: an hour of error moves
 * the Moon half a degree, which is a wrong pada, and five and a half hours can be a wrong
 * nakshatra. The day Astrolok signs up someone abroad, this is the line to find.
 */
export const IST_OFFSET_HOURS = 5.5;

/**
 * Julian Day for a civil date and time, Gregorian calendar.
 *
 * Meeus chapter 7. Valid for every year this application can see — `users.dob` is checked to be
 * on or after 1900-01-01.
 */
export function julianDay(
  year: number,
  month: number,
  day: number,
  hoursUtc = 0,
): number {
  let y = year;
  let m = month;
  if (m <= 2) {
    y -= 1;
    m += 12;
  }

  const a = Math.floor(y / 100);
  const b = 2 - a + Math.floor(a / 4);

  return Math.floor(365.25 * (y + 4716)) +
    Math.floor(30.6001 * (m + 1)) +
    day + b - 1524.5 +
    hoursUtc / 24;
}

/** Julian centuries from J2000.0, the argument every series below is written in. */
export function centuries(jd: number): number {
  return (jd - 2451545.0) / 36525;
}

// ---------------------------------------------------------------- the Sun

/**
 * The Sun's apparent geocentric longitude, in degrees. Meeus chapter 25.
 *
 * The equation of centre alone gets within ~0.01°, which is three orders of magnitude finer than
 * the 30° sign it is used to pick.
 */
export function sunLongitude(jd: number): number {
  const t = centuries(jd);

  // Geometric mean longitude.
  const l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;

  // Mean anomaly.
  const m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t;

  // Equation of the centre.
  const c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(m) +
    (0.019993 - 0.000101 * t) * sin(2 * m) +
    0.000289 * sin(3 * m);

  const trueLongitude = l0 + c;

  // Apparent longitude: nutation and aberration, from the Moon's ascending node.
  const omega = 125.04 - 1934.136 * t;
  return wrap360(trueLongitude - 0.00569 - 0.00478 * sin(omega));
}

// ---------------------------------------------------------------- the Moon

/**
 * Periodic terms for the Moon's longitude, Meeus table 47.A.
 *
 * `[D, M, M', F, coefficient]`, the coefficient in units of 1e-6 degrees. These are the largest
 * terms of the table, in descending order of magnitude; the omitted remainder sums to well under
 * 0.01°.
 *
 * Terms whose argument involves M — the Sun's mean anomaly — are multiplied by the eccentricity
 * correction E, because the Earth's orbit is not the circle the series pretends it is.
 */
const MOON_TERMS: ReadonlyArray<readonly [number, number, number, number, number]> = [
  [0, 0, 1, 0, 6288774],
  [2, 0, -1, 0, 1274027],
  [2, 0, 0, 0, 658314],
  [0, 0, 2, 0, 213618],
  [0, 1, 0, 0, -185116],
  [0, 0, 0, 2, -114332],
  [2, 0, -2, 0, 58793],
  [2, -1, -1, 0, 57066],
  [2, 0, 1, 0, 53322],
  [2, -1, 0, 0, 45758],
  [0, 1, -1, 0, -40923],
  [1, 0, 0, 0, -34720],
  [0, 1, 1, 0, -30383],
  [2, 0, 0, -2, 15327],
  [0, 0, 1, 2, -12528],
  [0, 0, 1, -2, 10980],
  [4, 0, -1, 0, 10675],
  [0, 0, 3, 0, 10034],
  [4, 0, -2, 0, 8548],
  [2, 1, -1, 0, -7888],
  [2, 1, 0, 0, -6766],
  [1, 0, -1, 0, -5163],
  [1, 1, 0, 0, 4987],
  [2, -1, 1, 0, 4036],
  [2, 0, 2, 0, 3994],
  [4, 0, 0, 0, 3861],
  [2, 0, -3, 0, 3665],
  [0, 1, -2, 0, -2689],
  [2, 0, -1, 2, -2602],
  [2, -1, -2, 0, 2390],
  [1, 0, 1, 0, -2348],
  [2, -2, 0, 0, 2236],
  [0, 1, 2, 0, -2120],
  [0, 2, 0, 0, -2069],
  [2, -2, -1, 0, 2048],
  [2, 0, 1, -2, -1773],
  [2, 0, 0, 2, -1595],
  [4, -1, -1, 0, 1215],
  [0, 0, 2, 2, -1110],
  [3, 0, -1, 0, -892],
  [2, 1, 1, 0, -810],
  [4, -1, -2, 0, 759],
  [0, 2, -1, 0, -713],
  [2, 2, -1, 0, -700],
  [2, 1, -2, 0, 691],
  [2, -1, 0, -2, 596],
  [4, 0, 1, 0, 549],
  [0, 0, 4, 0, 537],
  [4, -1, 0, 0, 520],
  [1, 0, -2, 0, -487],
];

/**
 * The Moon's geocentric longitude, in degrees. Meeus chapter 47.
 *
 * Apparent longitude is not computed: nutation is at most ~17", and the sidereal conversion below
 * subtracts an ayanamsa carrying more uncertainty than that.
 */
export function moonLongitude(jd: number): number {
  const t = centuries(jd);
  const t2 = t * t;
  const t3 = t2 * t;
  const t4 = t3 * t;

  // Moon's mean longitude.
  const lPrime = 218.3164477 + 481267.88123421 * t - 0.0015786 * t2 +
    t3 / 538841 - t4 / 65194000;

  // Mean elongation of the Moon from the Sun.
  const d = 297.8501921 + 445267.1114034 * t - 0.0018819 * t2 +
    t3 / 545868 - t4 / 113065000;

  // Sun's mean anomaly.
  const m = 357.5291092 + 35999.0502909 * t - 0.0001536 * t2 + t3 / 24490000;

  // Moon's mean anomaly.
  const mPrime = 134.9633964 + 477198.8675055 * t + 0.0087414 * t2 +
    t3 / 69699 - t4 / 14712000;

  // Moon's argument of latitude.
  const f = 93.2720950 + 483202.0175233 * t - 0.0036539 * t2 -
    t3 / 3526000 + t4 / 863310000;

  // Eccentricity of the Earth's orbit around the Sun.
  const e = 1 - 0.002516 * t - 0.0000074 * t2;

  let sum = 0;
  for (const [cd, cm, cmp, cf, coefficient] of MOON_TERMS) {
    const argument = cd * d + cm * m + cmp * mPrime + cf * f;
    // E once for a term linear in M, twice for one quadratic in it.
    const eccentricity = cm === 0 ? 1 : (Math.abs(cm) === 1 ? e : e * e);
    sum += coefficient * eccentricity * sin(argument);
  }

  // Additive corrections from Venus, Jupiter and the flattening of the Earth.
  const a1 = 119.75 + 131.849 * t;
  const a2 = 53.09 + 479264.290 * t;
  sum += 3958 * sin(a1) + 1962 * sin(lPrime - f) + 318 * sin(a2);

  return wrap360(lPrime + sum / 1_000_000);
}

// ---------------------------------------------------------------- sidereal

/**
 * Lahiri (Chitrapaksha) ayanamsa, in degrees — the offset between the tropical zodiac the
 * arithmetic above produces and the sidereal one Indian astrology uses.
 *
 * Linear: 23.85312° at J2000.0, precessing at 50.2388" a year. The true rate wobbles slightly,
 * but across the century of birth dates this app can hold the error stays inside an arcminute,
 * and the nakshatra it is used to pick is 800 arcminutes wide.
 *
 * Lahiri specifically, not Raman or Krishnamurti: it is the Indian government's official
 * ayanamsa and the one every published panchang uses, so a user checking this against their
 * family's almanac should find them agreeing.
 */
export function ayanamsa(jd: number): number {
  return 23.85312 + centuries(jd) * 100 * (50.2388 / 3600);
}

/** Tropical longitude to sidereal. */
export function toSidereal(tropicalLongitude: number, jd: number): number {
  return wrap360(tropicalLongitude - ayanamsa(jd));
}

// ---------------------------------------------------------------- the sky at a place
//
// Everything above is enough for the chat, which only ever needs the Moon and the Sun. A full
// kundali needs the rest of the grahas and the lagna, and the lagna needs a place as well as a
// moment. `kundali_chart.ts` assembles these; they live here so the astronomy stays in one file.

/** Mean obliquity of the ecliptic, in degrees. Meeus 22.2. */
export function meanObliquity(jd: number): number {
  const t = centuries(jd);
  return 23.4392911 - (46.8150 * t + 0.00059 * t * t - 0.001813 * t * t * t) / 3600;
}

/**
 * Mean sidereal time at Greenwich, in degrees, for a Julian Day in UT. Meeus 12.4.
 *
 * Mean rather than apparent: the difference is nutation in right ascension, never more than about
 * a second of time, and the lagna it feeds moves a degree every four minutes.
 */
export function greenwichSiderealTime(jd: number): number {
  const t = centuries(jd);
  return wrap360(
    280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t -
      t * t * t / 38710000,
  );
}

/**
 * Longitude of the Moon's mean ascending node — Rahu — in degrees, tropical. Meeus 47.7.
 *
 * The mean node rather than the true one, which is what the Lahiri ephemeris and most Indian
 * almanacs print. The two never differ by more than about a degree and a half. Ketu is always the
 * point opposite.
 */
export function meanRahu(jd: number): number {
  const t = centuries(jd);
  return wrap360(
    125.0445479 - 1934.1362891 * t + 0.0020754 * t * t + t * t * t / 467441 -
      t * t * t * t / 60616000,
  );
}

/**
 * The tropical ascendant — the point of the ecliptic rising on the eastern horizon — in degrees.
 *
 * `longitudeEast` is degrees east of Greenwich. Latitude is clamped inside the polar circles,
 * where for part of every day no single point of the ecliptic is rising and the formula stops
 * meaning anything; nobody this app will ever chart was born there.
 */
export function ascendant(jd: number, latitude: number, longitudeEast: number): number {
  const ramc = wrap360(greenwichSiderealTime(jd) + longitudeEast);
  const eps = meanObliquity(jd);
  const phi = Math.max(-66, Math.min(66, latitude));
  return atan2d(cos(ramc), -(sin(ramc) * cos(eps) + Math.tan(phi * DEG) * sin(eps)));
}

export type Graha = "mercury" | "venus" | "mars" | "jupiter" | "saturn";

/**
 * Low-precision orbital elements, from Paul Schlyter's "How to compute planetary positions".
 *
 * Each is `[base, rate per day]` for d = days from 2000 Jan 0.0. N and w already carry precession,
 * so the longitudes come out referred to the equinox of date — tropical, ready for [toSidereal].
 *
 * Chosen over the JPL approximate-elements table, whose Jupiter and Saturn drift by several
 * arcminutes, and over full VSOP87, which is thousands of terms. With the perturbations in
 * [planetLongitude] these land within an arcminute or two: fine enough for a sign, a nakshatra and
 * a house, and the house is what a kundali is read from.
 */
const ELEMENTS: Record<
  Graha | "sun",
  { N: [number, number]; i: [number, number]; w: [number, number]; a: number; e: [number, number]; M: [number, number] }
> = {
  sun: { N: [0, 0], i: [0, 0], w: [282.9404, 4.70935e-5], a: 1, e: [0.016709, -1.151e-9], M: [356.0470, 0.9856002585] },
  mercury: { N: [48.3313, 3.24587e-5], i: [7.0047, 5.00e-8], w: [29.1241, 1.01444e-5], a: 0.387098, e: [0.205635, 5.59e-10], M: [168.6562, 4.0923344368] },
  venus: { N: [76.6799, 2.46590e-5], i: [3.3946, 2.75e-8], w: [54.8910, 1.38374e-5], a: 0.723330, e: [0.006773, -1.302e-9], M: [48.0052, 1.6021302244] },
  mars: { N: [49.5574, 2.11081e-5], i: [1.8497, -1.78e-8], w: [286.5016, 2.92961e-5], a: 1.523688, e: [0.093405, 2.516e-9], M: [18.6021, 0.5240207766] },
  jupiter: { N: [100.4542, 2.76854e-5], i: [1.3030, -1.557e-7], w: [273.8777, 1.64505e-5], a: 5.20256, e: [0.048498, 4.469e-9], M: [19.8950, 0.0830853001] },
  saturn: { N: [113.6634, 2.38980e-5], i: [2.4886, -1.081e-7], w: [339.3939, 2.97661e-5], a: 9.55475, e: [0.055546, -9.499e-9], M: [316.9670, 0.0334442282] },
};

/** A position in the plane of its own orbit: distance and true anomaly plus perihelion. */
function orbitalPosition(body: Graha | "sun", d: number) {
  const el = ELEMENTS[body];
  const at = ([base, rate]: [number, number]) => base + rate * d;
  const N = at(el.N);
  const i = at(el.i);
  const w = at(el.w);
  const e = at(el.e);
  const M = wrap360(at(el.M));

  // Kepler's equation, iterated. Mercury's eccentricity is the largest here and still converges in
  // a handful of steps.
  let E = M + (e / DEG) * sin(M) * (1 + e * cos(M));
  for (let step = 0; step < 10; step++) {
    const next = E - (E - (e / DEG) * sin(E) - M) / (1 - e * cos(E));
    if (Math.abs(next - E) < 1e-6) {
      E = next;
      break;
    }
    E = next;
  }

  const xv = el.a * (cos(E) - e);
  const yv = el.a * Math.sqrt(1 - e * e) * sin(E);
  return { N, i, w, M, v: atan2d(yv, xv), r: Math.hypot(xv, yv) };
}

/**
 * A graha's geocentric ecliptic longitude, tropical, in degrees, for a Julian Day in UT.
 *
 * Heliocentric from [ELEMENTS], corrected for the mutual pull of Jupiter and Saturn — the two
 * large terms that otherwise leave Saturn nearly a degree out — then moved to the Earth by adding
 * the Sun's position. Light-time is ignored; it never shifts a longitude by more than a fraction
 * of an arcminute.
 */
export function planetLongitude(planet: Graha, jd: number): number {
  const d = jd - 2451543.5;
  const p = orbitalPosition(planet, d);

  const u = p.v + p.w;
  const xh = p.r * (cos(p.N) * cos(u) - sin(p.N) * sin(u) * cos(p.i));
  const yh = p.r * (sin(p.N) * cos(u) + cos(p.N) * sin(u) * cos(p.i));
  const zh = p.r * sin(u) * sin(p.i);

  let lon = atan2d(yh, xh);
  let lat = Math.atan2(zh, Math.hypot(xh, yh)) / DEG;

  if (planet === "jupiter" || planet === "saturn") {
    const mj = wrap360(ELEMENTS.jupiter.M[0] + ELEMENTS.jupiter.M[1] * d);
    const ms = wrap360(ELEMENTS.saturn.M[0] + ELEMENTS.saturn.M[1] * d);
    if (planet === "jupiter") {
      lon += -0.332 * sin(2 * mj - 5 * ms - 67.6) -
        0.056 * sin(2 * mj - 2 * ms + 21) +
        0.042 * sin(3 * mj - 5 * ms + 21) -
        0.036 * sin(mj - 2 * ms) +
        0.022 * cos(mj - ms) +
        0.023 * sin(2 * mj - 3 * ms + 52) -
        0.016 * sin(mj - 5 * ms - 69);
    } else {
      lon += 0.812 * sin(2 * mj - 5 * ms - 67.6) -
        0.229 * cos(2 * mj - 4 * ms - 2) +
        0.119 * sin(mj - 2 * ms - 3) +
        0.046 * sin(2 * mj - 6 * ms - 69) +
        0.014 * sin(mj - 3 * ms + 32);
      lat += -0.020 * cos(2 * mj - 4 * ms - 2) + 0.018 * sin(2 * mj - 6 * ms - 49);
    }
  }

  const x = p.r * cos(lon) * cos(lat);
  const y = p.r * sin(lon) * cos(lat);

  // The Sun as seen from the Earth, in the same low-precision frame, so the two cancel cleanly.
  const s = orbitalPosition("sun", d);
  const sunLon = wrap360(s.v + s.w);

  return atan2d(y + s.r * sin(sunLon), x + s.r * cos(sunLon));
}

/**
 * Whether a body is moving backwards along the ecliptic at [jd]: a central difference across a
 * day. A station, where the speed is momentarily zero, reads as direct.
 */
export function isRetrograde(longitudeAt: (jd: number) => number, jd: number): boolean {
  let delta = longitudeAt(jd + 0.5) - longitudeAt(jd - 0.5);
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  return delta < 0;
}

// ---------------------------------------------------------------- the names

/** The twelve rashis, in order from 0° sidereal. */
export const RASHIS = [
  "Mesha",
  "Vrishabha",
  "Mithuna",
  "Karka",
  "Simha",
  "Kanya",
  "Tula",
  "Vrischika",
  "Dhanu",
  "Makara",
  "Kumbha",
  "Meena",
] as const;

/** What each rashi is in English, for the one place the sage glosses it. */
export const RASHI_ENGLISH: Record<string, string> = {
  Mesha: "the Ram",
  Vrishabha: "the Bull",
  Mithuna: "the Twins",
  Karka: "the Crab",
  Simha: "the Lion",
  Kanya: "the Maiden",
  Tula: "the Scales",
  Vrischika: "the Scorpion",
  Dhanu: "the Archer",
  Makara: "the Crocodile",
  Kumbha: "the Water-bearer",
  Meena: "the Fishes",
};

/** The twenty-seven nakshatras, in order from 0° sidereal. */
export const NAKSHATRAS = [
  "Ashwini",
  "Bharani",
  "Krittika",
  "Rohini",
  "Mrigashira",
  "Ardra",
  "Punarvasu",
  "Pushya",
  "Ashlesha",
  "Magha",
  "Purva Phalguni",
  "Uttara Phalguni",
  "Hasta",
  "Chitra",
  "Swati",
  "Vishakha",
  "Anuradha",
  "Jyeshtha",
  "Mula",
  "Purva Ashadha",
  "Uttara Ashadha",
  "Shravana",
  "Dhanishta",
  "Shatabhisha",
  "Purva Bhadrapada",
  "Uttara Bhadrapada",
  "Revati",
] as const;

/** One nakshatra: 360 / 27. */
export const NAKSHATRA_SPAN = 360 / 27;

/**
 * The names a rashi actually goes by, as people type them.
 *
 * Sanskrit as this module spells it, the shorter Hindi forms ("Makar", "Kumbh"), Devanagari, and
 * the English names — which in India are used as translations of the rashi, not as a separate
 * Western system. Deliberately no alias that is also a common name or surname ("Singh", "Mina"):
 * this runs over whatever the sage recorded, and a surname must not become somebody's sign.
 */
const RASHI_ALIASES: Record<typeof RASHIS[number], readonly string[]> = {
  Mesha: ["mesha", "mesh", "मेष", "aries"],
  Vrishabha: ["vrishabha", "vrishabh", "vrishab", "vrushabh", "brishabh", "वृषभ", "taurus"],
  Mithuna: ["mithuna", "mithun", "मिथुन", "gemini"],
  Karka: ["karka", "kark", "karkat", "karkata", "कर्क", "cancer"],
  Simha: ["simha", "simh", "sinh", "सिंह", "leo"],
  Kanya: ["kanya", "कन्या", "virgo"],
  Tula: ["tula", "तुला", "libra"],
  Vrischika: [
    "vrischika",
    "vrischik",
    "vrishchika",
    "vrishchik",
    "vruschik",
    "vrushchik",
    "वृश्चिक",
    "scorpio",
  ],
  Dhanu: ["dhanu", "dhanus", "dhanur", "धनु", "sagittarius"],
  Makara: ["makara", "makar", "मकर", "capricorn"],
  Kumbha: ["kumbha", "kumbh", "कुंभ", "कुम्भ", "aquarius"],
  Meena: ["meena", "meen", "मीन", "pisces"],
};

/**
 * The rashi a piece of text names, spelled as [RASHIS] spells it, or null.
 *
 * Whole words only, with Unicode-aware edges — `\b` knows nothing about Devanagari, whose vowel
 * signs are marks rather than letters. When a sentence names more than one, the first one named
 * wins.
 */
export function rashiFromName(raw: string | null | undefined): string | null {
  const said = (raw ?? "").toLowerCase();
  if (!said.trim()) return null;

  let found: { rashi: string; at: number } | null = null;
  for (const rashi of RASHIS) {
    for (const alias of RASHI_ALIASES[rashi]) {
      const match = new RegExp(`(?<![\\p{L}\\p{M}])${alias}(?![\\p{L}\\p{M}])`, "u").exec(said);
      if (match && (found === null || match.index < found.at)) {
        found = { rashi, at: match.index };
      }
    }
  }

  return found?.rashi ?? null;
}

// ---------------------------------------------------------------- the dasha

/**
 * The Vimshottari cycle: nine grahas in their fixed order, and the years each one's period runs.
 *
 * The nakshatra the Moon sat in at birth names whose period a life opens in — the nine lords
 * repeat three times through the twenty-seven, starting with Ketu at Ashwini — and how far through
 * that nakshatra the Moon had travelled is how much of the opening period was already spent.
 */
export const DASHA_LORDS: ReadonlyArray<readonly [string, number]> = [
  ["Ketu", 7],
  ["Shukra", 20],
  ["Surya", 6],
  ["Chandra", 10],
  ["Mangal", 7],
  ["Rahu", 18],
  ["Guru", 16],
  ["Shani", 19],
  ["Budh", 17],
];

/** The whole cycle, in years. */
export const DASHA_CYCLE_YEARS = 120;

/** Julian years, the convention the common published dasha tables are computed in. */
const DASHA_YEAR_DAYS = 365.25;

export type DashaPhase = "early" | "middle" | "late";

/**
 * The periods running at a moment, and roughly where in each that moment falls.
 *
 * A third of the way rather than a date, on purpose. A period's end date handed to a language
 * model is a year waiting to be repeated to someone, so this is what every prompt up to chat v3
 * sees: "late in Shani's Mahadasha" is the tradition's own way of saying it without the calendar.
 * Chat v4 names years deliberately, and gets them from [antardashaSequence] instead, where the
 * dates are explicit rather than something to be read out of a phase.
 */
export interface Dasha {
  mahadasha: string;
  mahaPhase: DashaPhase;
  antardasha: string;
  antarPhase: DashaPhase;
}

/**
 * The Vimshottari Mahadasha and Antardasha at [asOfJd], for a Moon at [moonSidereal] at [birthJd].
 *
 * Only meaningful with a birth hour: the opening balance comes from the Moon's position inside
 * its nakshatra, and a day's uncertainty is a whole nakshatra — so [computeChart] withholds this
 * exactly when it withholds the nakshatra. Null for a moment before birth or unusable input.
 */
export function vimshottariDasha(
  moonSidereal: number,
  birthJd: number,
  asOfJd: number,
): Dasha | null {
  if (![moonSidereal, birthJd, asOfJd].every(Number.isFinite) || asOfJd < birthJd) return null;

  const longitude = wrap360(moonSidereal);
  let lord = Math.floor(longitude / NAKSHATRA_SPAN) % 9;
  const travelled = (longitude % NAKSHATRA_SPAN) / NAKSHATRA_SPAN;

  // The opening period began before birth, by the share of it the Moon had already travelled.
  let start = birthJd - travelled * DASHA_LORDS[lord][1] * DASHA_YEAR_DAYS;

  // Two full cycles is 240 years, which no birth date this app accepts can reach.
  for (let step = 0; step < 18; step++) {
    const length = DASHA_LORDS[lord][1] * DASHA_YEAR_DAYS;

    if (asOfJd < start + length) {
      // The sub-periods open with the Mahadasha's own lord and follow the same order.
      let subStart = start;
      for (let k = 0; k < 9; k++) {
        const sub = (lord + k) % 9;
        const subLength = length * DASHA_LORDS[sub][1] / DASHA_CYCLE_YEARS;

        // The last one takes whatever floating point leaves over, so the walk cannot fall off.
        if (asOfJd < subStart + subLength || k === 8) {
          return {
            mahadasha: DASHA_LORDS[lord][0],
            mahaPhase: phaseOf((asOfJd - start) / length),
            antardasha: DASHA_LORDS[sub][0],
            antarPhase: phaseOf((asOfJd - subStart) / subLength),
          };
        }
        subStart += subLength;
      }
    }

    start += length;
    lord = (lord + 1) % 9;
  }

  return null;
}

/** One Mahadasha as a span of Julian Days. */
export interface DashaPeriod {
  lord: string;
  startJd: number;
  endJd: number;
}

/**
 * The nine Mahadashas from birth: the opening one (already partly spent at birth, so its start is
 * before [birthJd]) and the eight that follow it.
 *
 * Dates, unlike [vimshottariDasha]. This feeds the kundali's timeline table, which is computed
 * fact printed beside the chart — never the model's prompt. The chat's timing windows are built
 * from [antardashaSequence], one level finer.
 */
export function mahadashaSequence(moonSidereal: number, birthJd: number): DashaPeriod[] {
  if (![moonSidereal, birthJd].every(Number.isFinite)) return [];

  const longitude = wrap360(moonSidereal);
  let lord = Math.floor(longitude / NAKSHATRA_SPAN) % 9;
  const travelled = (longitude % NAKSHATRA_SPAN) / NAKSHATRA_SPAN;
  let start = birthJd - travelled * DASHA_LORDS[lord][1] * DASHA_YEAR_DAYS;

  const periods: DashaPeriod[] = [];
  for (let step = 0; step < 9; step++) {
    const end = start + DASHA_LORDS[lord][1] * DASHA_YEAR_DAYS;
    periods.push({ lord: DASHA_LORDS[lord][0], startJd: start, endJd: end });
    start = end;
    lord = (lord + 1) % 9;
  }
  return periods;
}

/** One Antardasha as a span of Julian Days, with the Mahadasha it sits inside. */
export interface AntardashaPeriod {
  mahadasha: string;
  antardasha: string;
  startJd: number;
  endJd: number;
}

/**
 * The Antardashas that overlap [fromJd, toJd], in order — the one running at [fromJd] first.
 *
 * Dates, like [mahadashaSequence], and one level finer: the sub-periods are what the tradition
 * times an event by, since a Mahadasha of up to twenty years is too wide to answer "when" with.
 * Each opens with its Mahadasha's own lord and runs for its share of it, exactly as
 * [vimshottariDasha] walks them, so the period this names for [fromJd] is always the one that
 * function reports as running.
 */
export function antardashaSequence(
  moonSidereal: number,
  birthJd: number,
  fromJd: number,
  toJd: number,
): AntardashaPeriod[] {
  if (![fromJd, toJd].every(Number.isFinite) || toJd <= fromJd) return [];

  const spans: AntardashaPeriod[] = [];
  for (const maha of mahadashaSequence(moonSidereal, birthJd)) {
    if (maha.endJd <= fromJd) continue;
    if (maha.startJd >= toJd) break;

    const first = DASHA_LORDS.findIndex(([name]) => name === maha.lord);
    const length = maha.endJd - maha.startJd;
    let subStart = maha.startJd;

    for (let k = 0; k < 9; k++) {
      const sub = (first + k) % 9;
      // The last one ends where its Mahadasha does, so floating point cannot leave a gap.
      const subEnd = k === 8
        ? maha.endJd
        : subStart + length * DASHA_LORDS[sub][1] / DASHA_CYCLE_YEARS;

      if (subEnd > fromJd && subStart < toJd) {
        spans.push({
          mahadasha: maha.lord,
          antardasha: DASHA_LORDS[sub][0],
          startJd: subStart,
          endJd: subEnd,
        });
      }
      subStart = subEnd;
    }
  }
  return spans;
}

function phaseOf(fraction: number): DashaPhase {
  if (fraction < 1 / 3) return "early";
  if (fraction < 2 / 3) return "middle";
  return "late";
}

// ---------------------------------------------------------------- the chart

export interface Chart {
  /**
   * The Moon's rashi — in jyotish, "your sign" means this, not the Sun's.
   *
   * Null when it cannot be named honestly: the birth hour is unknown and the Moon changed sign
   * during the day they were born, so either of [moonRashiCandidates] could be theirs. A noon
   * guess used to fill this in, and that is how one account was told Dhanu in one conversation
   * and Makara in the next, once its birth hour arrived.
   */
  moonRashi: string | null;
  moonRashiEnglish: string | null;

  /** One sign when the Moon's rashi is settled; the two it moved between when it is not. */
  moonRashiCandidates: string[];

  /** True when the rashi they told the sage is what settled a day the Moon changed sign. */
  moonRashiStated: boolean;

  /**
   * Null when the birth time is unknown.
   *
   * A nakshatra lasts about a day, so without a time it cannot be named honestly. Returning null
   * is the whole point: the prompt then tells the sage to ask for the hour rather than to invent
   * a nakshatra, which is the failure this field exists to prevent.
   */
  nakshatra: string | null;

  /** 1-4, or null for the same reason as [nakshatra]. */
  pada: number | null;

  /**
   * The Sun's rashi. Steady for a month, so it survives an unknown birth time — except on the one
   * day a month it moves, when it is null for the same reason as [moonRashi].
   */
  sunRashi: string | null;
  sunRashiEnglish: string | null;
  sunRashiCandidates: string[];

  /** True when a birth time was supplied and the reading is at its full precision. */
  precise: boolean;

  /** The periods running at [BirthDetails.asOf]. Null without a birth hour, or without `asOf`. */
  dasha: Dasha | null;

  /**
   * The Antardashas from [BirthDetails.asOf] through the next [PERIOD_HORIZON_YEARS], dated. Null
   * exactly when [dasha] is. What the chat's timing windows are chosen from.
   */
  periods: AntardashaPeriod[] | null;
}

/**
 * How far ahead [Chart.periods] runs. Long enough that a topic whose grahas are all late in the
 * cycle still finds a window; short enough that nothing named is a lifetime away.
 */
export const PERIOD_HORIZON_YEARS = 12;

export interface BirthDetails {
  /** `YYYY-MM-DD`, as `users.dob` stores it. */
  dob: string;

  /** `HH:MM` or `HH:MM:SS`, as `users.birth_time` stores it. Null when unknown. */
  birthTime?: string | null;

  /** Hours east of UTC. Defaults to [IST_OFFSET_HOURS]; see the note there. */
  timezoneOffsetHours?: number;

  /**
   * A rashi they told the sage themselves, in any spelling [rashiFromName] reads.
   *
   * Only ever used to choose between the two signs of a day the Moon changed sign. It never
   * overrules a sign the clock settles: the rashi a person knows is often their naam rashi, from
   * the first letter of their name, and that is not the Moon's.
   */
  statedRashi?: string | null;

  /**
   * The moment to count the dasha to. Absent means no dasha — this module keeps no clock of its
   * own, which is what keeps every result above reproducible in a test.
   */
  asOf?: Date | null;
}

/** The last instant of a local day, in hours. */
const END_OF_DAY = 23 + 59 / 60 + 59 / 3600;

/** Julian Day of a JavaScript instant: the Unix epoch is JD 2440587.5. */
export function julianDayOf(instant: Date): number {
  return instant.getTime() / 86_400_000 + 2440587.5;
}

/**
 * The chart, or null when the date of birth is unusable.
 *
 * Null rather than a thrown error or a guessed date: a user who never finished onboarding still
 * gets to talk to the sage, just without a chart, and the prompt handles that case explicitly.
 *
 * With no birth time the nakshatra is withheld, and a rashi is named only if the sign held for the
 * whole day — both ends of the day are computed, and a sign that differs between them is a sign
 * the clock cannot settle. The Moon needs about two and a quarter days to cross a rashi, so most
 * days pass the check; the ones that do not are exactly the ones a noon guess used to get wrong.
 */
export function computeChart(details: BirthDetails): Chart | null {
  const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(details.dob?.trim() ?? "");
  if (!parts) return null;

  const year = Number(parts[1]);
  const month = Number(parts[2]);
  const day = Number(parts[3]);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  const clock = parseClock(details.birthTime);
  const offset = details.timezoneOffsetHours ?? IST_OFFSET_HOURS;
  const precise = clock !== null;

  const at = (localHours: number) => {
    const jd = julianDay(year, month, day, localHours - offset);
    return {
      jd,
      moon: toSidereal(moonLongitude(jd), jd),
      sun: toSidereal(sunLongitude(jd), jd),
    };
  };

  // Noon when the hour is unknown only feeds what is withheld anyway; the signs come from below.
  const birth = at(clock ?? 12);
  const start = precise ? birth : at(0);
  const end = precise ? birth : at(END_OF_DAY);

  const signsBetween = (from: number, to: number): string[] => {
    const first = rashiOf(from);
    const last = rashiOf(to);
    return first === last ? [first] : [first, last];
  };

  const moonRashiCandidates = signsBetween(start.moon, end.moon);
  const sunRashiCandidates = signsBetween(start.sun, end.sun);

  const stated = rashiFromName(details.statedRashi);
  const moonRashiStated = moonRashiCandidates.length > 1 &&
    stated !== null &&
    moonRashiCandidates.includes(stated);

  const moonRashi = moonRashiCandidates.length === 1
    ? moonRashiCandidates[0]
    : (moonRashiStated ? stated : null);
  const sunRashi = sunRashiCandidates.length === 1 ? sunRashiCandidates[0] : null;

  const nakshatraIndex = Math.floor(birth.moon / NAKSHATRA_SPAN) % 27;

  const asOfJd = precise && details.asOf ? julianDayOf(details.asOf) : null;
  const dasha = asOfJd !== null ? vimshottariDasha(birth.moon, birth.jd, asOfJd) : null;

  return {
    moonRashi,
    moonRashiEnglish: moonRashi ? RASHI_ENGLISH[moonRashi] : null,
    moonRashiCandidates,
    moonRashiStated,
    nakshatra: precise ? NAKSHATRAS[nakshatraIndex] : null,
    pada: precise
      ? Math.floor((birth.moon % NAKSHATRA_SPAN) / (NAKSHATRA_SPAN / 4)) + 1
      : null,
    sunRashi,
    sunRashiEnglish: sunRashi ? RASHI_ENGLISH[sunRashi] : null,
    sunRashiCandidates,
    precise,
    dasha,
    periods: dasha && asOfJd !== null
      ? antardashaSequence(
        birth.moon,
        birth.jd,
        asOfJd,
        asOfJd + PERIOD_HORIZON_YEARS * DASHA_YEAR_DAYS,
      )
      : null,
  };
}

function rashiOf(siderealLongitude: number): string {
  return RASHIS[Math.floor(siderealLongitude / 30) % 12];
}

/**
 * The chart as it travels: to the app inside every user payload, and into `users.chart` as the
 * snapshot `astro-chat` compares against. snake_case like every other field on the wire.
 */
export function chartToJson(chart: Chart | null): Record<string, unknown> | null {
  if (!chart) return null;

  return {
    moon_rashi: chart.moonRashi,
    moon_rashi_english: chart.moonRashiEnglish,
    moon_rashi_candidates: chart.moonRashiCandidates,
    nakshatra: chart.nakshatra,
    pada: chart.pada,
    sun_rashi: chart.sunRashi,
    sun_rashi_english: chart.sunRashiEnglish,
    sun_rashi_candidates: chart.sunRashiCandidates,
    precise: chart.precise,
    mahadasha: chart.dasha?.mahadasha ?? null,
    maha_phase: chart.dasha?.mahaPhase ?? null,
    antardasha: chart.dasha?.antardasha ?? null,
    antar_phase: chart.dasha?.antarPhase ?? null,
  };
}

/** `HH:MM[:SS]` to fractional hours, or null when it is not a time. */
export function parseClock(raw: string | null | undefined): number | null {
  const match = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(raw?.trim() ?? "");
  if (!match) return null;

  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  const seconds = Number(match[3] ?? "0");
  if (hours > 23 || minutes > 59 || seconds > 59) return null;

  return hours + minutes / 60 + seconds / 3600;
}

/**
 * The chart as the sage reads it, for dropping into the prompt.
 *
 * Plain sentences rather than JSON: this goes into a language model, and a sentence is what it is
 * best at using. Empty string when there is no chart, so the caller can concatenate without
 * checking.
 */
export function describeChart(
  chart: Chart | null,
  { dasha = false, years = false }: {
    dasha?: boolean;
    /**
     * The prompt names years from a timing block of its own (chat v4), so the dasha line points
     * there rather than forbidding them. Every earlier prompt keeps the prohibition.
     */
    years?: boolean;
  } = {},
): string {
  if (!chart) return "";

  const lines: string[] = [];

  if (chart.moonRashi) {
    lines.push(
      `Moon (Chandra) in ${chart.moonRashi} (${chart.moonRashiEnglish}) — this is the person's ` +
        `rashi, the sign that matters most in jyotish.`,
    );
    if (chart.moonRashiStated) {
      lines.push(
        `Chandra changed sign on the day they were born. ${chart.moonRashi} is the one of the ` +
          `two they told you is theirs, and that settles it.`,
      );
    }
  } else {
    const [from, to] = chart.moonRashiCandidates;
    lines.push(
      `Moon (Chandra): UNCERTAIN. On the day they were born it moved from ${from} ` +
        `(${RASHI_ENGLISH[from]}) into ${to} (${RASHI_ENGLISH[to]}), and without the hour of ` +
        `birth there is no telling which is their rashi. Do not name either one as their rashi. ` +
        `Ask for the hour of birth — it settles this.`,
    );
  }

  if (chart.sunRashi) {
    lines.push(`Sun (Surya) in ${chart.sunRashi} (${chart.sunRashiEnglish}).`);
  } else {
    const [from, to] = chart.sunRashiCandidates;
    lines.push(
      `Sun (Surya): moved from ${from} into ${to} on the day they were born. Without the hour, ` +
        `do not name either.`,
    );
  }

  if (chart.nakshatra) {
    lines.push(`Nakshatra: ${chart.nakshatra}, pada ${chart.pada}.`);
  } else {
    lines.push(
      "Nakshatra: UNKNOWN, because the birth time was never given. Do not name one. If the " +
        "moment is right, ask for the hour of birth — it is what a nakshatra needs.",
    );
  }

  // Opt-in, so a rollback to a prompt that was never told what a dasha is does not receive one.
  if (dasha) {
    if (chart.dasha) {
      const d = chart.dasha;
      lines.push(
        `Vimshottari dasha running now: the Mahadasha of ${d.mahadasha} (${d.mahaPhase} in its ` +
          `period), and within it the Antardasha of ${d.antardasha} (${d.antarPhase} in its ` +
          `period). ` +
          (years
            ? "Its dates, and the periods after it, are in THE TIMING below."
            : "Never give the year a dasha began or will end."),
      );
    } else {
      lines.push(
        "Dasha: UNKNOWN, because it is counted from the nakshatra, which needs the hour of " +
          "birth. Do not name one.",
      );
    }
  }

  return lines.join("\n");
}
