/**
 * The chat's own small kundli: the whole chart, once Astro has all four birth details.
 *
 * The product team (28 Sep): "make a small and simple kundli when user give the enough data and
 * give ans based on it. but dont show it to user" — the Kundali screen still asks for the details
 * itself and takes its 24 hours, exactly as before. Until now the chat read only the Moon's chart
 * (`jyotish.ts`): no lagna and no houses, so every "kyun" leaned on the dasha or on Guru's
 * transit. With the date, the hour and a place located on the map (`chat_birth_place.ts`, or the
 * Kundali form's), this casts the whole chart with `computeKundaliChart` — the same chart the
 * Kundali feature casts, on the clock of the birth place — and turns it into what the prompt can
 * reason from:
 *
 * - [describeKundli]: THEIR KUNDALI, inside THEIR CHART — the lagna, each graha's rashi and house
 *   from it with its dignity, the lords of the houses THE TIMING reads each matter from, and where
 *   the running dasha's lords sit.
 * - [kundliStrengths]: what is strong in it, for THE GOOD IN THEIR CHART — only what is true.
 * - [weakGrahas]: the grahas an upay for the matter would strengthen, for THE UPAY FOR TODAY.
 *
 * Cast every turn and never stored: it takes well under a millisecond (0.07 ms measured), and
 * nothing is written — not to `kundalis`, whose rows are the Kundali feature's alone, and not to
 * the user.
 *
 * One clock caveat. The Moon's chart the chat already reads is cast on India's clock (the note on
 * `users.birth_tz`), and this one on the birth place's. For everyone born in India since 1945 they
 * are the same instant, so the same Chandra and the same dasha. For the few born elsewhere — about
 * sixty accounts in September 2026 — Chandra, and the dasha counted from it, can differ. So the
 * block names Chandra only where the two charts agree, and names the dasha THEIR CHART names,
 * never its own: the prompt never holds two answers to one question.
 *
 * Pure; the clock comes in from outside.
 */

import { localToUtc } from "./birth_timezone.ts";
import { timingRule, TimingTopic, V5_TIMING_TOPICS } from "./chat_timing.ts";
import { Chart } from "./jyotish.ts";
import { computeKundaliChart, KundaliChart, PlacedPlanet, PlanetKey, PLANETS } from "./kundali_chart.ts";

/** The birth details on the user row, as `users` stores them. */
export interface KundliDetails {
  dob?: string | null;
  birth_time?: string | null;
  birth_lat?: number | string | null;
  birth_lng?: number | string | null;
  birth_tz?: string | null;
}

/**
 * The whole chart, or null until all four are on file: the date, the hour, the coordinates and
 * the time zone. The hour is read on the birth place's clock at the moment of birth
 * (`localToUtc`), as the Kundali feature reads it. Coordinates `purge_expired` has cleared are not
 * looked up again here: the chart waits for them, and the place still counts as known.
 */
export function miniKundli(user: KundliDetails, now: Date): KundaliChart | null {
  const dob = user.dob?.trim() ?? "";
  const time = (user.birth_time ?? "").trim().slice(0, 5);
  const zone = user.birth_tz?.trim() ?? "";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dob) || !/^\d{2}:\d{2}$/.test(time) || !zone) return null;
  if (user.birth_lat == null || user.birth_lng == null) return null;

  const [year, month, day] = dob.split("-").map(Number);
  const [hour, minute] = time.split(":").map(Number);
  const utc = localToUtc({ year, month, day, hour, minute }, zone);
  if (!utc) return null;

  return computeKundaliChart({
    dob,
    birthTime: time,
    utcOffsetSeconds: utc.offsetSeconds,
    latitude: Number(user.birth_lat),
    longitude: Number(user.birth_lng),
    asOf: now,
  });
}

// ---------------------------------------------------------------- reading it

const NAME: Record<PlanetKey, string> = Object.fromEntries(
  PLANETS.map((planet) => [planet.key, planet.sanskrit]),
) as Record<PlanetKey, string>;

const BY_NAME = new Map(PLANETS.map((planet) => [planet.sanskrit, planet.key]));

/** The seven grahas a dignity is read for — `dignityOf` leaves the nodes out. */
const VISIBLE: readonly PlanetKey[] = ["sun", "moon", "mars", "mercury", "jupiter", "venus", "saturn"];

const KENDRAS = [1, 4, 7, 10];
const TRIKONAS = [1, 5, 9];

/** What the kendras and trikonas hold, for a strength to say which house it blesses. */
const HOUSE_HOLDS: Record<number, string> = {
  1: "the self",
  4: "home and mother",
  5: "children and learning",
  7: "marriage and partnership",
  9: "fortune and dharma",
  10: "work and standing",
};

