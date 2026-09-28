/**
 * When, for someone whose hour of birth is not known: the transit windows chat v5 answers from.
 * With the hour, they also answer a matter whose dasha window is years off; see [nearerSeasons].
 *
 * The dasha — `chat_timing.ts` — needs the hour, and a quarter of v3's replies ended by asking for
 * it. Most people do not know it. Their Moon's rashi is usually settled anyway (the Moon needs two
 * and a quarter days to cross a sign), and the tradition has a second clock that runs from the
 * rashi alone: gochar, the transits of the slow grahas over it. Guru's year in a sign is what
 * "agle 12 se 18 mahine shaadi ke liye acche hain, kyonki Guru aapke liye shubh ghar mein aa rahe
 * hain" rests on, and that sentence is the v5 plan's own example.
 *
 * The rule, kept to what the tradition agrees on:
 *
 * - A matter is favoured while Guru occupies, or aspects, the house that holds it, counted from
 *   Chandra's rashi. Guru's aspects are the 5th, 7th and 9th from wherever he stands.
 * - When no such stay falls inside the horizon, the next stay in one of Guru's generally good
 *   houses from the Moon (2, 5, 7, 9, 11) is the window, and it is labelled as general.
 * - Shani is read only for relief. Sade sati and dhaiya are exactly the kind of fear the v5 craft
 *   forbids, so they are named only when they are ending — "Shani's weight lifts by about…".
 *
 * On a day the Moon changed sign, and with no hour to say which side of it they were born on, both
 * rashis are read and each matter gets the season the two agree on ([transitTimingEither]).
 *
 * Positions come from `planetLongitude`, sampled weekly for two years. Guru and Shani both turn
 * retrograde and can step back over a sign edge for a few weeks, so a stay shorter than two months
 * is folded into the one before it: a window that opens and shuts inside a month is noise.
 *
 * Pure, and the clock comes in from outside.
 */

import { julianDayOf, planetLongitude, RASHIS, toSidereal } from "./jyotish.ts";
import {
  ChatTiming,
  monthYear,
  TimingTopic,
  topicLabel,
  V5_TIMING_TOPICS,
} from "./chat_timing.ts";

/** How far ahead the windows are looked for. The v5 plan's longest honest promise. */
const HORIZON_DAYS = 24 * 30.44;

const STEP_DAYS = 7;

/** A stay shorter than this is a retrograde blip, not a stay. */
const MIN_STAY_DAYS = 60;

/** A window already running that closes sooner than this is not offered as "now". */
const MIN_REMAINING_DAYS = 60;

/**
 * Two favourable stays this close together are one season. Guru's retrograde loop takes him back
 * over a sign edge for a few months and forward again, and "November to January, and then July to
 * December" is the same favour interrupted, not two answers.
 */
const MAX_GAP_DAYS = 200;

/** The houses from Chandra each matter lives in. */
const TOPIC_HOUSES: Record<TimingTopic, readonly number[]> = {
  marriage: [7],
  love: [5, 7],
  children: [5],
  career: [10],
  money: [2, 11],
  debt: [6, 11],
  home: [4],
  studies: [5],
};

const HOUSE_NAMES: Record<number, string> = {
  2: "the house of savings",
  4: "the house of home",
  5: "the house of love, children and learning",
  6: "the house of debts",
  7: "the house of marriage",
  10: "the house of work",
  11: "the house of gains",
};

/** Where Guru does good from the Moon whatever the question. */
const GOOD_GURU_HOUSES: readonly number[] = [2, 5, 7, 9, 11];

/** One stretch of a graha in one sign. */
export interface Stay {
  rashiIndex: number;
  startJd: number;
  endJd: number;
}

export interface TransitWindow {
  startJd: number;
  endJd: number;
  now: boolean;

  /** The house from Chandra Guru stands in during it; null when read from either of two rashis. */
  guruHouse: number | null;

  /** The topic house it favours, or null when it is a general window (see file header). */
  favours: number | null;

  /**
   * "occupies" when Guru is in the topic's house, "aspects" when he looks at it; "either" for the
   * season two rashis agree on ([transitTimingEither]), which has no one house.
   */
  how: "occupies" | "aspects" | "general" | "either";
}

export interface TransitTiming {
  asOfJd: number;
  rashi: string;

  /** The two rashis the Moon moved between on their birthday, when [transitTimingEither] read both. */
  either?: readonly [string, string];

  topics: Array<{ topic: TimingTopic; window: TransitWindow | null }>;

  /** Set only when Shani's hard stretch over this rashi is ending, never while it runs. */
  shaniEasing: { endsJd: number; phase: "sade sati" | "dhaiya" } | null;
}

