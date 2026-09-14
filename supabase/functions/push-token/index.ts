import { fail, json, preflight } from "../_shared/cors.ts";
import { hashToken, serviceClient, userIdForBearer } from "../_shared/db.ts";
import { parsePushRegistration } from "../_shared/push.ts";

/**
 * Registers this device's FCM token against the caller's account and session.
 *
 * Idempotent: the token is the primary key, so the app can call this on every launch and every
 * token refresh and the table still holds one row per device. When a different account signs in
 * on the same phone the row moves to it, rather than leaving the device notifiable by the account
 * that signed out.
 *
 * The session binding is what makes sign-out work without a second call: `me` DELETE drops the
 * session row, and the foreign key's cascade drops this one. See
 * `20260914000001_push_tokens.sql`.
 */
Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  const db = serviceClient();
  const authorization = req.headers.get("Authorization");
  const userId = await userIdForBearer(db, authorization);
  if (!userId) return fail("unauthorized", "Please sign in again.", 401);

  let body: unknown = null;
  try {
    body = await req.json();
  } catch {
    // Left null: the parse below rejects a missing body exactly as it rejects a malformed one.
  }

  const registration = parsePushRegistration(body);
  if (!registration) {
    return fail("invalid_request", "That is not a push registration.", 400);
  }

  // `userIdForBearer` has already proved this bearer names a live session, so its hash is safe to
  // bind to — and the foreign key would refuse the row if it were not.
  const bearer = authorization!.replace(/^Bearer\s+/i, "").trim();

  const { error } = await db.from("push_tokens").upsert(
    {
      token: registration.token,
      user_id: userId,
      session_token_hash: await hashToken(bearer),
      platform: registration.platform,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "token" },
  );

  if (error) {
    console.error("push token upsert failed", error);
    return fail("server_error", "Could not register for notifications.", 500);
  }

  return json({ ok: true });
});
