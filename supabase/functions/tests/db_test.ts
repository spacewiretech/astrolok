import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";

import { configCached, loadConfig, primeConfig } from "../_shared/config.ts";
import { callerForBearer, hashToken, lastSeenDue, userIdForBearer, withinCap } from "../_shared/db.ts";
import { callerUserRow, USER_COLUMNS, userColumnsOf } from "../_shared/entitlement.ts";

/**
 * Rules that exist to take load off PostgREST: the session stamp that every signed-in call to
 * every function used to write, the one `edge_caller` round trip that replaced the requests at the
 * head of every signed-in call, and the reads `astro-chat` makes before `app_config` has said how
 * many rows it wants.
 */

const now = new Date("2026-09-25T10:00:00Z");
const minutesAgo = (minutes: number) => new Date(now.getTime() - minutes * 60_000).toISOString();

Deno.test("a session is due a stamp when never stamped, unreadable, or ten minutes stale", () => {
  assert(lastSeenDue(null, now));
  assert(lastSeenDue(undefined, now));
  assert(lastSeenDue("", now));
  assert(lastSeenDue("not a date", now));
  assert(lastSeenDue(minutesAgo(10), now));
  assert(lastSeenDue(minutesAgo(60 * 24 * 3), now));

  assertFalse(lastSeenDue(minutesAgo(0), now));
  assertFalse(lastSeenDue(minutesAgo(9.99), now));
  // A clock ahead of ours is not a reason to write on every call.
  assertFalse(lastSeenDue(new Date(now.getTime() + 60_000).toISOString(), now));
});

/**
 * Just enough of the client for the session lookup `edge_caller` replaced, which is still what runs
 * when `edge_caller` fails: one read, and the stamps it writes.
 */
function sessions(row: Record<string, unknown> | null) {
  const selected: string[] = [];
  const stamps: Array<Record<string, unknown>> = [];
  const db = {
    rpc: () => Promise.resolve({ data: null, error: { message: "function public.edge_caller does not exist" } }),
    from: (_table: string) => ({
      select: (columns: string) => {
        selected.push(columns);
        return { eq: () => ({ maybeSingle: () => Promise.resolve({ data: row, error: null }) }) };
      },
      update: (values: Record<string, unknown>) => ({
        eq: () => {
          stamps.push(values);
          return Promise.resolve({ error: null });
        },
      }),
    }),
  } as unknown as SupabaseClient;
  return { db, selected, stamps };
}

const future = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();

Deno.test("a session seen in the last ten minutes resolves without a write", async () => {
  const { db, selected, stamps } = sessions({
    user_id: "u1",
    expires_at: future,
    last_seen_at: new Date(Date.now() - 2 * 60_000).toISOString(),
  });

  assertEquals(await userIdForBearer(db, "Bearer abc"), "u1");
  assertEquals(stamps.length, 0);
  // The staleness is read with the lookup, not with a second query.
  assertEquals(selected, ["user_id, expires_at, last_seen_at"]);
});

Deno.test("a stale or never-stamped session is stamped once", async () => {
  for (const lastSeen of [new Date(Date.now() - 11 * 60_000).toISOString(), null]) {
    const { db, stamps } = sessions({ user_id: "u1", expires_at: future, last_seen_at: lastSeen });

    assertEquals(await userIdForBearer(db, "Bearer abc"), "u1");
    assertEquals(stamps.length, 1, `last seen ${lastSeen}`);
    assert(typeof stamps[0].last_seen_at === "string");
  }
});

Deno.test("an expired, unknown or missing session resolves to nobody and is never stamped", async () => {
  const expired = sessions({
    user_id: "u1",
    expires_at: new Date(Date.now() - 1000).toISOString(),
    last_seen_at: null,
  });
  assertEquals(await userIdForBearer(expired.db, "Bearer abc"), null);
  assertEquals(expired.stamps.length, 0);

  const unknown = sessions(null);
  assertEquals(await userIdForBearer(unknown.db, "Bearer abc"), null);
  assertEquals(unknown.stamps.length, 0);

  const missing = sessions({ user_id: "u1", expires_at: future, last_seen_at: null });
  assertEquals(await userIdForBearer(missing.db, null), null);
  assertEquals(await userIdForBearer(missing.db, "Bearer   "), null);
  assertEquals(missing.selected.length, 0);
});

const rows = (n: number) => Array.from({ length: n }, (_, i) => i);

Deno.test("a capped read is cut to the limit it was read ahead of", () => {
  // Today's config: a window of 20 turns, read under a cap of 40.
  assertEquals(withinCap(rows(40), { limit: 20, cap: 40 }), rows(20));
  assertEquals(withinCap(rows(33), { limit: 20, cap: 40 }), rows(20));
  // A thread shorter than the window is all of it.
  assertEquals(withinCap(rows(7), { limit: 20, cap: 40 }), rows(7));
  assertEquals(withinCap([], { limit: 20, cap: 40 }), []);
  // At the cap exactly, nothing the limit wants was cut off.
  assertEquals(withinCap(rows(40), { limit: 40, cap: 40 }), rows(40));
});

