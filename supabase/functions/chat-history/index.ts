import { promptVersion } from "../_shared/astro_chat.ts";
import { normaliseFeedbackComment } from "../_shared/chat_feedback.ts";
import { resolveLanguage } from "../_shared/chat_language.ts";
import { configSetting, loadConfig } from "../_shared/config.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer } from "../_shared/db.ts";

/**
 * Everything the chat screen and Profile need that does not cost a model call.
 *
 * Five jobs that would otherwise be five functions: the sidebar wants the list of conversations,
 * the transcript wants one of them, Profile wants the facts, both screens want to be able to
 * remove something, and the chat wants somewhere to put a rating. They are together because they
 * answer the same question from two screens, and splitting them would mean five deploys, five
 * quota-free endpoints to keep in step, and five places to get the session check right.
 *
 * No model is called here, so there is no quota and nothing to meter. The user id always comes
 * from the session token, and every query is scoped to it — a thread id in the body is a request,
 * never an authorisation.
 */

/** Enough to scroll back through a long conversation without paging. */
const MAX_MESSAGES = 200;

/** More conversations than anyone will scroll, and a bound on the sidebar's payload. */
const MAX_THREADS = 100;

/** Matches the column's own check constraint. */
const MAX_TITLE_CHARS = 80;

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  const db = serviceClient();

  const userId = await userIdForBearer(db, req.headers.get("Authorization"));
  if (!userId) {
    return fail("unauthorized", "Please sign in again.", 401);
  }

  // A body is optional here: the common case is "give me the sidebar".
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    // No body, or not JSON. Both mean a plain read.
  }

  // ------------------------------------------------------------ rating the chat
  //
  // Answered once per account: `chat_feedback` is keyed on the user, and a second answer is
  // ignored rather than refused, so a retried request never becomes an error on someone's screen.
  // Everything recorded beside the score is resolved here, never taken from the request — the row
  // exists to line a rating up against what actually produced the conversation.
  const rate = (body.rate ?? null) as Record<string, unknown> | null;
  if (rate && typeof rate === "object") {
    const threadId = typeof rate.thread_id === "string" ? rate.thread_id.trim() : "";
    const raw = rate.rating;
    // Null is a dismissal, and is recorded: otherwise the card would return on every reply to
    // someone who has already said "not now".
    const rating = raw === null
      ? null
      : typeof raw === "number" && Number.isInteger(raw) && raw >= 1 && raw <= 5
      ? raw
      : undefined;

    if (!threadId || rating === undefined) {
      return fail("invalid_request", "That rating could not be read.", 400);
    }

    const config = await loadConfig(db);

    const [{ data: thread }, { data: user }] = await Promise.all([
      // Scoped to the user, so another account's thread id records no conversation at all.
      db.from("chat_threads")
        .select("id")
        .eq("id", threadId)
        .eq("user_id", userId)
        .maybeSingle(),
      db.from("users").select("language").eq("user_id", userId).maybeSingle(),
    ]);

    const ownThread = thread ? (thread.id as string) : null;
    let turnCount: number | null = null;
    let model: string | null = null;

    if (ownThread) {
      const [{ count }, { data: latest }] = await Promise.all([
        db.from("chat_messages")
          .select("id", { count: "exact", head: true })
          .eq("thread_id", ownThread)
          .eq("role", "user"),
        db.from("chat_messages")
          .select("model")
          .eq("thread_id", ownThread)
          .eq("role", "astro")
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle(),
      ]);

      turnCount = count ?? null;
      model = typeof latest?.model === "string" ? latest.model : null;
    }

    const { error } = await db
      .from("chat_feedback")
      .upsert(
        {
          user_id: userId,
          thread_id: ownThread,
          rating,
          turn_count: turnCount,
          language: resolveLanguage(
            typeof user?.language === "string" ? user.language : null,
            config,
          ),
          prompt_version: promptVersion(configSetting(config, "chat_prompt_version")),
          model,
          // What they wrote beside the score, tidied and capped. A dismissal says nothing, whatever
          // arrives with it, and an unreadable comment costs the comment, never the rating.
          comment: rating === null ? null : normaliseFeedbackComment(rate.comment),
        },
        { onConflict: "user_id", ignoreDuplicates: true },
      );

    if (error) {
      console.error("chat-history: could not save the rating", error);
      return fail("server_error", "Could not save your rating.", 500);
    }

    return json({ rated: true });
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

  // ------------------------------------------------------------ renaming
  const rename = (body.rename ?? null) as Record<string, unknown> | null;
  if (rename && typeof rename === "object") {
    const id = typeof rename.thread_id === "string" ? rename.thread_id.trim() : "";
    const title = typeof rename.title === "string"
      ? rename.title.trim().replace(/\s+/g, " ").slice(0, MAX_TITLE_CHARS)
      : "";

    if (!id || !title) {
      return fail("invalid_request", "Give the conversation a name.", 400);
    }

    // Scoped to the user, so an id from another account matches no row and changes nothing.
    const { error } = await db
      .from("chat_threads")
      .update({ title })
      .eq("id", id)
      .eq("user_id", userId)
      .is("deleted_at", null);

    if (error) {
      console.error("chat-history: could not rename the thread", error);
      return fail("server_error", "Could not rename that conversation.", 500);
    }
  }

  // ------------------------------------------------------------ deleting a thread
  //
  // Marked, not removed. The daily allowance counts the user turns of the last 24 hours, so
  // deleting the rows would refund the questions they cost and make the limit advisory. The user
  // sees it gone, which is what they asked for; the count stays honest.
  const remove = typeof body.delete_thread === "string" ? body.delete_thread.trim() : "";
  if (remove) {
    const { error } = await db
      .from("chat_threads")
      .update({ deleted_at: new Date().toISOString() })
      .eq("id", remove)
      .eq("user_id", userId)
      .is("deleted_at", null);

    if (error) {
      console.error("chat-history: could not delete the thread", error);
      return fail("server_error", "Could not delete that conversation.", 500);
    }
  }

  // ------------------------------------------------------------ what is left today
  const config = await loadConfig(db);
  const perDay = Number(config.get("chat_messages_per_day") ?? "40");
  const limit = Number.isFinite(perDay) && perDay > 0 ? perDay : 40;
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const [{ data: facts }, { count }] = await Promise.all([
    db.from("user_facts")
      .select("key, value, updated_at")
      .eq("user_id", userId)
      .order("updated_at", { ascending: false }),
    // Still per user, not per thread: the allowance belongs to the account.
    db.from("chat_messages")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("role", "user")
      .gte("created_at", since),
  ]);

  const common = {
    facts: facts ?? [],
    remaining: Math.max(0, limit - (count ?? 0)),
  };

  // ------------------------------------------------------------ one conversation
  const threadId = typeof body.thread_id === "string" ? body.thread_id.trim() : "";
  if (threadId) {
    // Read through the thread rather than filtering messages by `user_id`, so an id belonging to
    // someone else returns "no such conversation" rather than an empty transcript that looks like
    // a bug.
    const { data: thread } = await db
      .from("chat_threads")
      .select("id, title, last_message_at")
      .eq("id", threadId)
      .eq("user_id", userId)
      .is("deleted_at", null)
      .maybeSingle();

    if (!thread) {
      return fail("not_found", "That conversation is no longer here.", 404);
    }

    const { data: rows, error: messagesError } = await db
      .from("chat_messages")
      .select("id, role, body, created_at")
      .eq("thread_id", threadId)
      .order("created_at", { ascending: false })
      .limit(MAX_MESSAGES);

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

    return json({ ...common, thread, messages });
  }

  // ------------------------------------------------------------ the sidebar
  //
  // One table, no join. `preview` is denormalised onto the thread by `astro-chat` for exactly
  // this read — see the column comment in the threads migration for why the obvious version of
  // this query cannot be written against Postgrest.
  const { data: threads, error: threadsError } = await db
    .from("chat_threads")
    .select("id, title, preview, last_message_at")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .order("last_message_at", { ascending: false })
    .limit(MAX_THREADS);

  if (threadsError) {
    console.error("chat-history: could not list the conversations", threadsError);
    return fail("server_error", "Could not load your conversations.", 500);
  }

  return json({ ...common, threads: threads ?? [] });
});