/** 1-based house of [rashiIndex] counted from [moonIndex]. */
function houseFrom(rashiIndex: number, moonIndex: number): number {
  return ((rashiIndex - moonIndex + 12) % 12) + 1;
}

/** The houses Guru influences from [house]: his own, and his 5th, 7th and 9th aspects. */
function guruInfluences(house: number): number[] {
  return [0, 4, 6, 8].map((step) => ((house - 1 + step) % 12) + 1);
}

/**
 * Where [planet] sits, sign by sign, from [fromJd] to [toJd] — retrograde blips folded away.
 *
 * The first stay is kept however short: it is where the graha is now, and "now" is true even if
 * it is about to move on.
 */
export function stays(planet: "jupiter" | "saturn", fromJd: number, toJd: number): Stay[] {
  const signAt = (jd: number) =>
    Math.floor(toSidereal(planetLongitude(planet, jd), jd) / 30) % 12;

  const raw: Stay[] = [];
  for (let jd = fromJd; jd < toJd; jd += STEP_DAYS) {
    const rashiIndex = signAt(jd);
    const last = raw[raw.length - 1];
    if (last && last.rashiIndex === rashiIndex) {
      last.endJd = Math.min(jd + STEP_DAYS, toJd);
    } else {
      raw.push({ rashiIndex, startJd: jd, endJd: Math.min(jd + STEP_DAYS, toJd) });
    }
  }

  // Fold short stays (after the first) into the one before, then merge neighbours of one sign.
  const folded: Stay[] = [];
  for (const stay of raw) {
    const last = folded[folded.length - 1];
    const short = stay.endJd - stay.startJd < MIN_STAY_DAYS;
    const ongoing = stay.endJd >= toJd;
    if (last && (last.rashiIndex === stay.rashiIndex || (short && !ongoing))) {
      last.endJd = stay.endJd;
    } else {
      folded.push({ ...stay });
    }
  }
  return folded;
}

/**
 * The transit windows for [rashi] from [asOf], or null for a sign this module cannot read.
 *
 * The caller decides which rashi: the computed one when the day settles it, a stated one only
 * when it is one of the two signs the Moon crossed that day. A naam rashi, from the first letter
 * of a name, is not the Moon's and must never be given here.
 */
export function transitTiming(rashi: string | null, asOf: Date): TransitTiming | null {
  const moonIndex = RASHIS.indexOf(rashi as typeof RASHIS[number]);
  if (moonIndex < 0) return null;

  const asOfJd = julianDayOf(asOf);
  const untilJd = asOfJd + HORIZON_DAYS;
  const guru = stays("jupiter", asOfJd, untilJd);

  const usable = (window: TransitWindow) =>
    !(window.now && window.endJd - asOfJd < MIN_REMAINING_DAYS);

  const windowFor = (stay: Stay, favours: number | null, how: TransitWindow["how"]) => {
    const startJd = Math.max(stay.startJd, asOfJd);
    return {
      startJd,
      endJd: Math.min(stay.endJd, untilJd),
      now: startJd <= asOfJd,
      guruHouse: houseFrom(stay.rashiIndex, moonIndex),
      favours,
      how,
    };
  };

  const topics = V5_TIMING_TOPICS.map((topic) => {
    // Every favourable stay, in order, then the first season they make once a retrograde dip
    // between two of them is bridged.
    const favourable = guru.flatMap((stay) => {
      const house = houseFrom(stay.rashiIndex, moonIndex);
      const target = TOPIC_HOUSES[topic].find((t) => guruInfluences(house).includes(t));
      if (target === undefined) return [];
      return [windowFor(stay, target, target === house ? "occupies" : "aspects")];
    });

    const seasons: TransitWindow[] = [];
    for (const window of favourable) {
      const last = seasons[seasons.length - 1];
      if (last && window.startJd - last.endJd <= MAX_GAP_DAYS) {
        last.endJd = window.endJd;
      } else {
        seasons.push({ ...window });
      }
    }

    const season = seasons.find(usable);
    if (season) return { topic, window: season };

    for (const stay of guru) {
      if (!GOOD_GURU_HOUSES.includes(houseFrom(stay.rashiIndex, moonIndex))) continue;
      const window = windowFor(stay, null, "general");
      if (usable(window)) return { topic, window };
    }

    return { topic, window: null };
  });

  return { asOfJd, rashi: RASHIS[moonIndex], topics, shaniEasing: shaniRelief(asOfJd, moonIndex) };
}