function ordinal(n: number): string {
  return n === 1 ? "1st" : n === 2 ? "2nd" : n === 3 ? "3rd" : `${n}th`;
}

function listed(items: string[]): string {
  return items.length === 1 ? items[0] : `${items.slice(0, -1).join(", ")} and ${items[items.length - 1]}`;
}

/**
 * Whether this chart's Chandra is THEIR CHART's — the same rashi. Always, for a birth read on
 * India's clock; see the file header for the rest.
 */
function moonAgrees(kundli: KundaliChart, chart: Chart | null): boolean {
  return kundli.planets.find((p) => p.key === "moon")?.rashi === chart?.moonRashi;
}

/** The grahas the block may place: all nine, less Chandra where the two charts disagree. */
function placeable(kundli: KundaliChart, chart: Chart | null): PlacedPlanet[] {
  const agrees = moonAgrees(kundli, chart);
  return kundli.planets.filter((p) => p.key !== "moon" || agrees);
}

/** The houses [planet] rules, from the lagna. None for Rahu and Ketu. */
function housesRuled(kundli: KundaliChart, planet: PlanetKey): number[] {
  return kundli.houses.filter((house) => house.lord === planet).map((house) => house.house);
}

const DIGNITY_WORDS = {
  exalted: "exalted (uchcha)",
  own: "in its own rashi (swagrahi)",
  debilitated: "debilitated (neecha)",
} as const;

/**
 * Each house a timing topic is read from (`chat_timing.ts`), with every matter it holds: the 7th
 * for marriage and partnership, the 5th for romance, children and learning, and so on.
 */
function matterHouses(): Array<[number, string[]]> {
  const holds = new Map<number, string[]>();
  for (const topic of V5_TIMING_TOPICS) {
    for (const [house, what] of timingRule(topic).houses) {
      const matter = what.replace(/^the house of /, "");
      const seen = holds.get(house) ?? [];
      if (!seen.includes(matter)) holds.set(house, [...seen, matter]);
    }
  }
  return [...holds].sort(([a], [b]) => a - b);
}

/**
 * THEIR KUNDALI, the lines added to THEIR CHART. Plain and short: what the model reasons from,
 * never what it recites. Every position in it is [kundli]'s; the dasha is [chart]'s (the file
 * header says why), and Chandra is named only when the two agree.
 */
export function describeKundli(kundli: KundaliChart, chart: Chart | null): string {
  const grahas = placeable(kundli, chart);
  const at = new Map(grahas.map((p) => [p.key, p]));
  const where = (key: PlanetKey) => {
    const p = at.get(key);
    return p ? `${NAME[key]} in the ${ordinal(p.house)} house` : NAME[key];
  };

  const lagnaLord = kundli.lagna.lord;
  const lines = [
    "THEIR KUNDALI — the whole chart, cast from their date, time and place of birth. Houses are " +
    "whole rashis counted from the lagna. Reason from it; never recite it or list the grahas to them.",
    `- Lagna: ${kundli.lagna.rashi} (${kundli.lagna.sign}), ruled by ${where(lagnaLord)}.`,
    `- The grahas: ${
      grahas.map((p) =>
        `${p.sanskrit} in ${p.rashi}, the ${ordinal(p.house)} house` +
        (p.dignity ? `, ${DIGNITY_WORDS[p.dignity]}` : "")
      ).join(" · ")
    }.`,
    `- The houses a matter is read from, and where their lords sit: ${
      matterHouses().map(([house, matters]) => {
        const h = kundli.houses[house - 1];
        return `the ${ordinal(house)}, of ${listed(matters)} — ${h.rashi}, its lord ${where(h.lord)}`;
      }).join(" · ")
    }.`,
  ];

  const dasha = chart?.dasha;
  if (dasha) {
    const lord = (name: string, level: string) => {
      const key = BY_NAME.get(name);
      if (!key) return null;
      const rules = housesRuled(kundli, key);
      const sits = at.get(key);
      return `${name}'s ${level}` +
        (sits ? ` — ${name} sits in the ${ordinal(sits.house)} house` : "") +
        (rules.length ? `${sits ? " and" : ` — ${name}`} rules the ${listed(rules.map(ordinal))}` : "");
    };
    const running = [
      lord(dasha.mahadasha, "Mahadasha"),
      dasha.antardasha !== dasha.mahadasha ? lord(dasha.antardasha, "Antardasha") : null,
    ].filter((part): part is string => part !== null);
    if (running.length > 0) lines.push(`- The dasha running now: ${running.join("; within it, ")}.`);
  }

  lines.push(
    "- These houses count from the lagna; THE TIMING's count from Chandra. A reason names one or " +
      "the other — never both in one sentence. A debilitated graha is never bad news to them: say " +
      "at most that THE UPAY FOR TODAY strengthens it, when it does.",
  );
  return lines.join("\n");
}

