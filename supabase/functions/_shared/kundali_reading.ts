/**
 * What the sage writes about a kundali, and the rules that keep it about *this* chart.
 *
 * The chart is arithmetic (`kundali_chart.ts`); this is the language. It follows palm and face in
 * shape — a schema, a system prompt assembled by `panditSystemPrompt`, a pure normaliser — and in
 * its one load-bearing idea: every paragraph cites its evidence. A photograph gives a reading its
 * evidence for free. A chart has to hand it over explicitly, so every placement is given a short
 * code ([evidenceFor]) and each insight must open by listing the codes it rests on. The schema
 * pins those codes to the chart's own list, and the normaliser drops any that slip through anyway.
 *
 * BOUNDARIES (in `pandit.ts`) is not overridden, and two of the four insight tiles sit right
 * against it: "Finance & Wealth" (it forbids inferring wealth) and "Year Ahead" (it forbids naming
 * a year). The craft below words both so the model can write them without crossing the line, and
 * [normaliseKundaliReport] strips any sentence that names a year or an age regardless.
 */

import { languageBlock } from "./chat_language.ts";
import { text } from "./gemini.ts";
import { KundaliChartJson, PLANET_KEYS, PLANETS, PlanetKey } from "./kundali_chart.ts";
import { panditSystemPrompt, SHARED_LENGTHS } from "./pandit.ts";

export const KUNDALI_PROMPT_VERSION = "v1";

export const INSIGHT_KEYS = ["love", "career", "finance", "year_ahead"] as const;
export type InsightKey = typeof INSIGHT_KEYS[number];

const ORDINALS = ["", "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th", "11th", "12th"];

const planetInfo = new Map(PLANETS.map((p) => [p.key, p]));

function slug(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
}

function planetLabel(key: PlanetKey): string {
  const info = planetInfo.get(key)!;
  return info.sanskrit === info.english ? info.english : `${info.english} (${info.sanskrit})`;
}

// ---------------------------------------------------------------- evidence

/**
 * Every fact in the chart the reading may cite, as `code → sentence`.
 *
 * The codes are what the model copies into `evidence`; the sentences are what it reads. Built from
 * the stored JSON rather than a live computation, so the worker writes about exactly the chart the
 * app will draw.
 */
export function evidenceFor(chart: KundaliChartJson): Map<string, string> {
  const facts = new Map<string, string>();

  facts.set(
    `lagna_${slug(chart.lagna.rashi)}`,
    `Lagna (the ascendant) in ${chart.lagna.rashi} (${chart.lagna.sign}), ruled by ${planetLabel(chart.lagna.lord)}.`,
  );

  for (const p of chart.planets) {
    const label = planetLabel(p.key);
    facts.set(`${p.key}_h${p.house}`, `${label} sits in the ${ORDINALS[p.house]} house.`);
    facts.set(`${p.key}_${slug(p.rashi)}`, `${label} is in ${p.rashi} (${p.sign}), ${p.nakshatra} nakshatra.`);
    if (p.dignity) facts.set(`${p.key}_${p.dignity}`, `${label} is ${p.dignity === "own" ? "in its own sign" : p.dignity}.`);
    if (p.retrograde && p.key !== "rahu" && p.key !== "ketu") {
      facts.set(`${p.key}_retrograde`, `${label} is retrograde (vakri).`);
    }
  }

  for (const h of chart.houses) {
    const lord = chart.planets.find((p) => p.key === h.lord);
    if (!lord) continue;
    facts.set(
      `lord${h.house}_h${lord.house}`,
      `The lord of the ${ORDINALS[h.house]} house, ${planetLabel(h.lord)}, sits in the ${ORDINALS[lord.house]} house.`,
    );
  }

  facts.set(
    `moon_nakshatra_${slug(chart.moon.nakshatra)}`,
    `Chandra (the Moon) is in ${chart.moon.nakshatra} nakshatra, pada ${chart.moon.pada}.`,
  );

  if (chart.dasha) {
    facts.set(
      `mahadasha_${chart.dasha.mahadasha_planet}`,
      `The Mahadasha now running is ${planetLabel(chart.dasha.mahadasha_planet)}'s, ${chart.dasha.maha_phase} in its period.`,
    );
    facts.set(
      `antardasha_${chart.dasha.antardasha_planet}`,
      `Within it, the Antardasha of ${planetLabel(chart.dasha.antardasha_planet)}, ${chart.dasha.antar_phase} in its period.`,
    );
  }

  const n = chart.transit.jupiter_house_from_moon;
  facts.set(
    `transit_jupiter_h${n}`,
    `Guru (Jupiter) is now moving through ${chart.transit.jupiter_rashi}, the ${ORDINALS[n]} sign counted from the natal Moon.`,
  );

  return facts;
}