/** A shared stretch shorter than this is a coincidence of two windows, not a season they agree on. */
const MIN_SHARED_DAYS = MIN_STAY_DAYS;

/**
 * The seasons for a day the Moon changed sign, read from both of [candidates] — the two rashis it
 * moved between (`Chart.moonRashiCandidates`) — because the hour that would say which is theirs is
 * not known. Each matter gets the part of the two windows both share, or, when they share none,
 * the stretch that covers both; a matter either rashi has no window for gets none. Shani's relief
 * only when it comes for both, by the later of the two.
 *
 * Without it, THE TIMING was UNKNOWN for them: the Moon takes two and a quarter days over a sign,
 * so 44% of birth dates had no window at all without the hour, and "naukri kab lagegi?" was
 * answered with a yog and no month or year — about 1,500 people's first "kab" in a week of
 * September. A rashi they told Astro settles such a day before it gets here (`computeChart`).
 */
export function transitTimingEither(candidates: readonly string[], asOf: Date): TransitTiming | null {
  if (candidates.length !== 2) return null;
  const [a, b] = candidates.map((rashi) => transitTiming(rashi, asOf));
  if (!a || !b) return null;

  const agreed = (x: TransitWindow | null, y: TransitWindow | null): TransitWindow | null => {
    if (!x || !y) return null;
    const start = Math.max(x.startJd, y.startJd);
    const end = Math.min(x.endJd, y.endJd);
    const [startJd, endJd] = end - start >= MIN_SHARED_DAYS
      ? [start, end]
      : [Math.min(x.startJd, y.startJd), Math.max(x.endJd, y.endJd)];
    return { startJd, endJd, now: startJd <= a.asOfJd, guruHouse: null, favours: null, how: "either" };
  };

  const topics = a.topics.map(({ topic, window }) => ({
    topic,
    window: agreed(window, b.topics.find((t) => t.topic === topic)?.window ?? null),
  }));
  const shaniEasing = a.shaniEasing && b.shaniEasing
    ? (a.shaniEasing.endsJd >= b.shaniEasing.endsJd ? a.shaniEasing : b.shaniEasing)
    : null;

  return {
    asOfJd: a.asOfJd,
    rashi: `${a.rashi} or ${b.rashi}`,
    either: [a.rashi, b.rashi],
    topics,
    shaniEasing,
  };
}

/**
 * The house from [rashi] Guru stands in at [asOfJd] when it is one of the houses where he does good
 * for everything (2, 5, 7, 9, 11) — a strength of the chart right now, which THE GOOD IN THEIR
 * CHART may name (`goodInChart` in `astro_chat_v5.ts`) — or null.
 */
export function guruFavoursNow(rashi: string | null, asOfJd: number): number | null {
  const moonIndex = RASHIS.indexOf(rashi as typeof RASHIS[number]);
  if (moonIndex < 0) return null;
  const [now] = stays("jupiter", asOfJd, asOfJd + STEP_DAYS);
  const house = now ? houseFrom(now.rashiIndex, moonIndex) : null;
  return house !== null && GOOD_GURU_HOUSES.includes(house) ? house : null;
}

/**
 * When Shani's sade sati (12th, 1st, 2nd from the Moon) or dhaiya (4th, 8th) over this rashi ends
 * within a year — and only then. A hard stretch still running is not mentioned at all.
 */
function shaniRelief(asOfJd: number, moonIndex: number): TransitTiming["shaniEasing"] {
  const hard = (house: number) => [12, 1, 2, 4, 8].includes(house);
  const shani = stays("saturn", asOfJd, asOfJd + 3 * 365.25);
  const [now, ...after] = shani;
  if (!now) return null;

  const house = houseFrom(now.rashiIndex, moonIndex);
  if (!hard(house)) return null;

  // Sade sati spans three signs; it ends when Shani leaves the 2nd.
  const phase = [12, 1, 2].includes(house) ? "sade sati" : "dhaiya";
  let endsJd = now.endJd;
  if (phase === "sade sati") {
    for (const next of after) {
      const nextHouse = houseFrom(next.rashiIndex, moonIndex);
      if (![12, 1, 2].includes(nextHouse)) break;
      endsJd = next.endJd;
    }
  }

  return endsJd - asOfJd <= 365.25 ? { endsJd, phase } : null;
}

function ordinal(n: number): string {
  if (n === 1) return "1st";
  if (n === 2) return "2nd";
  if (n === 3) return "3rd";
  return `${n}th`;
}

function span(window: TransitWindow): string {
  return window.now
    ? `now, through about ${monthYear(window.endJd)}`
    : `from about ${monthYear(window.startJd)} to ${monthYear(window.endJd)}`;
}

