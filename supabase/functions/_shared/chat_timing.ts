/**
 * When, for the chat: the windows a "when" question is answered from.
 *
 * "Shaadi kab hogi" is the question Astro is asked most, and until chat v4 it could only answer
 * with a condition — "the door opens once you are settled" — because nothing was allowed to name
 * a year. Every one-star comment in the review that prompted this file followed one of those
 * replies. So v4 names a window, and this module is where the window comes from: computed from
 * the dasha, never invented by the model.
 *
 * Computed matters for two reasons. The years have to rest on the chart, or the reply is a
 * horoscope column with a date in it. And they have to be the same every time: someone who asks
 * twice and hears 2027 and then 2029 has caught the sage making it up.
 *
 * The rule is the tradition's own, kept deliberately simple: a matter is timed by the Antardasha
 * of a graha that signifies it (its karaka — Shukra for marriage) or that rules the house it
 * lives in, counted from Chandra's rashi. The chat has only the Moon's chart, so the houses are
 * counted from the Moon (Chandra lagna) rather than from an ascendant it does not have.
 *
 * Pure, and the clock comes in from outside, so every window is reproducible in a test.
 */

import { AntardashaPeriod, Chart, julianDayOf, RASHIS } from "./jyotish.ts";
import { PLANETS, SIGN_LORDS } from "./kundali_chart.ts";

/** The matters a v4 window is worked out for. Children are not among them: see BOUNDARIES. */
export const TIMING_TOPICS = ["marriage", "career", "money", "home", "studies"] as const;

/**
 * The matters a v5 window is worked out for: v4's five plus the three the topics report found
 * people asking "kab" about most after marriage — love (22.5% of typed questions), children (36%
 * of which ask when) and debt. Children are read as a period of time only; v5's health rule in
 * BOUNDARIES says how.
 */
export const V5_TIMING_TOPICS = [
  "marriage",
  "love",
  "children",
  "career",
  "money",
  "debt",
  "home",
  "studies",
] as const;

export type TimingTopic = typeof V5_TIMING_TOPICS[number];

interface TopicRule {
  /** What someone asking about this is asking about, as the prompt lists it. */
  label: string;

  /** Grahas that signify the matter themselves, each with why, as the sage may cite it. */
  karakas: ReadonlyArray<readonly [string, string]>;

  /** Houses counted from Chandra's rashi (1 is the rashi itself), each with what it holds. */
  houses: ReadonlyArray<readonly [number, string]>;
}

const RULES: Record<TimingTopic, TopicRule> = {
  marriage: {
    label: "Marriage, a life partner, a relationship turning into marriage",
    karakas: [
      ["Shukra", "the graha of love and marriage"],
      ["Guru", "the graha of blessing and of the spouse"],
    ],
    houses: [[7, "the house of marriage"]],
  },
  career: {
    label: "A job, a promotion, a government post, work or business",
    karakas: [
      ["Surya", "the graha of authority and government"],
      ["Shani", "the graha of work and service"],
    ],
    houses: [[10, "the house of work"]],
  },
  money: {
    label: "Money, income, savings, a debt clearing",
    karakas: [["Guru", "the graha of wealth and growth"]],
    houses: [[2, "the house of savings"], [11, "the house of gains"]],
  },
  love: {
    label: "Love, one particular person, talking again, a relationship becoming serious",
    karakas: [
      ["Shukra", "the graha of love"],
      ["Chandra", "the graha of the heart and feeling"],
    ],
    houses: [[5, "the house of romance"], [7, "the house of partnership"]],
  },
  children: {
    label: "Children (santan), as a period of time only",
    karakas: [["Guru", "the graha of children and blessing"]],
    houses: [[5, "the house of children"]],
  },
  debt: {
    label: "A debt reducing, a loan being cleared",
    karakas: [["Guru", "the graha of relief and growth"]],
    houses: [[6, "the house of debts"], [11, "the house of gains"]],
  },
  home: {
    label: "A home of their own, land or property, a vehicle",
    karakas: [
      ["Mangal", "the graha of land and property"],
      ["Shukra", "the graha of comfort and vehicles"],
    ],
    houses: [[4, "the house of home"]],
  },
  studies: {
    label: "Studies, exams and results",
    karakas: [
      ["Budh", "the graha of learning"],
      ["Guru", "the graha of knowledge"],
    ],
    houses: [[5, "the house of learning"]],
  },
};

/** Two windows per matter: the answer, and the one to give when they ask "and if not then?" */
const MAX_WINDOWS = 2;

/**
 * A window already running that closes sooner than this is not offered as the answer. Telling
 * someone "now" about a period with weeks left in it is a promise the calendar breaks at once.
 */
const MIN_REMAINING_DAYS = 60;

/** Below this, no marriage (or, in v5, children) window is named at all. */
const ADULT_AGE = 18;

