import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";

import {
  DEFAULT_STAGE_FRACTIONS,
  kundaliPayload,
  KundaliRow,
  kundaliState,
  nextAttemptAt,
  parseKundaliRequest,
  parseStageFractions,
  sameBirthInputs,
  stageTimeline,
} from "../_shared/kundali.ts";
import { computeKundaliChart, kundaliChartToJson } from "../_shared/kundali_chart.ts";
import {
  buildKundaliPrompt,
  evidenceFor,
  INSIGHT_KEYS,
  kundaliSchema,
  kundaliSystemPrompt,
  normaliseKundaliReport,
  topicFacts,
  withoutDates,
} from "../_shared/kundali_reading.ts";

const NOW = new Date("2026-09-17T10:00:00Z");

const chart = kundaliChartToJson(computeKundaliChart({
  dob: "1990-01-01",
  birthTime: "12:00",
  utcOffsetSeconds: 19800,
  latitude: 28.6139,
  longitude: 77.209,
  asOf: NOW,
})!);

function row(overrides: Partial<KundaliRow> = {}): KundaliRow {
  return {
    id: "8a1f5c2e-0000-4000-8000-000000000001",
    user_id: "u1",
    status: "ready",
    dob: "1990-01-01",
    birth_time: "12:00:00",
    birth_place: "New Delhi, Delhi, India",
    birth_place_id: "ChIJLbZ-NFv9DDkRQJY4FbcFcgM",
    birth_lat: 28.6139,
    birth_lng: 77.209,
    birth_tz: "Asia/Kolkata",
    utc_offset_seconds: 19800,
    chart,
    report: { headline: "A steady fire" } as never,
    language: "English",
    requested_at: "2026-09-16T09:00:00Z",
    unlock_at: "2026-09-17T09:00:00Z",
    generated_at: "2026-09-16T09:10:00Z",
    first_viewed_at: null,
    waiting_last_viewed_at: null,
    superseded_at: null,
    attempts: 1,
    ...overrides,
  };
}

const options = { now: NOW, entitled: true, includeReport: true, regenerationsLeft: 2, unlockHours: 24 };

// ---------------------------------------------------------------- the lock

Deno.test("the chart and report are never sent before the reveal, unentitled, unwritten or unasked", () => {
  const cases: Array<[string, KundaliRow, Partial<typeof options>, boolean]> = [
    ["revealed, ready, entitled, asked", row(), {}, true],
    ["before unlock", row({ unlock_at: "2026-09-17T10:00:01Z" }), {}, false],
    ["exactly at unlock", row({ unlock_at: "2026-09-17T10:00:00Z" }), {}, true],
    ["not entitled", row(), { entitled: false }, false],
    ["status queued", row({ status: "queued", report: null }), {}, false],
    ["status generating", row({ status: "generating" }), {}, false],
    ["status failed", row({ status: "failed" }), {}, false],
    ["ready but no report", row({ report: null }), {}, false],
    ["summary only", row(), { includeReport: false }, false],
  ];

  for (const [name, r, overrides, revealed] of cases) {
    const payload = kundaliPayload(r, { ...options, ...overrides });
    assertEquals("chart" in payload, revealed, `${name}: chart`);
    assertEquals("report" in payload, revealed, `${name}: report`);
    // The teaser is arithmetic and always present.
    assertEquals((payload.teaser as Record<string, unknown>).moon_rashi, chart.moon.rashi, `${name}: teaser`);
  }
});

Deno.test("state follows the clock and the status", () => {
  assertEquals(kundaliState(row({ unlock_at: "2026-09-18T00:00:00Z" }), NOW), "waiting");
  assertEquals(kundaliState(row({ unlock_at: "2026-09-18T00:00:00Z", status: "ready" }), NOW), "waiting");
  assertEquals(kundaliState(row(), NOW), "ready");
  assertEquals(kundaliState(row({ status: "queued" }), NOW), "delayed");
  assertEquals(kundaliState(row({ status: "failed" }), NOW), "failed");
});

