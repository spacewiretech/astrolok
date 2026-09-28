import { assert, assertEquals } from "jsr:@std/assert@1";

import { describeKundli, kundliStrengths, miniKundli, weakGrahas } from "../_shared/mini_kundli.ts";
import { computeKundaliChart, KundaliChart } from "../_shared/kundali_chart.ts";
import { localToUtc } from "../_shared/birth_timezone.ts";
import { computeChart } from "../_shared/jyotish.ts";
import { buildUserPromptV5, ChatContextV5, goodInChart } from "../_shared/astro_chat_v5.ts";
import { describeUpay, upayFor } from "../_shared/chat_upay.ts";
import { chatTiming } from "../_shared/chat_timing.ts";
import { transitTiming } from "../_shared/chat_transits.ts";

/**
 * The chat's own small kundli (`mini_kundli.ts`): cast only with all four birth details, every
 * position in THEIR KUNDALI the one `computeKundaliChart` gives, only true strengths, the grahas an
 * upay would strengthen, and Chandra and the dasha never contradicting THEIR CHART.
 */

const NOW = new Date("2026-09-28T04:30:00Z"); // 10:00 on a Monday in India

/** Priya: 15 August 1998, 07:00, Rampur (UP). */
const PRIYA = {
  dob: "1998-08-15",
  birth_time: "07:00:00",
  birth_lat: 28.81,
  birth_lng: 79.025,
  birth_tz: "Asia/Calcutta",
};

const ordinal = (n: number) => n === 1 ? "1st" : n === 2 ? "2nd" : n === 3 ? "3rd" : `${n}th`;

/** The chart as the Kundali feature would cast it — independently of `miniKundli`. */
function castDirectly(u: typeof PRIYA, now = NOW): KundaliChart {
  const [year, month, day] = u.dob.split("-").map(Number);
  const [hour, minute] = u.birth_time.split(":").map(Number);
  const utc = localToUtc({ year, month, day, hour, minute }, u.birth_tz)!;
  return computeKundaliChart({
    dob: u.dob,
    birthTime: u.birth_time.slice(0, 5),
    utcOffsetSeconds: utc.offsetSeconds,
    latitude: u.birth_lat,
    longitude: u.birth_lng,
    asOf: now,
  })!;
}

const chatChart = (u: { dob: string; birth_time: string }) =>
  computeChart({ dob: u.dob, birthTime: u.birth_time, asOf: NOW });

// ---------------------------------------------------------------- only with all four

Deno.test("the kundli is cast only with the date, the hour, the coordinates and the zone", () => {
  assert(miniKundli(PRIYA, NOW));
  for (const missing of ["dob", "birth_time", "birth_lat", "birth_lng", "birth_tz"] as const) {
    assertEquals(miniKundli({ ...PRIYA, [missing]: null }, NOW), null, missing);
  }
  assertEquals(miniKundli({ ...PRIYA, birth_tz: "Not/AZone" }, NOW), null);
  assertEquals(miniKundli({ ...PRIYA, birth_time: "7 baje" }, NOW), null);
  assertEquals(miniKundli({ ...PRIYA, birth_lat: 123 }, NOW), null);
  // As PostgREST may hand a numeric column back: a string.
  assert(miniKundli({ ...PRIYA, birth_lat: "28.8100", birth_lng: "79.0250" }, NOW));
});

Deno.test("THEIR KUNDALI rides in THEIR CHART only when there is one", () => {
  const chart = chatChart(PRIYA);
  const base: ChatContextV5 = {
    chart,
    timing: null,
    transits: null,
    birthHourAsks: { asked: 1, declined: false },
    facts: [],
    firstReply: false,
    remediesGiven: [],
    hookGiven: false,
    planEnabled: false,
    care: false,
  };
  const withKundli = buildUserPromptV5("Meri shaadi kab hogi?", { ...base, kundli: miniKundli(PRIYA, NOW) });
  const theirChart = withKundli.slice(withKundli.indexOf("THEIR CHART"), withKundli.indexOf("\n\nTHE TIMING"));
  assert(theirChart.includes("THEIR KUNDALI — the whole chart, cast from their date, time and place of birth"));
  assert(theirChart.includes("- Lagna: Simha (Leo), ruled by Surya in the 12th house."));

  for (const kundli of [null, undefined, miniKundli({ ...PRIYA, birth_tz: null }, NOW)]) {
    assert(!buildUserPromptV5("x", { ...base, kundli }).includes("THEIR KUNDALI"));
  }
  // No date, no THEIR CHART — and no kundli smuggled in under "unavailable".
  assert(!buildUserPromptV5("x", { ...base, chart: null, kundli: miniKundli(PRIYA, NOW) }).includes("THEIR KUNDALI"));
});