/** The matters that wait for adulthood: withheld under [ADULT_AGE], floored at 21. */
const ADULT_TOPICS: ReadonlySet<TimingTopic> = new Set(["marriage", "children"]);

/**
 * v5's longest window. The v5 plan allows a month-year window "of up to about two years", and a
 * merged run of favourable periods can be far longer — "2027 to 2031" is not an answer to "kab".
 */
const V5_MAX_WINDOW_DAYS = 24 * 30.44;

/**
 * No marriage window opens before this age, whoever is asking. The legal age for a man in India,
 * and the app does not know who is a man, so it holds for everyone.
 */
const MARRIAGE_MIN_AGE = 21;

/**
 * Past this wait for an Antardasha of its own, a matter is timed by a favourable Mahadasha instead.
 *
 * Someone of 21 asking about marriage, told 2035, has been given a verdict rather than a window.
 * The tradition reads the Mahadasha lord as well as the Antardasha lord — the Mahadasha is the
 * backdrop every sub-period plays out against — so when the first period ruled by a favoured graha
 * is further off than this, a sub-period inside a favoured Mahadasha comes first.
 */
const LONG_WAIT_YEARS = 4;

/** One stretch of time the chart favours a matter in. */
export interface TimingWindow {
  /**
   * The favoured grahas that make it a window. Antardasha lords — one, or more when favourable
   * periods run back to back — or, when [level] is "mahadasha", the Mahadasha's own lord.
   */
  lords: string[];

  /** Which level of the dasha carries the favour. "mahadasha" only through [LONG_WAIT_YEARS]. */
  level: "antardasha" | "mahadasha";

  /** The Mahadasha the window opens inside. */
  mahadasha: string;

  /** The Antardashas it spans, in order. */
  antardashas: string[];

  startJd: number;
  endJd: number;

  /** True when the window is already running at [ChatTiming.asOfJd]. */
  now: boolean;
}

export interface TopicTiming {
  topic: TimingTopic;
  label: string;

  /** Each graha that times this matter for this chart, and why — "lord of the 7th…". */
  reasons: Record<string, string>;

  /** Soonest first, at most [MAX_WINDOWS]. Empty when none falls inside the horizon. */
  windows: TimingWindow[];

  /** True only for marriage, when they are under [ADULT_AGE] and no window is named. */
  withheld: boolean;

  /**
   * The soonest any window for it may open: today, or their 21st birthday for marriage and
   * children. A window from another clock — Guru's transit — must respect it too.
   */
  opensJd: number;
}

export interface ChatTiming {
  asOfJd: number;

  /** The Antardashas ahead, the running one first — the chart's own clock, dated. */
  periods: AntardashaPeriod[];

  topics: TopicTiming[];
}

/**
 * The windows for every matter, or null when the chart carries no dated periods — which is
 * exactly when the hour of birth is unknown.
 *
 * [dob] is `users.dob`, for the age limits on marriage. A dob that cannot be read withholds
 * nothing and floors nothing: the chart it came from could not have been computed either.
 */
export function chatTiming(
  chart: Chart | null,
  { dob, asOf, v5 = false }: { dob?: string | null; asOf: Date; v5?: boolean },
): ChatTiming | null {
  if (!chart?.periods?.length || !chart.moonRashi) return null;

  const moonIndex = RASHIS.indexOf(chart.moonRashi as typeof RASHIS[number]);
  if (moonIndex < 0) return null;

  const asOfJd = julianDayOf(asOf);
  const birthday = birthdayJd(dob);
  const age = birthday ? completedYears(birthday, asOfJd) : null;

  const topics = (v5 ? V5_TIMING_TOPICS : TIMING_TOPICS).map((topic): TopicTiming => {
    const rule = RULES[topic];
    const reasons = reasonsFor(rule, moonIndex);
    const adult = ADULT_TOPICS.has(topic);

    const floorJd = adult && birthday ? birthday(MARRIAGE_MIN_AGE) : -Infinity;
    const opensJd = Math.max(asOfJd, floorJd);

    if (adult && age !== null && age < ADULT_AGE) {
      return { topic, label: rule.label, reasons, windows: [], withheld: true, opensJd };
    }

    const windows = windowsFor(chart.periods!, new Set(Object.keys(reasons)), asOfJd, floorJd);

    return {
      topic,
      label: rule.label,
      reasons,
      windows: v5 ? windows.map(clipped) : windows,
      withheld: false,
      opensJd,
    };
  });

  return { asOfJd, periods: chart.periods, topics };
}

/** How the prompt names [topic] — shared with the transit windows, so both lists read alike. */
export function topicLabel(topic: TimingTopic): string {
  return RULES[topic].label;
}