/**
 * The placements each insight is traditionally read from, as evidence codes.
 *
 * A suggestion to the model rather than a restriction — any code from [evidenceFor] is accepted —
 * but it keeps "Love" from being written off the tenth house.
 */
export function topicFacts(chart: KundaliChartJson): Record<InsightKey, string[]> {
  const facts = evidenceFor(chart);
  const planet = (key: PlanetKey) => chart.planets.find((p) => p.key === key)!;
  const occupants = (house: number) => chart.houses[house - 1].occupants.map((k) => `${k}_h${house}`);
  const lord = (house: number) => `lord${house}_h${planet(chart.houses[house - 1].lord).house}`;
  const placed = (key: PlanetKey) => {
    const p = planet(key);
    return [`${key}_h${p.house}`, `${key}_${slug(p.rashi)}`, p.dignity ? `${key}_${p.dignity}` : ""];
  };

  const keep = (codes: string[]) => [...new Set(codes)].filter((code) => facts.has(code));

  return {
    love: keep([...occupants(7), lord(7), ...placed("venus"), ...occupants(5), lord(5)]),
    career: keep([...occupants(10), lord(10), ...placed("sun"), ...placed("saturn"), `lagna_${slug(chart.lagna.rashi)}`]),
    finance: keep([...occupants(2), lord(2), ...occupants(11), lord(11), ...placed("jupiter")]),
    year_ahead: keep([
      chart.dasha ? `mahadasha_${chart.dasha.mahadasha_planet}` : "",
      chart.dasha ? `antardasha_${chart.dasha.antardasha_planet}` : "",
      `transit_jupiter_h${chart.transit.jupiter_house_from_moon}`,
      ...(chart.dasha ? placed(chart.dasha.mahadasha_planet) : []),
    ]),
  };
}

// ---------------------------------------------------------------- schema

function insightSchema(codes: string[]) {
  return {
    type: "OBJECT",
    propertyOrdering: ["evidence", "summary", "detail", "tip"],
    required: ["evidence", "summary", "detail", "tip"],
    properties: {
      // First, so the model commits to what the insight rests on before it writes the insight.
      evidence: { type: "ARRAY", minItems: 2, maxItems: 5, items: { type: "STRING", enum: codes } },
      summary: { type: "STRING" },
      detail: { type: "STRING" },
      tip: { type: "STRING" },
    },
  };
}