// ---------------------------------------------------------------- every position is the chart's

Deno.test("for a fixed chart, the block's houses and dignities are computeKundaliChart's", () => {
  const direct = castDirectly(PRIYA);
  const block = describeKundli(miniKundli(PRIYA, NOW)!, chatChart(PRIYA));

  // Pinned, so a change to the astronomy shows up here as well as in kundali_chart_test.
  assertEquals(direct.lagna.rashi, "Simha");
  const pinned = Object.fromEntries(direct.planets.map((p) => [p.sanskrit, [p.rashi, p.house, p.dignity]]));
  assertEquals(pinned, {
    Surya: ["Karka", 12, null],
    Chandra: ["Vrishabha", 10, "exalted"],
    Mangal: ["Karka", 12, "debilitated"],
    Budh: ["Karka", 12, null],
    Guru: ["Meena", 8, "own"],
    Shukra: ["Karka", 12, null],
    Shani: ["Mesha", 9, "debilitated"],
    Rahu: ["Simha", 1, null],
    Ketu: ["Kumbha", 7, null],
  });

  assert(block.includes(
    "- The grahas: Surya in Karka, the 12th house · Chandra in Vrishabha, the 10th house, exalted " +
      "(uchcha) · Mangal in Karka, the 12th house, debilitated (neecha) · Budh in Karka, the 12th " +
      "house · Guru in Meena, the 8th house, in its own rashi (swagrahi) · Shukra in Karka, the " +
      "12th house · Shani in Mesha, the 9th house, debilitated (neecha) · Rahu in Simha, the 1st " +
      "house · Ketu in Kumbha, the 7th house.",
  ));
  // The houses each matter is read from, counted from the lagna, and where their lords sit.
  assert(block.includes("the 7th, of marriage and partnership — Kumbha, its lord Shani in the 9th house"));
  assert(block.includes("the 10th, of work — Vrishabha, its lord Shukra in the 12th house"));
  assert(block.includes("the 5th, of romance, children and learning — Dhanu, its lord Guru in the 8th house"));
  assert(block.includes("the 2nd, of savings") && block.includes("the 11th, of gains"));
  assert(block.includes("the 6th, of debts") && block.includes("the 4th, of home"));
  // The dasha THEIR CHART names, and where its lords sit.
  assert(block.includes(
    "- The dasha running now: Rahu's Mahadasha — Rahu sits in the 1st house; within it, Shani's " +
      "Antardasha — Shani sits in the 9th house and rules the 6th and 7th.",
  ));
  assert(block.includes("never recite it or list the grahas to them"));
  assert(block.includes("A debilitated graha is never bad news to them"));
});

/** Births across forty years and three clocks: every planet in the block as the chart places it. */
const SWEEP = Array.from({ length: 120 }, (_, i) => {
  const zones = [
    { birth_lat: 28.6139, birth_lng: 77.209, birth_tz: "Asia/Kolkata" },
    { birth_lat: 13.0827, birth_lng: 80.2707, birth_tz: "Asia/Calcutta" },
    { birth_lat: 51.5072, birth_lng: -0.1276, birth_tz: "Europe/London" },
  ];
  const day = new Date(Date.UTC(1965, 0, 1) + i * 127 * 86_400_000);
  return {
    dob: day.toISOString().slice(0, 10),
    birth_time: `${String((i * 7) % 24).padStart(2, "0")}:${String((i * 13) % 60).padStart(2, "0")}`,
    ...zones[i % 3],
  };
});

Deno.test("across forty years of births, every position named is the one the chart gives", () => {
  for (const u of SWEEP) {
    const direct = castDirectly(u);
    const chart = chatChart(u);
    const block = describeKundli(miniKundli(u, NOW)!, chart);
    const moonAgrees = direct.planets.find((p) => p.key === "moon")!.rashi === chart!.moonRashi;
    assert(block.includes(`- Lagna: ${direct.lagna.rashi} (`), u.dob);
    for (const p of direct.planets) {
      const said = `${p.sanskrit} in ${p.rashi}, the ${ordinal(p.house)} house`;
      if (p.key === "moon" && !moonAgrees) {
        assert(!block.includes("Chandra in "), `${u.dob}: a Chandra THEIR CHART does not hold`);
        continue;
      }
      assert(block.includes(said), `${u.dob}: ${said}`);
      const dignity = p.dignity === "exalted" ? "exalted" : p.dignity === "own" ? "own rashi" : p.dignity === "debilitated" ? "debilitated" : null;
      const tail = block.slice(block.indexOf(said) + said.length).split(" · ")[0];
      assertEquals(dignity ? tail.includes(dignity) : !/exalted|own rashi|debilitated/.test(tail), true, `${u.dob}: ${said}${tail}`);
    }
  }
});