/**
 * The grahas that signify [topic] and the houses it lives in, as this file reads them — for the
 * chat's small kundli (`mini_kundli.ts`), which counts the same houses from the lagna rather than
 * from Chandra. Copies, so nothing outside can change a rule.
 */
export function timingRule(topic: TimingTopic): {
  karakas: string[];
  houses: Array<readonly [number, string]>;
} {
  const rule = RULES[topic];
  return { karakas: rule.karakas.map(([graha]) => graha), houses: [...rule.houses] };
}

/** A window cut to [V5_MAX_WINDOW_DAYS] from where it opens. */
function clipped(window: TimingWindow): TimingWindow {
  return { ...window, endJd: Math.min(window.endJd, window.startJd + V5_MAX_WINDOW_DAYS) };
}

/** The grahas that time [rule] for a Moon in rashi [moonIndex], each with every reason it has. */
function reasonsFor(rule: TopicRule, moonIndex: number): Record<string, string> {
  const reasons = new Map<string, string[]>();
  const add = (graha: string, why: string) =>
    reasons.set(graha, [...reasons.get(graha) ?? [], why]);

  for (const [graha, why] of rule.karakas) add(graha, why);
  for (const [house, holds] of rule.houses) {
    const lord = lordOf((moonIndex + house - 1) % 12);
    add(lord, `lord of the ${ordinal(house)} house from their Chandra, ${holds}`);
  }

  return Object.fromEntries([...reasons].map(([graha, whys]) => [graha, whys.join(", and ")]));
}

/**
 * The favourable stretches among [periods], soonest first.
 *
 * Back-to-back favourable periods are one window, not two: "2027 to 2028, and then 2028 to 2030"
 * reads as a sage hedging, where "2027 to 2030" reads as a long good stretch — which is what it is.
 */
function windowsFor(
  periods: AntardashaPeriod[],
  favoured: Set<string>,
  asOfJd: number,
  floorJd: number,
): TimingWindow[] {
  const openJd = Math.max(asOfJd, floorJd);
  const usable = (window: TimingWindow) =>
    !(window.now && window.endJd - asOfJd < MIN_REMAINING_DAYS);

  const strong: TimingWindow[] = [];

  for (const period of periods) {
    if (!favoured.has(period.antardasha)) continue;

    const startJd = Math.max(period.startJd, openJd);
    if (startJd >= period.endJd) continue;

    const last = strong[strong.length - 1];
    if (last && Math.abs(last.endJd - period.startJd) < 1) {
      last.endJd = period.endJd;
      last.antardashas.push(period.antardasha);
      if (!last.lords.includes(period.antardasha)) last.lords.push(period.antardasha);
      continue;
    }

    strong.push({
      lords: [period.antardasha],
      level: "antardasha",
      mahadasha: period.mahadasha,
      antardashas: [period.antardasha],
      startJd,
      endJd: period.endJd,
      now: startJd <= asOfJd,
    });
  }

  // After merging, so a period about to close that runs straight into another favourable one
  // still counts as the long window it is part of.
  const windows = strong.filter(usable);

  const first = windows[0];
  if (!first || first.startJd > openJd + LONG_WAIT_YEARS * 365.25) {
    const supporting = periods
      .filter((period) => favoured.has(period.mahadasha))
      .map((period): TimingWindow => {
        const startJd = Math.max(period.startJd, openJd);
        return {
          lords: [period.mahadasha],
          level: "mahadasha",
          mahadasha: period.mahadasha,
          antardashas: [period.antardasha],
          startJd,
          endJd: period.endJd,
          now: startJd <= asOfJd,
        };
      })
      .find((window) => window.startJd < window.endJd && usable(window));

    if (supporting && (!first || supporting.startJd < first.startJd)) {
      return [supporting, ...windows].slice(0, MAX_WINDOWS);
    }
  }

  return windows.slice(0, MAX_WINDOWS);
}

/** The graha that rules the rashi at [index], spelled as `DASHA_LORDS` spells it. */
function lordOf(index: number): string {
  const key = SIGN_LORDS[index];
  return PLANETS.find((planet) => planet.key === key)!.sanskrit;
}

function ordinal(n: number): string {
  if (n === 1) return "1st";
  if (n === 2) return "2nd";
  if (n === 3) return "3rd";
  return `${n}th`;
}

/**
 * A function from an age to the Julian Day of that birthday, or null for a dob that is not a date.
 * Midnight UTC is close enough: nothing here is finer than a month.
 */
function birthdayJd(dob: string | null | undefined): ((years: number) => number) | null {
  const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dob?.trim() ?? "");
  if (!parts) return null;

  const [year, month, day] = [Number(parts[1]), Number(parts[2]), Number(parts[3])];
  return (years) => julianDayOf(new Date(Date.UTC(year + years, month - 1, day)));
}

