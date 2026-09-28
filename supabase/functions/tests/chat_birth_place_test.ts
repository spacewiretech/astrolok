import { assert, assertEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

import {
  captureBirthPlace,
  deniesPlace,
  pickedPlace,
  placeQuery,
  questionBefore,
  readPlace,
  spokenPlace,
} from "../_shared/chat_birth_place.ts";
import { saysOwnDetailWrong } from "../_shared/birth_details.ts";
import { asksFor, describeSawal, sawalFor, SawalContext } from "../_shared/chat_sawal.ts";
import { buildUserPromptV5, ChatContextV5, kundaliLineFor, v5Body } from "../_shared/astro_chat_v5.ts";
import { UserRow } from "../_shared/entitlement.ts";
import { miniKundli } from "../_shared/mini_kundli.ts";

const flat = (text: string) => text.replace(/\s+/g, " ");

/**
 * The place of birth told in the chat (`chat_birth_place.ts`): typed or picked, found on the map,
 * saved only as a blank filled or a correction, said back, and asked again once when it cannot be
 * found. Google is never called: `fetch` is swapped for a recorder that answers as Places and the
 * Time Zone API do, and the database for one that records every table it is asked for — so a test
 * can say that `kundalis` was never touched.
 */

const NOW = new Date("2026-09-28T06:30:00Z");
const TOKEN = "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d";

// ---------------------------------------------------------------- Google, recorded

interface Call {
  url: string;
  method: string;
  body: Record<string, unknown> | null;
}

/** What each Google endpoint answers in a test. A function of the call, or a fixed body. */
interface Google {
  autocomplete?: unknown | ((body: Record<string, unknown>) => unknown);
  details?: unknown | ((placeId: string) => unknown);
  timezone?: unknown;
  /** An HTTP status to fail every call with. */
  status?: number;
}

const RAMPUR = {
  suggestions: [
    {
      placePrediction: {
        placeId: "ChIJrampurUP",
        structuredFormat: { mainText: { text: "Rampur" }, secondaryText: { text: "Uttar Pradesh, India" } },
      },
    },
    {
      placePrediction: {
        placeId: "ChIJrampurHP",
        structuredFormat: { mainText: { text: "Rampur" }, secondaryText: { text: "Himachal Pradesh, India" } },
      },
    },
  ],
};

const DETAILS: Record<string, unknown> = {
  ChIJrampurUP: { id: "ChIJrampurUP", formattedAddress: "Rampur, Uttar Pradesh, India", location: { latitude: 28.80999, longitude: 79.02501 } },
  ChIJrampurHP: { id: "ChIJrampurHP", formattedAddress: "Rampur, Himachal Pradesh 172001, India", location: { latitude: 31.4492, longitude: 77.6300 } },
  ChIJjaipur: { id: "ChIJjaipur", formattedAddress: "Jaipur, Rajasthan, India", location: { latitude: 26.912434, longitude: 75.787271 } },
};

function withGoogle(google: Google): { calls: Call[]; restore: () => void } {
  const calls: Call[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const body = init?.body ? JSON.parse(String(init.body)) : null;
    calls.push({ url, method: init?.method ?? "GET", body });
    const reply = (value: unknown, status = 200) =>
      Promise.resolve(new Response(JSON.stringify(value), { status }));
    if (google.status) return reply({ error: { status: "PERMISSION_DENIED" } }, google.status);

    if (url.endsWith("/places:autocomplete")) {
      const answer = typeof google.autocomplete === "function"
        ? google.autocomplete(body!)
        : google.autocomplete ?? RAMPUR;
      return reply(answer);
    }
    const details = /\/places\/([^?]+)\?/.exec(url);
    if (details) {
      const id = decodeURIComponent(details[1]);
      const answer = typeof google.details === "function" ? google.details(id) : google.details ?? DETAILS[id];
      return answer ? reply(answer) : reply({ error: { status: "NOT_FOUND" } }, 404);
    }
    if (url.includes("/timezone/json")) {
      return reply(google.timezone ?? { status: "OK", timeZoneId: "Asia/Calcutta" });
    }
    return reply({}, 500);
  }) as typeof fetch;
  return { calls, restore: () => { globalThis.fetch = original; } };
}