// ---------------------------------------------------------------- Chandra and the dasha agree

Deno.test("born off India's clock: Chandra only where the charts agree, and THEIR CHART's dasha", () => {
  // 22:15 in Chicago on 2 May 1990: India's clock puts Chandra in Karka, Chicago's in Simha.
  const u = { dob: "1990-05-02", birth_time: "22:15", birth_lat: 41.8781, birth_lng: -87.6298, birth_tz: "America/Chicago" };
  const chart = chatChart(u)!;
  const kundli = miniKundli(u, NOW)!;
  assertEquals([chart.moonRashi, kundli.planets.find((p) => p.key === "moon")!.rashi], ["Karka", "Simha"]);
  assertEquals([chart.dasha!.mahadasha, kundli.dasha!.mahadasha], ["Chandra", "Chandra"]);
  assert(chart.dasha!.antardasha !== kundli.dasha!.antardasha);

  const block = describeKundli(kundli, chart);
  assert(!/Chandra in (?:Karka|Simha)/.test(block));
  assert(block.includes(`Chandra's Mahadasha — Chandra rules the 9th; within it, ${chart.dasha!.antardasha}'s Antardasha`));
  assert(!block.includes(`${kundli.dasha!.antardasha}'s Antardasha`));
  // Nor a Chandra strength or weakness drawn from the other clock.
  assert(!kundliStrengths(kundli, chart).some((line) => line.includes("Chandra")));
  assert(!weakGrahas(kundli, "general", chart).includes("Chandra"));
});

// ---------------------------------------------------------------- strengths: only true ones

const KENDRA_TRIKONA = [1, 4, 5, 7, 9, 10];

/** Checks one strength line against the chart it came from. */
function holds(line: string, k: KundaliChart): boolean {
  const planet = (name: string) => k.planets.find((p) => p.sanskrit === name)!;
  let m = /^The lord of their lagna, (\w+), sits in the (\d+)\w\w house/.exec(line);
  if (m) {
    const p = planet(m[1]);
    return p.key === k.lagna.lord && p.house === Number(m[2]) && KENDRA_TRIKONA.includes(p.house) &&
      p.dignity !== "debilitated";
  }
  m = /^(\w+) is exalted \(uchcha\) in (\w+)/.exec(line);
  if (m) return planet(m[1]).dignity === "exalted" && planet(m[1]).rashi === m[2];
  m = /^(\w+) is in its own rashi, (\w+) \(swagrahi\)/.exec(line);
  if (m) return planet(m[1]).dignity === "own" && planet(m[1]).rashi === m[2];
  m = /^(Guru|Shukra), a benefic, sits in the (\d+)\w\w house from their lagna/.exec(line);
  if (m) {
    const p = planet(m[1]);
    return p.house === Number(m[2]) && KENDRA_TRIKONA.includes(p.house) && p.dignity !== "debilitated";
  }
  return false;
}

Deno.test("every strength named is true of the chart, and none is invented", () => {
  let named = 0;
  for (const u of SWEEP) {
    const k = miniKundli(u, NOW)!;
    const lines = kundliStrengths(k, chatChart(u));
    assert(lines.length <= 4);
    for (const line of lines) assert(holds(line, k), `${u.dob}: ${line}`);
    named += lines.length;
  }
  assert(named > 100, "the sweep should find strengths to check");

  // Priya: an exalted Chandra and Guru at home — and not her lagna lord, Surya in the 12th.
  assertEquals(kundliStrengths(miniKundli(PRIYA, NOW), chatChart(PRIYA)), [
    "Chandra is exalted (uchcha) in Vrishabha in their kundali — at its very strongest.",
    "Guru is in its own rashi, Meena (swagrahi) — strong and at home.",
  ]);
  // 17 January 1985, 10:30 in Delhi: nothing that qualifies, so nothing at all.
  const bare = { dob: "1985-01-17", birth_time: "10:30", birth_lat: 28.6139, birth_lng: 77.209, birth_tz: "Asia/Kolkata" };
  assertEquals(kundliStrengths(miniKundli(bare, NOW), chatChart(bare)), []);
  assertEquals(kundliStrengths(null, null), []);
});