Deno.test("a limit past the cap is read again only when the cap may have cut it short", () => {
  // Everything there is came back under the cap, so a larger limit has nothing more to find.
  assertEquals(withinCap(rows(39), { limit: 60, cap: 40 }), rows(39));
  // The cap was reached: rows 40..59 may exist, and the caller reads again at 60.
  assertEquals(withinCap(rows(40), { limit: 60, cap: 40 }), null);
});

/** Every column `USER_COLUMNS` names, plus the `chart`-less extras `to_jsonb(users)` also carries. */
const userRow: Record<string, unknown> = {
  ...Object.fromEntries(USER_COLUMNS.split(",").map((column) => [column.trim(), null])),
  user_id: "u1",
  mobile_no: "9876543210",
  payment_type: "trial",
  trial_ends_at: future,
  total_paid_amount: 3,
  updated_at: "2026-09-28T06:00:00+00:00",
};

/** A client that answers `edge_caller` with [answer] and fails the test on any other request. */
function edgeCaller(answer: Record<string, unknown> | null) {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const db = {
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      return Promise.resolve({ data: answer, error: null });
    },
    from: (table: string) => {
      throw new Error(`unexpected request to ${table}`);
    },
  } as unknown as SupabaseClient;
  return { db, calls };
}

Deno.test("the session, its stamp and the user row are one round trip", async () => {
  const { db, calls } = edgeCaller({ user_id: "u1", user: userRow, config: null });
  const wantedConfig = !configCached();

  const caller = await callerForBearer(db, "Bearer abc");

  assertEquals(caller, { userId: "u1", user: userRow });
  assertEquals(calls, [{
    name: "edge_caller",
    args: {
      p_token_hash: await hashToken("abc"),
      p_with_config: wantedConfig,
      p_with_user: true,
      p_stamp_every_seconds: 600,
    },
  }]);
});

Deno.test("config brought by the session lookup answers the loadConfig after it", async () => {
  primeConfig([{ key: " chat_prompt_version ", value: " v5\n" }]);
  assert(configCached());

  const { db, calls } = edgeCaller({ user_id: "u1", user: null, config: [{ key: "ignored", value: "x" }] });
  await userIdForBearer(db, "Bearer abc");
  // Cached inside its minute, so config is not asked for, and one that came anyway is not taken.
  assertEquals(calls[0].args.p_with_config, false);

  const config = await loadConfig(db);
  assertEquals(config.get("chat_prompt_version"), "v5");
  assertFalse(config.has("ignored"));
});

Deno.test("only a caller who needs the user row asks for it", async () => {
  const { db, calls } = edgeCaller({ user_id: "u1", user: null, config: null });

  assertEquals(await userIdForBearer(db, "Bearer abc"), "u1");
  assertEquals(calls[0].args.p_with_user, false);
});

Deno.test("edge_caller's nobody is nobody, and a missing token asks nothing", async () => {
  const { db, calls } = edgeCaller({ user_id: null, user: null, config: null });

  assertEquals(await callerForBearer(db, "Bearer abc"), null);
  assertEquals(await callerForBearer(db, null), null);
  assertEquals(await callerForBearer(db, "Bearer   "), null);
  assertEquals(calls.length, 1);
});

Deno.test("a failing edge_caller falls back to the separate reads", async () => {
  const { db, selected } = sessions({ user_id: "u1", expires_at: future, last_seen_at: null });

  assertEquals(await callerForBearer(db, "Bearer abc"), { userId: "u1", user: null });
  assertEquals(selected, ["user_id, expires_at, last_seen_at"]);
});

Deno.test("a row is cut to exactly USER_COLUMNS, and one missing a column is no row", () => {
  const cut = userColumnsOf(userRow) as unknown as Record<string, unknown>;
  assertEquals(Object.keys(cut).sort(), USER_COLUMNS.split(",").map((column) => column.trim()).sort());
  assertEquals(cut.trial_ends_at, future);
  assertFalse("total_paid_amount" in cut);

  const { trial_ends_at: _dropped, ...withoutTrial } = userRow;
  assertEquals(userColumnsOf(withoutTrial), null);
  assertEquals(userColumnsOf(null), null);
});

Deno.test("the caller's row is read only when the session lookup did not bring a whole one", async () => {
  const reads: string[] = [];
  const db = {
    from: (table: string) => ({
      select: (columns: string) => ({
        eq: () => ({
          maybeSingle: () => {
            reads.push(`${table}: ${columns}`);
            return Promise.resolve({ data: { ...userRow, name: "read" }, error: null });
          },
        }),
      }),
    }),
  } as unknown as SupabaseClient;

  assertEquals((await callerUserRow(db, { userId: "u1", user: userRow }, "test"))?.mobile_no, "9876543210");
  assertEquals(reads.length, 0);

  assertEquals((await callerUserRow(db, { userId: "u1", user: null }, "test"))?.name, "read");
  const { plan_variant: _dropped, ...incomplete } = userRow;
  assertEquals((await callerUserRow(db, { userId: "u1", user: incomplete }, "test"))?.name, "read");
  assertEquals(reads, [`users: ${USER_COLUMNS}`, `users: ${USER_COLUMNS}`]);
});