function why(window: TransitWindow): string {
  if (window.how === "either" || window.guruHouse === null) {
    return "Guru's transit favours it counted from either of the two signs — name no house";
  }
  const where = `Guru in the ${ordinal(window.guruHouse)} house from their Chandra`;
  if (window.how === "general" || window.favours === null) {
    return `${where}, one of the houses where Guru does good for everything`;
  }
  const holds = HOUSE_NAMES[window.favours] ?? `the ${ordinal(window.favours)} house`;
  return window.how === "occupies"
    ? `${where}, ${holds}`
    : `${where}, looking on the ${ordinal(window.favours)} house, ${holds}`;
}

/**
 * For a chart with the hour: the Guru season to answer with, for each matter whose first dasha
 * window opens beyond the two-year horizon.
 *
 * Three in ten people with an hour on file were told a marriage window more than two years off —
 * "September 2031" to someone of 26 — while Guru favoured the same matter within two years for
 * nearly all of them. The dasha is the finer clock, but a window years away answers "kab" with
 * "not yet", and the v5 plan's promise is a window inside two years. Only a stay that favours the
 * matter's own house counts here, not a general one, and never before [TopicTiming.opensJd].
 */
export function nearerSeasons(
  timing: ChatTiming,
  transits: TransitTiming,
): Partial<Record<TimingTopic, string>> {
  const nearer: Partial<Record<TimingTopic, string>> = {};
  for (const [topic, season] of Object.entries(nearerWindows(timing, transits))) {
    nearer[topic as TimingTopic] = `${span(season)} — ${why(season)}`;
  }
  return nearer;
}

/**
 * The seasons [nearerSeasons] words, as windows — for code that has to know when they open, such
 * as whether the time ahead may be called good (`kundaliLineFor` in `astro_chat_v5.ts`).
 */
export function nearerWindows(
  timing: ChatTiming,
  transits: TransitTiming,
): Partial<Record<TimingTopic, TransitWindow>> {
  const horizonJd = timing.asOfJd + HORIZON_DAYS;
  const nearer: Partial<Record<TimingTopic, TransitWindow>> = {};

  for (const topic of timing.topics) {
    if (topic.withheld) continue;
    const first = topic.windows[0];
    if (first && first.startJd <= horizonJd) continue;

    const season = transits.topics.find((t) => t.topic === topic.topic)?.window;
    if (!season || season.how === "general" || season.startJd < topic.opensJd) continue;

    nearer[topic.topic] = season;
  }
  return nearer;
}

/**
 * The timing block for someone with no hour of birth.
 *
 * Wider on purpose, and says so: without the hour this is the season, not the month.
 */
export function describeTransits(timing: TransitTiming): string {
  const lines = timing.topics.map(({ topic, window }) =>
    window
      ? `- ${topicLabel(topic)}: ${span(window)} — ${why(window)}.`
      : `- ${topicLabel(topic)}: no Guru stay in the next two years is marked for it. Speak of ` +
        `what the rashi leans toward, with hope, and give no months.`
  );

  const shani = timing.shaniEasing
    ? [
      "",
      `Shani: the heavier stretch over their rashi (${timing.shaniEasing.phase}) eases by about ` +
      `${monthYear(timing.shaniEasing.endsJd)}. You may say that relief is coming. Never describe ` +
      "the stretch itself as a threat.",
    ]
    : [];

  const [from, to] = timing.either ?? [];
  return [
    timing.either
      ? `THE TIMING (from Guru's transit; today is ${monthYear(timing.asOfJd)}). Their hour of ` +
        `birth is not known, and on the day they were born Chandra moved from ${from} into ${to}, ` +
        "so each window below is the season both signs agree on. These are seasons, not months — " +
        "this is your answer whenever they ask when:"
      : `THE TIMING (from Guru's transit over their rashi, ${timing.rashi}; today is ` +
        `${monthYear(timing.asOfJd)}). Their hour of birth is not known, so these are seasons, ` +
        "not months — this is your answer whenever they ask when:",
    ...lines,
    ...shani,
    ...(timing.either
      ? [
        "",
        `Never name ${from} or ${to} as their rashi, and never a house for Guru: from each sign it ` +
        'is a different one. The reason is Guru\'s gochar, in plain words — "is samay Guru ka ' +
        'gochar aapke liye shubh hai".',
      ]
      : []),
    "",
    'Say a window as a stretch of months — "agle 12 se 18 mahine", "2027 ke middle se 2028 ' +
    'tak" — never a single month and never a date. Give the same window every time you are asked.',
  ].join("\n");
}
