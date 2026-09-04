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
function wrap360(degrees: number): number {
  const x = degrees % 360;
  return x < 0 ? x + 360 : x;
}

function sin(degrees: number): number {
  return Math.sin(degrees * DEG);
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
function centuries(jd: number): number {
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
const NAKSHATRA_SPAN = 360 / 27;

// ---------------------------------------------------------------- the chart

export interface Chart {
  /** The Moon's rashi — in jyotish, "your sign" means this, not the Sun's. */
  moonRashi: string;
  moonRashiEnglish: string;

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

  /** The Sun's rashi. Steady for a month, so it survives an unknown birth time. */
  sunRashi: string;
  sunRashiEnglish: string;

  /** True when a birth time was supplied and the reading is at its full precision. */
  precise: boolean;
}

export interface BirthDetails {
  /** `YYYY-MM-DD`, as `users.dob` stores it. */
  dob: string;

  /** `HH:MM` or `HH:MM:SS`, as `users.birth_time` stores it. Null when unknown. */
  birthTime?: string | null;

  /** Hours east of UTC. Defaults to [IST_OFFSET_HOURS]; see the note there. */
  timezoneOffsetHours?: number;
}

/**
 * The chart, or null when the date of birth is unusable.
 *
 * Null rather than a thrown error or a guessed date: a user who never finished onboarding still
 * gets to talk to the sage, just without a chart, and the prompt handles that case explicitly.
 *
 * With no birth time the Moon is computed for noon local — the middle of the day, so the worst
 * case is half a day of error rather than a whole one — and the nakshatra is withheld. The rashi
 * survives because the Moon needs about two and a quarter days to cross one, so noon is right far
 * more often than not.
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

  // Noon local when the hour is unknown: the middle of the day bounds the error at ±12 hours
  // rather than ±24.
  const localHours = clock ?? 12;
  const utcHours = localHours - offset;

  const jd = julianDay(year, month, day, utcHours);

  const moon = toSidereal(moonLongitude(jd), jd);
  const sun = toSidereal(sunLongitude(jd), jd);

  const moonRashi = RASHIS[Math.floor(moon / 30) % 12];
  const sunRashi = RASHIS[Math.floor(sun / 30) % 12];

  const precise = clock !== null;
  const nakshatraIndex = Math.floor(moon / NAKSHATRA_SPAN) % 27;

  return {
    moonRashi,
    moonRashiEnglish: RASHI_ENGLISH[moonRashi],
    nakshatra: precise ? NAKSHATRAS[nakshatraIndex] : null,
    pada: precise
      ? Math.floor((moon % NAKSHATRA_SPAN) / (NAKSHATRA_SPAN / 4)) + 1
      : null,
    sunRashi,
    sunRashiEnglish: RASHI_ENGLISH[sunRashi],
    precise,
  };
}

/** `HH:MM[:SS]` to fractional hours, or null when it is not a time. */
function parseClock(raw: string | null | undefined): number | null {
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
export function describeChart(chart: Chart | null): string {
  if (!chart) return "";

  const lines = [
    `Moon (Chandra) in ${chart.moonRashi} (${chart.moonRashiEnglish}) — this is the person's ` +
    `rashi, the sign that matters most in jyotish.`,
    `Sun (Surya) in ${chart.sunRashi} (${chart.sunRashiEnglish}).`,
  ];

  if (chart.nakshatra) {
    lines.push(`Nakshatra: ${chart.nakshatra}, pada ${chart.pada}.`);
  } else {
    lines.push(
      "Nakshatra: UNKNOWN, because the birth time was never given. Do not name one. If the " +
        "moment is right, ask for the hour of birth — it is what a nakshatra needs.",
    );
  }

  return lines.join("\n");
}