Deno.test("the summary carries what the waiting screen needs", () => {
  const payload = kundaliPayload(row({ unlock_at: "2026-09-18T09:00:00Z" }), { ...options, includeReport: false });
  assertEquals(payload.state, "waiting");
  assertEquals(payload.server_now, NOW.toISOString());
  assertEquals((payload.birth as Record<string, unknown>).birth_time, "12:00");
  assertEquals((payload.stages as unknown[]).length, 4);
  assertEquals(payload.viewed, false);
  assertEquals(payload.regenerations_left, 2);
});

// ---------------------------------------------------------------- stages and backoff

Deno.test("stages tick off across the wait and the last one lands on the reveal", () => {
  const stages = stageTimeline("2026-09-16T00:00:00Z", "2026-09-17T00:00:00Z");
  assertEquals(stages.map((s) => s.key), ["positions", "lagna", "dasha", "insights"]);
  assertEquals(stages[3].completes_at, "2026-09-17T00:00:00.000Z");
  for (let i = 1; i < stages.length; i++) assert(stages[i].completes_at > stages[i - 1].completes_at);
});

Deno.test("a malformed stage config falls back rather than ticking everything off at once", () => {
  assertEquals(parseStageFractions("0.1,0.2,0.5,1"), [0.1, 0.2, 0.5, 1]);
  assertEquals(parseStageFractions(""), DEFAULT_STAGE_FRACTIONS);
  assertEquals(parseStageFractions("0.5,0.2,0.9,1"), DEFAULT_STAGE_FRACTIONS);
  assertEquals(parseStageFractions("0.1,0.2,0.5"), DEFAULT_STAGE_FRACTIONS);
  assertEquals(parseStageFractions("0.1,0.2,0.5,0.9"), DEFAULT_STAGE_FRACTIONS);
});

Deno.test("retries back off from five minutes and cap at three hours", () => {
  const minutes = (n: number) => (nextAttemptAt(n, NOW).getTime() - NOW.getTime()) / 60_000;
  assertEquals(minutes(1), 5);
  assertEquals(minutes(2), 10);
  assertEquals(minutes(4), 40);
  assertEquals(minutes(10), 180);
});

// ---------------------------------------------------------------- the request

const REQUEST = {
  dob: "1990-01-01",
  birth_time: "12:00",
  place: { place_id: "ChIJLbZ-NFv9DDkRQJY4FbcFcgM", label: "New Delhi, Delhi, India", lat: 28.61394, lng: 77.20902, time_zone_id: "Asia/Kolkata" },
};

Deno.test("a well-formed request is read, with the offset of the birth moment", () => {
  const parsed = parseKundaliRequest(REQUEST, NOW);
  assert(parsed.ok);
  assertEquals(parsed.value.utcOffsetSeconds, 19800);
  assertEquals(parsed.value.place.latitude, 28.6139);

  const wartime = parseKundaliRequest({ ...REQUEST, dob: "1943-06-01" }, NOW);
  assert(wartime.ok);
  assertEquals(wartime.value.utcOffsetSeconds, 23400);
});

Deno.test("requests missing what a chart needs are refused with something to show", () => {
  const bad: unknown[] = [
    { ...REQUEST, dob: "01/01/1990" },
    { ...REQUEST, dob: "1899-12-31" },
    { ...REQUEST, dob: "2001-02-29" },
    { ...REQUEST, birth_time: "" },
    { ...REQUEST, birth_time: "24:00" },
    { ...REQUEST, place: { ...REQUEST.place, lat: "28.6" } },
    { ...REQUEST, place: { ...REQUEST.place, lng: 181 } },
    { ...REQUEST, place: { ...REQUEST.place, time_zone_id: "Nowhere/Else" } },
    { ...REQUEST, place: { ...REQUEST.place, label: "" } },
    { ...REQUEST, dob: "2026-09-18" },
    null,
  ];
  for (const body of bad) {
    const parsed = parseKundaliRequest(body, NOW);
    assertFalse(parsed.ok, JSON.stringify(body));
    if (!parsed.ok) assert(parsed.message.length > 0);
  }
});

Deno.test("the same details are recognised, by place id or by coordinates", () => {
  const parsed = parseKundaliRequest(REQUEST, NOW);
  assert(parsed.ok);
  assert(sameBirthInputs(row(), parsed.value));
  assert(sameBirthInputs(row({ birth_place_id: null }), parsed.value));
  assertFalse(sameBirthInputs(row({ birth_time: "12:01:00" }), parsed.value));
  assertFalse(sameBirthInputs(row({ birth_place_id: "other" }), parsed.value));
  // Coordinates purged after 30 days: the label is what is left to compare.
  assert(sameBirthInputs(row({ birth_place_id: null, birth_lat: null, birth_lng: null }), parsed.value));
});