Deno.test("THE GOOD IN THEIR CHART carries the kundli's strengths after the Moon chart's own", () => {
  const chart = chatChart(PRIYA)!;
  const timing = chatTiming(chart, { dob: PRIYA.dob, asOf: NOW, v5: true });
  const transits = transitTiming(chart.moonRashi, NOW);
  const more = kundliStrengths(miniKundli(PRIYA, NOW), chart);
  const good = goodInChart({ chart, timing, transits, more });
  assertEquals(good.slice(-more.length), more);
  const prompt = buildUserPromptV5("x", {
    chart,
    timing,
    transits,
    birthHourAsks: { asked: 1, declined: false },
    facts: [],
    firstReply: false,
    remediesGiven: [],
    hookGiven: false,
    planEnabled: false,
    care: false,
    strengths: good,
  });
  assert(prompt.includes("- Guru is in its own rashi, Meena (swagrahi) — strong and at home."));
});

// ---------------------------------------------------------------- what an upay would strengthen

Deno.test("the grahas an upay would strengthen: debilitated, then beside a node, for the matter", () => {
  const k = miniKundli(PRIYA, NOW);
  const chart = chatChart(PRIYA);
  // Shani rules her 7th from the lagna, and is debilitated; Mangal is too, but bears on no marriage.
  assertEquals(weakGrahas(k, "marriage", chart), ["Shani"]);
  assertEquals(weakGrahas(k, "career", chart), ["Shani"]);
  assertEquals(weakGrahas(k, "money", chart), []);
  assertEquals(weakGrahas(k, "general", chart), ["Mangal", "Shani"]);
  assertEquals(weakGrahas(null, "marriage", null), []);

  // 3 January 1985, 10:30 in Delhi: Budh and Shani share the 10th with a node, neither in dignity.
  const nodes = { dob: "1985-01-03", birth_time: "10:30", birth_lat: 28.6139, birth_lng: 77.209, birth_tz: "Asia/Kolkata" };
  assertEquals(weakGrahas(miniKundli(nodes, NOW), "general", chatChart(nodes)), ["Budh", "Shani"]);
});

Deno.test("THE UPAY FOR TODAY strengthens the graha the kundli names, and says so", () => {
  // 3 November 1985, 10:30 in Delhi: Guru and Shukra debilitated — both bear on marriage — in a
  // Budh dasha, which no marriage remedy's day matches.
  const u = { dob: "1985-11-03", birth_time: "10:30", birth_lat: 28.6139, birth_lng: 77.209, birth_tz: "Asia/Kolkata" };
  const chart = chatChart(u)!;
  const weak = weakGrahas(miniKundli(u, NOW), "marriage", chart);
  assertEquals(weak, ["Guru", "Shukra"]);

  // Monday, with Monday's 16 Somvar already given: the marriage remedies left fall on Thursday
  // and Friday, and the kundli's Guru chooses between them.
  const upay = upayFor("marriage", { now: NOW, chart, weakGrahas: weak, given: ["shiv_jal"] });
  assertEquals([upay.id, upay.strengthens], ["kele_jal", { graha: "Guru", because: "kundali" }]);
  assert(describeUpay(upay, { hook: null }).includes("it strengthens Guru, which their kundali wants stronger"));

  const without = upayFor("marriage", { now: NOW, chart, given: ["shiv_jal"] });
  assertEquals(without.strengthens, null);
});

// ---------------------------------------------------------------- nothing written

Deno.test("the kundli is cast, never stored: no database, no kundalis, no re-cast", async () => {
  for (const file of ["mini_kundli.ts", "chat_birth_place.ts"]) {
    const source = await Deno.readTextFile(new URL(`../_shared/${file}`, import.meta.url));
    const code = source.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, "");
    assert(!/from\(\s*["']kundalis["']\s*\)/.test(code), `${file} reads or writes kundalis`);
    assert(!/recastKundali|replace_live_kundali|generateKundaliNow/.test(code), `${file} re-casts`);
  }
  const mini = await Deno.readTextFile(new URL("../_shared/mini_kundli.ts", import.meta.url));
  assert(!/\.from\(|\.rpc\(|fetch\(/.test(mini.replace(/\/\*[\s\S]*?\*\//g, "")), "mini_kundli.ts is not pure");
});