function completedYears(birthday: (years: number) => number, asOfJd: number): number {
  let years = 0;
  while (years < 150 && birthday(years + 1) <= asOfJd) years++;
  return years;
}

// ---------------------------------------------------------------- for the prompt

const MONTHS = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

/** Periods listed after the windows. Enough to reason about "and after that?", not a table. */
const MAX_PERIODS_LISTED = 8;

/** A month and a year, never a day: the finest the sage is ever handed. */
export function monthYear(jd: number): string {
  const date = new Date((jd - 2440587.5) * 86_400_000);
  return `${MONTHS[date.getUTCMonth()]} ${date.getUTCFullYear()}`;
}

function span(window: TimingWindow): string {
  return window.now
    ? `now, through about ${monthYear(window.endJd)}`
    : `from about ${monthYear(window.startJd)} to ${monthYear(window.endJd)}`;
}

function listed(names: string[]): string {
  return names.length === 1
    ? names[0]
    : `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
}

/** Which period a window is: "the Antardasha of Shukra", or a sub-period of a favoured Mahadasha. */
function source(window: TimingWindow): string {
  if (window.level === "mahadasha") {
    return `the Mahadasha of ${window.mahadasha}, during its Antardasha of ` +
      window.antardashas[0];
  }
  const plural = window.antardashas.length > 1 ? "Antardashas" : "Antardasha";
  return `the ${plural} of ${listed(window.antardashas)}`;
}

function topicLine(topic: TopicTiming, nearer?: string): string {
  if (topic.withheld) {
    const what = topic.topic === "children" ? "children" : "marriage";
    return `- ${topic.label}: they are under 18. Name no time for ${what}. Speak warmly of the ` +
      `years ahead of them, and of their studies, instead.`;
  }

  const [first, second] = topic.windows;

  // v5: the dasha's own period is years off, and Guru's transit favours the matter sooner.
  if (nearer) {
    const later = first
      ? `Their dasha's own period for it comes later — ${span(first)}, in ${source(first)} — ` +
        "name it only if they ask what comes after."
      : "Their dasha marks no period for it in the next twelve years; do not say so.";
    return `- ${topic.label}: ${nearer}, from Guru's transit over their rashi. This is the ` +
      `window to give. ${later}`;
  }

  if (!first) {
    return `- ${topic.label}: no period in the next twelve years is marked for it. Read from the ` +
      `periods below, and speak of the next one with hope.`;
  }

  const why = first.lords
    .map((lord) => `${lord}, ${topic.reasons[lord]}`)
    .join("; ");
  const then = second ? ` After that: ${span(second)}, ${source(second)}.` : "";

  return `- ${topic.label}: ${span(first)}, in ${source(first)} (${why}).${then}`;
}

/**
 * The timing block for the user prompt.
 *
 * Always says something: without a dated chart it says the timing is unknown, so the sage cannot
 * mistake silence for permission to pick a year of its own.
 *
 * [nearer] is v5's: for a matter whose dasha window is years off, the Guru season that replaces it
 * as the answer (`nearerSeasons` in `chat_transits.ts`).
 */
export function describeTiming(
  timing: ChatTiming | null,
  { hasChart, v5 = false, nearer = {} }: {
    hasChart: boolean;
    v5?: boolean;
    nearer?: Partial<Record<TimingTopic, string>>;
  },
): string {
  if (!timing) {
    const because = hasChart
      ? "their hour of birth is not on file, and the dasha is counted from it"
      : "their date of birth is not on file";
    return `THE TIMING: UNKNOWN, because ${because}. Name no year, no month and no age for ` +
      `anything — a year you chose yourself would be a guess dressed as a reading.`;
  }

  const upcoming = timing.periods.slice(0, MAX_PERIODS_LISTED).map((period, index) => {
    const when = index === 0
      ? `now until about ${monthYear(period.endJd)}`
      : `${monthYear(period.startJd)} to ${monthYear(period.endJd)}`;
    return `- ${when}: the Antardasha of ${period.antardasha}, within the Mahadasha of ` +
      `${period.mahadasha}`;
  });

  return [
    `THE TIMING (computed from their Vimshottari dasha; today is ${monthYear(timing.asOfJd)}). ` +
    `This is fact, and it is your answer whenever they ask when:`,
    ...timing.topics.map((topic) => topicLine(topic, nearer[topic.topic])),
    "",
    "The periods ahead, in order:",
    ...upcoming,
    "",
    v5
      ? 'Say a window as a month-year range — "2027 ke middle se 2028 ke end tak", "March se ' +
        'August 2027 ke beech" — never as a day or a date. Give the same window every time you ' +
        "are asked; when they press, name a month inside it."
      : 'Say a window as years or part of a year — "2027 ke aas-paas", "agle saal ki shuruaat" — ' +
        "never as a day or a date. Give the same window every time you are asked.",
  ].join("\n");
}
