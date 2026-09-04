import { loadConfig } from "../_shared/config.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer } from "../_shared/db.ts";

/**
 * The conversation so far, and what Astro remembers.
 *
 * Two jobs that would otherwise be two functions. They are together because they answer the same
 * question from two screens — the chat wants the transcript, Profile wants the facts — and
 * splitting them would mean two deploys, two quota-free endpoints to keep in step, and two places
 * to get the session check right.
 *
 * Reads only, plus the one destructive thing a user is entitled to do to their own memory:
 * forget it. No model is called here, so there is no quota and nothing to meter.
 */

/** Enough to scroll back through a long conversation without paging. */
const MAX_MESSAGES = 200;

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  const db = serviceClient();

  const userId = await userIdForBearer(db, req.headers.get("Authorization"));
  if (!userId) {
    return fail("unauthorized", "Please sign in again.", 401);
  }

  // A body is optional here: the common case is "give me everything".
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    // No body, or not JSON. Both mean a plain read.
  }

  // ------------------------------------------------------------ forgetting
  //
  // Deleting is the whole reason Profile can show this list honestly. A memory the user can see
  // but not remove would be worse than one they never knew about.
  const forget = typeof body.forget === "string" ? body.forget.trim() : "";
  if (forget) {
    const query = db.from("user_facts").delete().eq("user_id", userId);

    // "*" is forget-everything. Anything else is one key, matched exactly — never a pattern, so
    // a stray character cannot widen a single deletion into all of them.
    const { error } = forget === "*" ? await query : await query.eq("key", forget);

    if (error) {
      console.error("chat-history: could not forget", error);
      return fail("server_error", "Could not update what Astro remembers.", 500);
    }
  }

  const config = await loadConfig(db);
  const perDay = Number(config.get("chat_messages_per_day") ?? "40");
  const limit = Number.isFinite(perDay) && perDay > 0 ? perDay : 40;
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const [{ data: rows, error: messagesError }, { data: facts }, { count }] = await Promise
    .all([
      db.from("chat_messages")
        .select("id, role, body, created_at")
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(MAX_MESSAGES),
      db.from("user_facts")
        .select("key, value, updated_at")
        .eq("user_id", userId)
        .order("updated_at", { ascending: false }),
      db.from("chat_messages")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .eq("role", "user")
        .gte("created_at", since),
    ]);

  if (messagesError) {
    console.error("chat-history: could not read the conversation", messagesError);
    return fail("server_error", "Could not load your conversation.", 500);
  }

  // Newest-first from the index, oldest-first for a transcript that reads top to bottom.
  const messages = (rows ?? []).slice().reverse().map((row) => ({
    id: row.id,
    role: row.role,
    created_at: row.created_at,
    ...(row.body as Record<string, unknown>),
  }));

  return json({
    messages,
    facts: facts ?? [],
    remaining: Math.max(0, limit - (count ?? 0)),
  });
});