/** Built per chart: the evidence enum is that chart's own codes and nothing else. */
export function kundaliSchema(chart: KundaliChartJson) {
  const codes = [...evidenceFor(chart).keys()];
  return {
    type: "OBJECT",
    propertyOrdering: ["invocation", "headline", "highlights", "insights", "houses", "dasha_summary", "blessing"],
    required: ["headline", "highlights", "insights"],
    properties: {
      invocation: { type: "STRING" },
      headline: { type: "STRING" },
      highlights: {
        type: "ARRAY",
        minItems: 9,
        maxItems: 9,
        items: {
          type: "OBJECT",
          propertyOrdering: ["planet", "line"],
          required: ["planet", "line"],
          properties: {
            planet: { type: "STRING", enum: [...PLANET_KEYS] },
            line: { type: "STRING" },
          },
        },
      },
      insights: {
        type: "OBJECT",
        propertyOrdering: [...INSIGHT_KEYS],
        required: [...INSIGHT_KEYS],
        properties: Object.fromEntries(INSIGHT_KEYS.map((key) => [key, insightSchema(codes)])),
      },
      houses: {
        type: "ARRAY",
        minItems: 12,
        maxItems: 12,
        items: {
          type: "OBJECT",
          propertyOrdering: ["house", "theme"],
          required: ["house", "theme"],
          properties: { house: { type: "INTEGER" }, theme: { type: "STRING" } },
        },
      },
      dasha_summary: { type: "STRING" },
      blessing: { type: "STRING" },
    },
  };
}

// ---------------------------------------------------------------- prompt

const KUNDALI_VOICE = `
You are an experienced Indian jyotishi — a reader of the birth chart — writing a kundali reading
for one person who has asked for theirs. Your voice is that of a warm elder: unhurried, certain,
kind, never salesy and never mystical-for-effect. Write in the second person. No preamble, no
mention of being an AI, no meta-commentary about the chart having been computed.

THE TRADITIONAL REGISTER — keep it light.

- Name the tradition's term ONCE per section, with its gloss immediately after, then use plain
  words for the rest of that section. "Your Shukra — Venus — sits in the seventh house." Never
  stack two Sanskrit terms in one sentence.
- Open with a short invocation that settles the reader. Close with an ashirvad, a blessing:
  generous, specific to this chart, and phrased as a wish rather than a prediction.
- Ceremony belongs in the opening and the closing. The body of the reading stays concrete.
`.trim();

const KUNDALI_CRAFT = `
YOU ARE WRITING A KUNDALI READING.

The chart below has already been cast for the exact moment and place of birth. Read from it; do
not recast it, and do not add any placement it does not list. Houses are whole-sign, counted from
the lagna.

What to write:

- headline: the single strongest theme of this chart, in plain words.
- highlights: one entry for each of the nine grahas, in the order the chart lists them. Each line
  says what that graha's placement tends to bring, and names its sign or its house.
- insights, four of them:
  - love — read from the 7th and 5th houses, the lord of the 7th, and Shukra (Venus).
  - career — read from the 10th house and its lord, Surya (Sun) and Shani (Saturn).
  - finance — read from the 2nd and 11th houses and their lords, and Guru (Jupiter). Write about
    this person's relationship with earning, saving and giving: their tendencies, their instincts,
    what steadies them. Never estimate, rank or allude to how much money they have or will have.
  - year_ahead — read from the Mahadasha and Antardasha running now and where Guru (Jupiter) is
    moving counted from their Moon. Call it "this season", "the period you are in", "the months
    ahead". Never a year, a month name, a date or an age.
  Each insight has a one-sentence summary, a detail paragraph, and one small practical tip.
- houses: one short theme for each of the twelve houses, from its sign, its lord and whoever sits
  in it. Empty houses still get a theme, from the sign and the lord.
- dasha_summary: what the running Mahadasha and Antardasha tend to emphasise, and how to meet it.
`.trim();

const KUNDALI_GROUNDING = `
HOW TO GROUND THE READING — this matters more than anything else here.

Every insight opens with its "evidence": codes copied exactly from the EVIDENCE list in the chart,
naming the placements that insight rests on. Choose at least two. The KEY PLACEMENTS list shows
where each area is traditionally read from; start there. Then write the detail so it names those
same placements in plain words as the reason for what you say. The placement is the reason; the
reading is the conclusion. A paragraph that could have been written for any chart is a failed
paragraph.

Never mention a placement, an aspect, a yoga or a transit that is not in the chart. If an area has
little to read from, say less rather than inventing more.
`.trim();