// ---------------------------------------------------------------- its strengths

/** More than this, and THE GOOD IN THEIR CHART stops being a short list. */
const MAX_STRENGTHS = 4;

/**
 * THE GOOD IN THEIR CHART's lines from the kundli — only what is true of it, strongest claim
 * first: a strong lagna lord (in a kendra or trikona, and not debilitated), each exalted graha,
 * each graha in its own rashi, and Guru or Shukra in a kendra or trikona. At most
 * [MAX_STRENGTHS]; none at all is an empty list, and the craft forbids inventing one.
 */
export function kundliStrengths(kundli: KundaliChart | null, chart: Chart | null): string[] {
  if (!kundli) return [];
  const grahas = placeable(kundli, chart);
  const lines: string[] = [];
  const kind = (house: number) =>
    KENDRAS.includes(house) && TRIKONAS.includes(house)
      ? "both a kendra and a trikona"
      : KENDRAS.includes(house)
      ? "a kendra"
      : "a trikona";

  const lord = grahas.find((p) => p.key === kundli.lagna.lord);
  if (
    lord && lord.dignity !== "debilitated" &&
    (KENDRAS.includes(lord.house) || TRIKONAS.includes(lord.house))
  ) {
    lines.push(
      `The lord of their lagna, ${lord.sanskrit}, sits in the ${ordinal(lord.house)} house — ` +
        `${kind(lord.house)} — which makes the lagna strong: the backbone of the whole chart.`,
    );
  }

  for (const p of grahas.filter((p) => VISIBLE.includes(p.key) && p.dignity === "exalted")) {
    lines.push(`${p.sanskrit} is exalted (uchcha) in ${p.rashi} in their kundali — at its very strongest.`);
  }
  for (const p of grahas.filter((p) => VISIBLE.includes(p.key) && p.dignity === "own")) {
    lines.push(`${p.sanskrit} is in its own rashi, ${p.rashi} (swagrahi) — strong and at home.`);
  }

  for (const p of grahas.filter((p) => p.key === "jupiter" || p.key === "venus")) {
    if (p.dignity === "debilitated") continue;
    if (!KENDRAS.includes(p.house) && !TRIKONAS.includes(p.house)) continue;
    lines.push(
      `${p.sanskrit}, a benefic, sits in the ${ordinal(p.house)} house from their lagna — ` +
        `${kind(p.house)}, the house of ${HOUSE_HOLDS[p.house]} — and blesses it.`,
    );
  }

  return lines.slice(0, MAX_STRENGTHS);
}

// ---------------------------------------------------------------- what an upay would strengthen

/**
 * The grahas an upay for [topic] would strengthen, weakest first, by their names (`Shukra`) —
 * `upayFor`'s `weakGrahas`, which prefers a remedy on their day. Only grahas that bear on the
 * matter: its karakas and the lords of its houses from the lagna (`chat_timing.ts`); for health
 * or no one subject, any. Debilitated first, then one sharing a house with Rahu or Ketu — the
 * commonest affliction a pandit ji would name. Never Rahu or Ketu themselves, which have no day.
 */
export function weakGrahas(kundli: KundaliChart | null, topic: string, chart: Chart | null): string[] {
  if (!kundli) return [];
  const grahas = placeable(kundli, chart).filter((p) => VISIBLE.includes(p.key));

  const timed = (V5_TIMING_TOPICS as readonly string[]).includes(topic)
    ? timingRule(topic as TimingTopic)
    : null;
  const bears = timed
    ? new Set([
      ...timed.karakas,
      ...timed.houses.map(([house]) => NAME[kundli.houses[house - 1].lord]),
    ])
    : null;
  const relevant = grahas.filter((p) => !bears || bears.has(p.sanskrit));

  const nodes = new Set(
    kundli.planets.filter((p) => p.key === "rahu" || p.key === "ketu").map((p) => p.house),
  );
  const debilitated = relevant.filter((p) => p.dignity === "debilitated");
  const afflicted = relevant.filter((p) =>
    p.dignity !== "debilitated" && p.dignity !== "exalted" && p.dignity !== "own" && nodes.has(p.house)
  );
  return [...debilitated, ...afflicted].map((p) => p.sanskrit);
}