// ---------------------------------------------------------------- the reading

function goodReport(): Record<string, unknown> {
  const codes = [...evidenceFor(chart).keys()];
  const topics = topicFacts(chart);
  return {
    invocation: "Sit with me a while.",
    headline: "A patient fire that builds slowly",
    highlights: chart.planets.map((p) => ({ planet: p.key, line: `${p.english} brings something.` })).reverse(),
    insights: Object.fromEntries(INSIGHT_KEYS.map((key) => [key, {
      evidence: [...topics[key].slice(0, 2), "made_up_code"].filter(Boolean).length > 1
        ? [...topics[key].slice(0, 2), "made_up_code"]
        : [codes[0], "made_up_code"],
      summary: `The ${key} summary.`,
      detail: `The ${key} detail rests on what the chart shows.`,
      tip: "A small kindness.",
    }])),
    houses: Array.from({ length: 12 }, (_, i) => ({ house: 12 - i, theme: `Theme ${12 - i}` })),
    dasha_summary: "A season of steady work.",
    blessing: "May your patience find good company.",
  };
}

Deno.test("a good report is kept, reordered, and stripped of invented evidence", () => {
  const { report, usable, problems } = normaliseKundaliReport(goodReport(), chart);
  assert(usable, problems.join("; "));
  assertEquals(report.highlights.map((h) => h.planet), chart.planets.map((p) => p.key));
  assertEquals(report.houses.map((h) => h.house), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
  for (const key of INSIGHT_KEYS) {
    assertFalse(report.insights[key].evidence.includes("made_up_code"));
    assert(report.insights[key].evidence.length > 0);
  }
});

Deno.test("a report citing nothing real is unusable, so the worker tries again", () => {
  const raw = goodReport();
  const insights = raw.insights as Record<string, Record<string, unknown>>;
  insights.love.evidence = ["nope"];
  insights.career.evidence = [];
  const { usable, problems } = normaliseKundaliReport(raw, chart);
  assertFalse(usable);
  assert(problems.some((p) => p.includes("love")));
});

Deno.test("a thin report — no headline, missing insights, few highlights — is unusable", () => {
  assertFalse(normaliseKundaliReport({ ...goodReport(), headline: "" }, chart).usable);
  assertFalse(normaliseKundaliReport({ ...goodReport(), highlights: [] }, chart).usable);
  const raw = goodReport();
  delete (raw.insights as Record<string, unknown>).finance;
  assertFalse(normaliseKundaliReport(raw, chart).usable);
  assertFalse(normaliseKundaliReport(null, chart).usable);
});

Deno.test("sentences naming a year or an age are dropped", () => {
  assertEquals(withoutDates("Work steadies. In 2027 it blooms. Stay kind."), "Work steadies. Stay kind.");
  assertEquals(withoutDates("Around the age of 32 love arrives. Be open."), "Be open.");
  assertEquals(withoutDates("Your 10th house is strong."), "Your 10th house is strong.");
  assertEquals(withoutDates("२०२७ में सफलता। धैर्य रखें।"), "धैर्य रखें।");
});

Deno.test("the schema only admits this chart's own evidence codes", () => {
  const schema = kundaliSchema(chart) as any;
  const codes = schema.properties.insights.properties.love.properties.evidence.items.enum as string[];
  assertEquals(new Set(codes), new Set(evidenceFor(chart).keys()));
  assert(codes.includes(`lagna_${chart.lagna.rashi.toLowerCase()}`));
});

Deno.test("the prompt carries the chart, the evidence codes and the boundaries", () => {
  const prompt = buildKundaliPrompt(chart, { firstName: "Asha" });
  assert(prompt.includes("Asha"));
  for (const code of evidenceFor(chart).keys()) assert(prompt.includes(code), code);

  const system = kundaliSystemPrompt("Hindi");
  assert(system.includes("BOUNDARIES"));
  assert(system.includes("Never estimate, rank or allude to how much money"));
  assert(system.includes("Hindi"));
});