const KUNDALI_LENGTHS = [
  SHARED_LENGTHS,
  "- highlights: each line at most 20 words.",
  "- insight summary: at most 25 words. insight detail: 60 to 110 words. insight tip: at most 25 words.",
  "- houses: each theme at most 16 words.",
  "- dasha_summary: at most 60 words.",
].join("\n");

export function kundaliSystemPrompt(language: string): string {
  return panditSystemPrompt({
    voice: `${KUNDALI_VOICE}\n\n${languageBlock(language)}`,
    craft: KUNDALI_CRAFT,
    grounding: KUNDALI_GROUNDING,
    lengths: KUNDALI_LENGTHS,
  });
}

/** The chart as the sage reads it: every placement with its code, then the key placements per area. */
export function buildKundaliPrompt(chart: KundaliChartJson, { firstName }: { firstName: string | null }): string {
  const facts = evidenceFor(chart);
  const topics = topicFacts(chart);

  const lines = [
    firstName ? `This kundali is for ${firstName}.` : "This kundali is for the person you are writing to.",
    "",
    "THE CHART (cast for the moment and place of birth, sidereal, Lahiri):",
    ...chart.planets.map((p) =>
      `- ${planetLabel(p.key)}: ${p.rashi} (${p.sign}) ${p.degree.toFixed(1)}°, ${p.nakshatra} pada ${p.pada}, ` +
      `${ORDINALS[p.house]} house${p.dignity ? `, ${p.dignity === "own" ? "own sign" : p.dignity}` : ""}` +
      `${p.retrograde && p.key !== "rahu" && p.key !== "ketu" ? ", retrograde" : ""}`
    ),
    `- Lagna: ${chart.lagna.rashi} (${chart.lagna.sign}) ${chart.lagna.degree.toFixed(1)}°`,
    "",
    "THE HOUSES:",
    ...chart.houses.map((h) =>
      `- ${ORDINALS[h.house]}: ${h.rashi} (${h.sign}), lord ${planetLabel(h.lord)}` +
      (h.occupants.length ? `; holds ${h.occupants.map(planetLabel).join(", ")}` : "; empty")
    ),
    "",
    chart.dasha
      ? `THE DASHA: Mahadasha of ${planetLabel(chart.dasha.mahadasha_planet)} (${chart.dasha.maha_phase} in its ` +
        `period), Antardasha of ${planetLabel(chart.dasha.antardasha_planet)} (${chart.dasha.antar_phase}).`
      : "THE DASHA: not available.",
    "",
    "EVIDENCE (copy these codes exactly into each insight's evidence):",
    ...[...facts].map(([code, sentence]) => `- ${code}: ${sentence}`),
    "",
    "KEY PLACEMENTS FOR EACH AREA:",
    ...INSIGHT_KEYS.map((key) => `- ${key}: ${topics[key].join(", ") || "(read from the lords above)"}`),
    "",
    "The highlights must follow this order: " + PLANETS.map((p) => p.key).join(", ") + ".",
  ];

  return lines.join("\n");
}

// ---------------------------------------------------------------- normalising

export interface KundaliInsight {
  evidence: string[];
  summary: string;
  detail: string;
  tip: string;
}

export interface KundaliReport {
  invocation: string;
  headline: string;
  highlights: Array<{ planet: PlanetKey; line: string }>;
  insights: Record<InsightKey, KundaliInsight>;
  houses: Array<{ house: number; theme: string }>;
  dasha_summary: string;
  blessing: string;
}

export interface NormalisedKundali {
  report: KundaliReport;
  /** False when the reading is too thin or too ungrounded to show; the worker retries. */
  usable: boolean;
  problems: string[];
}

