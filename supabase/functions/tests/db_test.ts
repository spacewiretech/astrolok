import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";

import { lastSeenDue, userIdForBearer, withinCap } from "../_shared/db.ts";

/**
 * Two rules that exist to take load off PostgREST: the session stamp that every signed-in call to
 * every function used to write, and the reads `astro-chat` makes before `app_config` has said how
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

/** Just enough of the client for `userIdForBearer`: one session lookup, and the stamps it writes. */
function sessions(row: Record<string, unknown> | null) {
  const selected: string[] = [];
  const stamps: Array<Record<string, unknown>> = [];
  const db = {
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