// ---------------------------------------------------------------- the database, recorded

interface Touch {
  table: string;
  update?: Record<string, unknown>;
  eq?: [string, unknown];
}

/** Records every table and RPC asked for; `users` answers with the row as the update left it. */
function fakeDb(row: Record<string, unknown>, { fail = false } = {}) {
  const touched: Touch[] = [];
  const db = {
    from(table: string) {
      const call: Touch = { table };
      touched.push(call);
      const query = {
        update(values: Record<string, unknown>) {
          call.update = values;
          return query;
        },
        eq(column: string, value: unknown) {
          call.eq = [column, value];
          return query;
        },
        select() {
          return query;
        },
        single() {
          return Promise.resolve(
            fail
              ? { data: null, error: { code: "23514", message: "check", details: "Failing row contains (secret)" } }
              : { data: { ...row, ...call.update }, error: null },
          );
        },
      };
      return query;
    },
    rpc(name: string) {
      touched.push({ table: `rpc:${name}` });
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { db: db as unknown as SupabaseClient, touched };
}

const CONFIG = new Map([["google_places_api_key", "test-key"]]);

function account(over: Partial<UserRow> = {}): UserRow {
  return {
    user_id: "u1",
    mobile_no: "9999999999",
    name: "Priya",
    dob: "1998-08-15",
    birth_time: "07:00:00",
    birth_place: null,
    birth_place_id: null,
    birth_lat: null,
    birth_lng: null,
    birth_tz: null,
    payment_type: "trial",
    trial_ends_at: "2026-10-05T00:00:00Z",
    current_period_end: null,
    ...over,
  } as UserRow;
}

type Row = { role: string; body: Record<string, unknown> };
const user = (text: string): Row => ({ role: "user", body: { text } });
const astro = (body: Record<string, unknown>): Row => ({ role: "astro", body: { kind: "answer", ...body } });

/** A thread that has just asked for the place, newest first: the hour was asked and answered. */
const ASKED: Row[] = [
  astro({ ask_for: "birth_place" }),
  user("subah 7 baje"),
  astro({ ask_for: "birth_time" }),
  user("Meri shaadi kab hogi?"),
];

/** Captures under a recorded Google and database. */
async function capture(
  message: string,
  { rows = ASKED, over = {}, sent = undefined, google = {}, config = CONFIG, fail = false }: {
    rows?: Row[];
    over?: Partial<UserRow>;
    sent?: unknown;
    google?: Google;
    config?: Map<string, string>;
    fail?: boolean;
  } = {},
) {
  const me = account(over);
  const { db, touched } = fakeDb(me as unknown as Record<string, unknown>, { fail });
  const { calls, restore } = withGoogle(google);
  try {
    const result = await captureBirthPlace(db, config, me, rows, message, sent, NOW);
    return { result, me, touched, calls };
  } finally {
    restore();
  }
}

// ---------------------------------------------------------------- typed

Deno.test("a typed town is searched India-first, its top match located, and saved with its zone", async () => {
  const { result, me, touched, calls } = await capture("Rampur, UP");

  assertEquals(calls.length, 3);
  assert(calls[0].url.endsWith("/places:autocomplete"));
  assertEquals(calls[0].body?.input, "Rampur, UP");
  assertEquals(calls[0].body?.regionCode, "in");
  // One billed session: the search and the Details that ends it share a token.
  assert(calls[1].url.includes(`sessionToken=${calls[0].body?.sessionToken}`));
  assert(calls[1].url.includes("/places/ChIJrampurUP?"));
  assert(calls[2].url.includes("/timezone/json?location=28.80999,79.02501"));

  assertEquals(touched.map((t) => t.table), ["users"]);
  const saved = touched[0].update!;
  assertEquals(saved.birth_place, "Rampur, Uttar Pradesh, India");
  assertEquals(saved.birth_place_id, "ChIJrampurUP");
  assertEquals([saved.birth_lat, saved.birth_lng], [28.81, 79.025]);
  assertEquals(saved.birth_tz, "Asia/Calcutta");
  assertEquals(saved.birth_coords_at, NOW.toISOString());
  assertEquals(touched[0].eq, ["user_id", "u1"]);

  // Said back without the country, answering the question before the hour was asked.
  assertEquals(result?.captured, {
    field: "birth_place",
    said: "Rampur, Uttar Pradesh",
    question: "Meri shaadi kab hogi?",
  });
  assertEquals(result?.saved, { field: "birth_place", from: null, to: "Rampur, Uttar Pradesh, India" });
  // The account the app installs, and the one the rest of the turn reads.
  assertEquals((result?.user as Record<string, unknown>).birth_tz, "Asia/Calcutta");
  assertEquals((result?.user as Record<string, unknown>).birth_lat, 28.81);
  assertEquals([me.birth_place_id, me.birth_lat, me.birth_tz], ["ChIJrampurUP", 28.81, "Asia/Calcutta"]);
});

Deno.test("the sentence around a place is not searched for", () => {
  const cases: Array<[string, string]> = [
    ["Jaipur", "Jaipur"],
    ["mera janm Jaipur mein hua tha", "Jaipur"],
    ["Born in Rampur, UP", "Rampur, UP"],
    ["main Rampur, Uttar Pradesh mein paida hua tha", "Rampur, Uttar Pradesh"],
    ["जयपुर में हुआ था", "जयपुर"],
    ["मेरा जन्म रामपुर, उत्तर प्रदेश में हुआ", "रामपुर, उत्तर प्रदेश"],
    ["Sector 62, Noida", "Sector 62, Noida"],
    ["Gaya", "Gaya"],
    ["Muzaffarnagar ke paas ek gaon", "Muzaffarnagar"],
    ["Ahmednagar 🙏", "Ahmednagar"],
  ];
  for (const [said, query] of cases) assertEquals(placeQuery(said, NOW), query, said);
});

Deno.test("a word that is part of a place's name stays in it; standing apart, it goes", () => {
  const cases: Array<[string, string]> = [
    ["Cape Town", "Cape Town"],
    ["Kansas City", "Kansas City"],
    ["Mexico City", "Mexico City"],
    ["Port of Spain", "Port of Spain"],
    ["Old Town, Bhubaneswar", "Old Town, Bhubaneswar"],
    ["Model Town, Ludhiana", "Model Town, Ludhiana"],
    ["born in the city of Mysore", "Mysore"],
    ["I was born in the town of Nabha", "Nabha"],
  ];
  for (const [said, query] of cases) assertEquals(placeQuery(said, NOW), query, said);
});

Deno.test("a reply in a southern language is searched as the town, without the sentence or its \"in\"", () => {
  const cases: Array<[string, string]> = [
    ["ನಾನು ಮೈಸೂರಿನಲ್ಲಿ ಹುಟ್ಟಿದೆ", "ಮೈಸೂರ"],
    ["ಮೈಸೂರು", "ಮೈಸೂರು"],
    ["நான் சென்னையில் பிறந்தேன்", "சென்னை"],
    ["నేను విజయవాడలో పుట్టాను", "విజయవాడ"],
    ["ഞാൻ കൊച്ചിയിൽ ജനിച്ചു", "കൊച്ചി"],
  ];
  for (const [said, query] of cases) assertEquals(placeQuery(said, NOW), query, said);
});

Deno.test("a locality named for a subject is still a place: Laxmi Nagar is not about money", () => {
  for (const said of ["Laxmi Nagar, Delhi", "Prem Nagar, Dehradun", "Hospital Road, Jaipur", "School Road, Kanpur"]) {
    assertEquals(placeQuery(said, NOW), said, said);
  }
  // A subject said as a subject is not.
  assertEquals(placeQuery("shaadi ki baat chal rahi hai", NOW), null);
});

Deno.test("a place with a question after it is the place; the question is this turn's to answer", async () => {
  assertEquals(readPlace("Jaipur mein, par shaadi kab hogi?", NOW), { query: "Jaipur", asks: true });
  assertEquals(readPlace("Jaipur. Aur meri naukri kab lagegi?", NOW), { query: "Jaipur", asks: true });
  assertEquals(readPlace("Rampur, UP, aur shaadi kab hogi?", NOW), { query: "Rampur, UP", asks: true });
  assertEquals(readPlace("Mera janm Jaipur mein hua tha, kab shaadi hogi?", NOW), { query: "Jaipur", asks: true });
  // A question first, or a yes before it, is no place at all.
  for (const said of ["Meri shaadi kab hogi?", "Haan, par naukri kab lagegi?", "ok, aur kya?"]) {
    assertEquals(readPlace(said, NOW), null, said);
  }

  // Found and saved, and the reply answers the question they just asked, not the one before.
  const { result, calls } = await capture("Rampur, UP. Aur naukri kab lagegi?");
  assertEquals(calls[0].body?.input, "Rampur, UP");
  assertEquals(result?.captured, { field: "birth_place", said: "Rampur, Uttar Pradesh", question: null });
});

Deno.test("what is plainly not a place is never searched for — and nothing is saved", async () => {
  for (
    const said of [
      "Meri shaadi kab hogi?",
      "naukri ke baare mein batao",
      "pata nahi",
      "yaad nahi hai",
      "मुझे नहीं पता",
      "haan ji",
      "ok thank you",
      "hello",
      "15 August 1998",
      "subah 7 baje",
      "ye",
      "UP",
      "main ek chhote se gaon mein paida hua tha jiska naam mujhe ab yaad bhi nahi aata aur wahan koi nahi rehta",
    ]
  ) {
    assertEquals(placeQuery(said, NOW), null, said);
    const { result, touched, calls } = await capture(said);
    assertEquals([result, touched.length, calls.length], [null, 0, 0], said);
  }
});

Deno.test("an unasked town is not a place answer: nothing is looked up", async () => {
  const { result, calls, touched } = await capture("Jaipur", { rows: [astro({ ask_for: "none" }), user("hi")] });
  assertEquals([result, calls.length, touched.length], [null, 0, 0]);
  // Nor in a thread with no reply at all yet.
  assertEquals((await capture("Jaipur", { rows: [] })).result, null);
});

// ---------------------------------------------------------------- picked

Deno.test("a picked row is looked up by its id, without a search, and saved as the search showed it", async () => {
  const sent = { place_id: "ChIJjaipur", description: "Jaipur, Rajasthan, India", session_token: TOKEN };
  const { result, touched, calls } = await capture("Jaipur, Rajasthan, India", { sent });

  assertEquals(calls.length, 2);
  assert(calls[0].url.includes("/places/ChIJjaipur?sessionToken=" + TOKEN), "the app's session is closed");
  assert(calls[1].url.includes("/timezone/json"));
  const saved = touched[0].update!;
  assertEquals(
    [saved.birth_place, saved.birth_place_id, saved.birth_lat, saved.birth_lng, saved.birth_tz],
    ["Jaipur, Rajasthan, India", "ChIJjaipur", 26.9124, 75.7873, "Asia/Calcutta"],
  );
  assertEquals(result?.captured?.said, "Jaipur, Rajasthan");
});

Deno.test("a picked row works without a session token, and a malformed one is not a pick", async () => {
  const { calls } = await capture("Jaipur", { sent: { place_id: "ChIJjaipur", description: "Jaipur, Rajasthan, India" } });
  assertEquals(calls.length, 2);
  assert(/sessionToken=[0-9a-f-]{36}/.test(calls[0].url), "a session of its own");

  assertEquals(pickedPlace({ place_id: "../../etc", description: "x" }), null);
  assertEquals(pickedPlace({ place_id: "" }), null);
  assertEquals(pickedPlace("ChIJjaipur"), null);
  assertEquals(pickedPlace([{ place_id: "ChIJjaipur" }]), null);
  assertEquals(pickedPlace({ place_id: "ChIJjaipur", description: 7, session_token: "not-a-uuid" }), {
    placeId: "ChIJjaipur",
    description: "",
    sessionToken: null,
  });
});

Deno.test("typed words are saved as Google names the place — and so is a pick with no words", async () => {
  // The suggestion's own words can be theirs back ("Rampur, UP", seen live): Details' name says
  // which Rampur was found.
  const typed = await capture("Rampur, UP", {
    google: {
      autocomplete: {
        suggestions: [{ placePrediction: { placeId: "ChIJrampurUP", structuredFormat: { mainText: { text: "Rampur" }, secondaryText: { text: "UP" } } } }],
      },
    },
  });
  assertEquals(typed.touched[0].update?.birth_place, "Rampur, Uttar Pradesh, India");
  assertEquals(typed.result?.captured?.said, "Rampur, Uttar Pradesh");

  const { touched } = await capture("📍", { sent: { place_id: "ChIJrampurHP" } });
  assertEquals(touched[0].update?.birth_place, "Rampur, Himachal Pradesh, India");
  assertEquals(spokenPlace("Rampur, Himachal Pradesh 172001, India"), "Rampur, Himachal Pradesh");
  assertEquals(spokenPlace("Chicago, IL, USA"), "Chicago, IL, USA");
});

// ---------------------------------------------------------------- not found

Deno.test("a place the map cannot find is not saved, and is asked for once more, then left", async () => {
  const empty = await capture("Xqzvbn", { google: { autocomplete: { suggestions: [] } } });
  assertEquals(empty.result, { failed: "birth_place" });
  assertEquals([empty.touched.length, empty.calls.length], [0, 1]);

  // Google refusing, a bad id, an unknown zone: each is a place not found, and never an error.
  for (
    const google of [
      { status: 403 },
      { status: 429 },
      { details: () => null },
      { timezone: { status: "ZERO_RESULTS" } },
      { timezone: { status: "OK", timeZoneId: "Mars/Olympus_Mons" } },
    ] as Google[]
  ) {
    const { result, touched } = await capture("Rampur", { google });
    assertEquals([result, touched.length], [{ failed: "birth_place" }, 0], JSON.stringify(google));
  }

  // The sawal asks again — the town and the state — once, and the second failure is let go.
  const base = sawalContext({ place: false });
  const again = sawalFor({ ...base, placeAsks: 1, captureFailed: "birth_place" });
  assertEquals([again.about, again.because, again.askFor], ["birth_place", "unreadable", "birth_place"]);
  assert(describeSawal(again).includes("shehar aur kaunsa rajya"));
  assertEquals(sawalFor({ ...base, placeAsks: 2, captureFailed: "birth_place" }).about, "situation");
});

Deno.test("a lookup or a write that fails never fails the turn, nor logs the place", async () => {
  const logged: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logged.push(args.map(String).join(" "));
  try {
    const refused = await capture("Rampur", { google: { status: 403 } });
    assertEquals(refused.result, { failed: "birth_place" });
    const unsaved = await capture("Rampur", { fail: true });
    assertEquals(unsaved.result, null);
    const unkeyed = await capture("Rampur", { config: new Map() });
    assertEquals([unkeyed.result, unkeyed.calls.length], [null, 0]);
  } finally {
    console.error = original;
  }
  assert(logged.length >= 2);
  for (const line of logged) {
    assert(!/rampur|secret|failing row/i.test(line), `the place reached the log: ${line}`);
  }
});

Deno.test("place search switched off from the dashboard spends nothing", async () => {
  const off = new Map([["google_places_api_key", "k"], ["place_search_enabled", "false"]]);
  const { result, calls } = await capture("Rampur", { config: off });
  assertEquals([result, calls.length], [null, 0]);
});

// ---------------------------------------------------------------- never over what is there

Deno.test("coordinates on file are never overwritten, nor even looked up", async () => {
  const located = { birth_place: "Jaipur, Rajasthan, India", birth_place_id: "ChIJjaipur", birth_lat: 26.9124, birth_lng: 75.7873, birth_tz: "Asia/Calcutta" };
  for (const sent of [undefined, { place_id: "ChIJrampurUP", description: "Rampur, Uttar Pradesh, India" }]) {
    const { result, touched, calls } = await capture("Rampur", { over: located, sent });
    assertEquals([result, touched.length, calls.length], [null, 0, 0]);
  }
  // The place id alone, once `purge_expired` has cleared the coordinates, is still a place.
  const purged = await capture("Rampur", { over: { ...located, birth_lat: null, birth_lng: null } });
  assertEquals([purged.result, purged.calls.length], [null, 0]);
});

Deno.test("words on file that were never located are replaced by the place they name", async () => {
  const { result, touched } = await capture("Rampur, UP", { over: { birth_place: "Rampur" } });
  assertEquals(touched[0].update?.birth_place, "Rampur, Uttar Pradesh, India");
  assertEquals(result?.saved?.from, "Rampur");
});

Deno.test("a correction replaces a located place", async () => {
  const located = { birth_place: "Jaipur, Rajasthan, India", birth_place_id: "ChIJjaipur", birth_lat: 26.9124, birth_lng: 75.7873, birth_tz: "Asia/Calcutta" };

  // They said it was wrong, and were asked again (`saysOwnDetailWrong`, the sawal's "wrong").
  assertEquals(saysOwnDetailWrong("mera janm sthan galat hai"), "birth_place");
  const rows = [astro({ ask_for: "birth_place" }), user("mera janm sthan galat hai"), astro({ ask_for: "none" })];
  const { result, touched } = await capture("Rampur, UP", { over: located, rows });
  assertEquals(touched[0].update?.birth_place_id, "ChIJrampurUP");
  assertEquals(result?.saved, {
    field: "birth_place",
    from: "Jaipur, Rajasthan, India",
    to: "Rampur, Uttar Pradesh, India",
  });

  // And in the same breath as the answer.
  const direct = await capture("galat hai, sahi Rampur UP hai", { over: located, rows: [astro({ ask_for: "birth_place" })] });
  assertEquals(direct.touched[0]?.update?.birth_place_id, "ChIJrampurUP");
});

/** A thread whose last reply saved Rampur, UP and said it back, newest first. */
const SAID_BACK: Row[] = [
  astro({ ask_for: "none", saved: { field: "birth_place", from: null, to: "Rampur, Uttar Pradesh, India" } }),
  user("Rampur"),
  astro({ ask_for: "birth_place" }),
];
const RAMPUR_UP = {
  birth_place: "Rampur, Uttar Pradesh, India",
  birth_place_id: "ChIJrampurUP",
  birth_lat: 28.81,
  birth_lng: 79.025,
  birth_tz: "Asia/Calcutta",
};

Deno.test("a \"nahi\" to the place said back takes it off again, and is never searched for", async () => {
  // Answers to a question asked beside the check, live (review, 28 Sep): each had its leftover
  // words — "tak", "pasand", "dono" — found on the map, and saved over Rampur.
  for (
    const said of [
      "nahi",
      "Nahi abhi tak nahi",
      "Nahi, meri apni pasand hai",
      "nahi, dono",
      "Nahi, abhi koi baat nahi chal rahi",
      "nahi, Rampur Himachal wala",
      "galat hai",
      "नहीं",
      "ಇಲ್ಲ",
      "இல்லை, வேற ஊர்",
    ]
  ) {
    const { result, me, touched, calls } = await capture(said, { rows: SAID_BACK, over: RAMPUR_UP });
    assertEquals(calls.length, 0, said);
    assertEquals(result?.denied, true, said);
    // Off the account: the words it replaced back (none), and no id, coordinates or zone.
    assertEquals(touched.map((t) => t.table), ["users"], said);
    assertEquals(touched[0].update, {
      birth_place: null,
      birth_place_id: null,
      birth_lat: null,
      birth_lng: null,
      birth_tz: null,
      birth_coords_at: null,
    }, said);
    assertEquals([me.birth_place_id, me.birth_lat, me.birth_tz], [null, null, null], said);
    // So the small kundli is no longer cast from a place they called wrong, this turn or later.
    assertEquals(miniKundli(me, NOW), null, said);
    assertEquals((result?.user as Record<string, unknown>).birth_lat, null, said);
    // Nothing said back, so the next turn is not read as another answer to the check.
    assertEquals([result?.captured, result?.saved], [undefined, undefined], said);
  }

  // It was, before the no.
  assert(miniKundli(account(RAMPUR_UP), NOW) !== null);

  // Words on file before it go back.
  const words = [astro({ ask_for: "none", saved: { field: "birth_place", from: "Rampur", to: RAMPUR_UP.birth_place } })];
  assertEquals((await capture("nahi", { rows: words, over: RAMPUR_UP })).touched[0].update?.birth_place, "Rampur");

  // A place saved since, by the Kundali form, is not the chat's to take back.
  const formSaved = await capture("nahi", { rows: SAID_BACK, over: { ...RAMPUR_UP, birth_place: "Jaipur, Rajasthan, India", birth_place_id: "ChIJjaipur" } });
  assertEquals([formSaved.result, formSaved.touched.length], [{ denied: true }, 0]);

  // The sawal asks for it again, and the answer to that ask is read and replaces nothing wrong.
  const again = sawalFor({ ...sawalContext({ place: false }), placeAsks: 1, placeDenied: true });
  assertEquals([again.about, again.because, again.askFor], ["birth_place", "wrong", "birth_place"]);
  const asked = [astro({ ask_for: "birth_place" }), user("nahi"), ...SAID_BACK];
  const fixed = await capture("Rampur, Himachal Pradesh", {
    rows: asked,
    google: { autocomplete: { suggestions: [RAMPUR.suggestions[1]] } },
  });
  assertEquals(fixed.touched[0].update?.birth_place_id, "ChIJrampurHP");
});

Deno.test("only a no is a no: a yes, a question, and the southern words that only look like one", async () => {
  for (
    const said of [
      "haan sahi hai",
      "ji",
      "Shaadi kab hogi?",
      // "Yes, they are looking at a house here" — ಇಲ್ಲಿ is "here", not ಇಲ್ಲ.
      "ಹೌದು, ಇಲ್ಲಿ ಮನೆ ನೋಡುತ್ತಿದ್ದಾರೆ",
      // "…or the other one" — അല്ലെങ്കിൽ is "or", not അല്ല.
      "ശരി, അല്ലെങ്കിൽ അടുത്ത മാസം",
      "Nahan",
    ]
  ) {
    const { result, calls, touched } = await capture(said, { rows: SAID_BACK, over: RAMPUR_UP });
    assertEquals([result, calls.length, touched.length], [null, 0, 0], said);
    assertEquals(deniesPlace(said), false, said);
  }
  for (const said of ["nahi", "Nahi, Bareilly", "galat hai", "नहीं", "ಇಲ್ಲ", "ಅಲ್ಲ", "தவறு", "కాదు", "അല്ല", "wrong"]) {
    assert(deniesPlace(said), said);
  }
});

// ---------------------------------------------------------------- kundalis

Deno.test("a captured place writes the user alone: never kundalis, and no re-cast", async () => {
  // One after another: each swaps the global `fetch`.
  const flows = [
    await capture("Rampur, UP"),
    await capture("x", { sent: { place_id: "ChIJjaipur", description: "Jaipur, Rajasthan, India" } }),
    await capture("galat hai, sahi Rampur hai", {
      over: { birth_place_id: "ChIJjaipur", birth_lat: 26.9, birth_lng: 75.8, birth_tz: "Asia/Calcutta" },
    }),
  ];
  for (const { touched } of flows) {
    assertEquals(touched.map((t) => t.table), ["users"]);
    assert(!Object.keys(touched[0].update ?? {}).some((key) => !key.startsWith("birth_")));
  }
});

// ---------------------------------------------------------------- the question they asked

Deno.test("the reply to the place still answers the question asked before the details were", () => {
  assertEquals(questionBefore(ASKED), "Meri shaadi kab hogi?");
  assertEquals(questionBefore([astro({ ask_for: "birth_place" }), user("Naukri kab lagegi?")]), "Naukri kab lagegi?");
  assertEquals(questionBefore([astro({ ask_for: "birth_place" }), user("hi")]), null);
  assertEquals(questionBefore([]), null);
});

// ---------------------------------------------------------------- the sawal and the prompt

function sawalContext(over: Partial<SawalContext>): SawalContext {
  return {
    topic: "marriage",
    message: "Rampur",
    care: false,
    dob: true,
    hour: true,
    place: false,
    hourAsks: { asked: 1, declined: false },
    dobAsks: 0,
    placeAsks: 0,
    asked: [],
    ...over,
  };
}

Deno.test("the place just found is checked, as the reply's one question; then the sawal moves on", () => {
  // The check alone: a reply that also asked "Kya abhi ghar mein kisi rishte ki baat chal rahi
  // hai?" had its "Nahi, abhi koi baat nahi" read as a no to the place.
  const check = sawalFor(sawalContext({ place: true, placeAsks: 1, captured: "birth_place" }));
  assertEquals([check.about, check.askFor, check.question], ["place_check", "none", null]);
  const block = describeSawal(check, { placeFound: "Rampur, Uttar Pradesh" });
  assert(block.includes('"Rampur, Uttar Pradesh — sahi hai na?"'));
  assert(block.includes("no question about their situation beside it"));
  // Even under a detail called wrong in the same breath, and before an hour still missing.
  assertEquals(sawalFor(sawalContext({ place: true, hour: false, hourAsks: { asked: 0, declined: false }, captured: "birth_place" })).about, "place_check");

  const next = sawalFor(sawalContext({ message: "haan sahi hai", place: true, placeAsks: 1 }));
  assertEquals([next.about, next.askFor], ["situation", "none"]);
  // A place called wrong is asked about before a missing hour; at most twice in a thread.
  const wrong = sawalFor(sawalContext({ message: "meri birth place galat hai", place: true, hour: false, hourAsks: { asked: 0, declined: false } }));
  assertEquals([wrong.about, wrong.because], ["birth_place", "wrong"]);
  assert(describeSawal(wrong).includes("Sahi janm sthan"));
  assertEquals(sawalFor(sawalContext({ message: "meri birth place galat hai", place: true, placeAsks: 2 })).about, "situation");
  // "Papa ki janm ki jagah galat hai" is about papa.
  assertEquals(saysOwnDetailWrong("papa ka janm sthan galat hai"), null);
  assertEquals(saysOwnDetailWrong("meri jagah galat save hai"), "birth_place");
  assertEquals(saysOwnDetailWrong("mera birth time galat hai"), "birth_time");
  assertEquals(asksFor([astro({ ask_for: "birth_place" }), astro({ ask_for: "birth_place" })], "birth_place"), 2);
});

const PROMPT_BASE: ChatContextV5 = {
  chart: null,
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

Deno.test("the place is said back as a check, and a place not found is never called saved", () => {
  const captured = { field: "birth_place" as const, said: "Rampur, Uttar Pradesh", question: "Meri shaadi kab hogi?" };
  const said = flat(buildUserPromptV5("Rampur, UP", {
    ...PROMPT_BASE,
    captured,
    sawal: sawalFor(sawalContext({ place: true, placeAsks: 1, captured: "birth_place" })),
  }));
  assert(said.includes("THE DETAIL THEY JUST GAVE: their place of birth, found on the map as Rampur, Uttar Pradesh"));
  assert(said.includes("THE QUESTION TO ASK says the place back as the check"));
  // The check is the sawal, with the place in it, and nothing else is asked.
  assert(said.includes('the check on the place of birth just found — "Rampur, Uttar Pradesh — sahi hai na?"'));
  assert(said.includes("«Meri shaadi kab hogi?»"));
  // No kundli without the hour: the block does not claim one, and forbids saying there is one.
  assert(!said.includes("THEIR KUNDALI above"));
  assert(said.includes("never say the kundali is now complete, clearer or fully seen"));

  const lost = buildUserPromptV5("Xqzvbn", { ...PROMPT_BASE, captureFailed: "birth_place" });
  assert(lost.includes("THEY WERE ASKED FOR THEIR PLACE OF BIRTH and this reply could not be found on the map"));
  assert(lost.includes("never name a place for them"));
  assert(!lost.includes("THE DETAIL THEY JUST GAVE"));
});

Deno.test("the reply that saved a place stores it, so the next turn knows it was said back", () => {
  const body = v5Body(
    { kind: "answer", topic: "marriage", bubbles: ["a", "b"], offer: "none", options: [], askFor: "none" },
    { version: "v5", saved: { field: "birth_place", from: null, to: "Rampur, Uttar Pradesh, India" } },
  );
  assertEquals((body.saved as Record<string, unknown>).field, "birth_place");
});

Deno.test("THE KUNDALI LINE says sthan only for a place that is known", () => {
  // `astro-chat` passes the words only once the place is located.
  const chart = { precise: true, moonRashi: "Tula" } as never;
  assertEquals(kundaliLineFor(chart, { timing: null, transits: null, birthPlace: null, question: "x" })?.place, false);
  assertEquals(kundaliLineFor(chart, { timing: null, transits: null, birthPlace: "Rampur, Uttar Pradesh, India", question: "x" })?.place, true);
});