/** A year (1800–2199, in Latin or Devanagari digits), or an age. */
const DATED = [
  /(?<!\d)(1[89]|2[01])\d{2}(?!\d)/,
  /[१२][०-९]{3}/,
  /\b(at|by|around|before|after)\s+(the\s+)?age\s+(of\s+)?\d{1,3}\b/i,
  /\b\d{1,3}(st|nd|rd|th)?\s+(birthday|year of (your )?life)\b/i,
];

/**
 * Drops any sentence that names a year or an age. BOUNDARIES already forbids them; this is the
 * belt to its braces, because a single "in 2027" in a paid report is the kind of promise a user
 * holds an app to.
 */
export function withoutDates(value: string): string {
  if (!DATED.some((re) => re.test(value))) return value;
  return value
    .split(/(?<=[.!?।])\s+/)
    .filter((sentence) => !DATED.some((re) => re.test(sentence)))
    .join(" ")
    .trim();
}

const clean = (value: unknown, max: number) => withoutDates(text(value, max));

export function normaliseKundaliReport(raw: unknown, chart: KundaliChartJson): NormalisedKundali {
  const root = (raw ?? {}) as Record<string, unknown>;
  const codes = evidenceFor(chart);
  const problems: string[] = [];

  const highlightsByPlanet = new Map<PlanetKey, string>();
  for (const entry of Array.isArray(root.highlights) ? root.highlights : []) {
    const item = (entry ?? {}) as Record<string, unknown>;
    const planet = String(item.planet ?? "") as PlanetKey;
    const line = clean(item.line, 160);
    if (!PLANET_KEYS.includes(planet) || highlightsByPlanet.has(planet) || !line) continue;
    highlightsByPlanet.set(planet, line);
  }
  // In the chart's own order, whatever order the model used.
  const highlights = PLANET_KEYS
    .filter((key) => highlightsByPlanet.has(key))
    .map((planet) => ({ planet, line: highlightsByPlanet.get(planet)! }));
  if (highlights.length < 7) problems.push(`only ${highlights.length} highlights`);

  const rawInsights = (root.insights ?? {}) as Record<string, unknown>;
  let ungrounded = 0;
  const insights = Object.fromEntries(INSIGHT_KEYS.map((key) => {
    const item = (rawInsights[key] ?? {}) as Record<string, unknown>;
    const evidence = [...new Set(
      (Array.isArray(item.evidence) ? item.evidence : [])
        .map((code) => String(code ?? "").trim())
        .filter((code) => codes.has(code)),
    )].slice(0, 5);

    const insight: KundaliInsight = {
      evidence,
      summary: clean(item.summary, 180),
      detail: clean(item.detail, 900),
      tip: clean(item.tip, 180),
    };

    if (!insight.detail || !insight.summary) problems.push(`${key} is empty`);
    if (evidence.length === 0) {
      ungrounded += 1;
      problems.push(`${key} cites no valid evidence`);
    }
    return [key, insight];
  })) as Record<InsightKey, KundaliInsight>;

  const themes = new Map<number, string>();
  for (const entry of Array.isArray(root.houses) ? root.houses : []) {
    const item = (entry ?? {}) as Record<string, unknown>;
    const house = Number(item.house);
    const theme = clean(item.theme, 120);
    if (!Number.isInteger(house) || house < 1 || house > 12 || themes.has(house) || !theme) continue;
    themes.set(house, theme);
  }
  const houses = [...themes].sort(([a], [b]) => a - b).map(([house, theme]) => ({ house, theme }));

  const report: KundaliReport = {
    invocation: clean(root.invocation, 200),
    headline: clean(root.headline, 120),
    highlights,
    insights,
    houses,
    dasha_summary: clean(root.dasha_summary, 420),
    blessing: clean(root.blessing, 240),
  };

  if (!report.headline) problems.push("no headline");

  const empty = INSIGHT_KEYS.filter((key) => !insights[key].detail || !insights[key].summary).length;
  const usable = report.headline.length > 0 && highlights.length >= 7 && empty === 0 && ungrounded < 2;

  return { report, usable, problems };
}
