import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

import { configCached, primeConfig } from "./config.ts";

/**
 * Service-role client. Bypasses RLS, so it is the only thing that can read or write
 * `users`, `user_sessions` and `otp_throttle` — those tables have RLS on with no policies.
 *
 * SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected into every Edge Function by the
 * platform; they never need setting by hand.
 */
export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

/** Indian mobile, matching the CHECK on users.mobile_no and the app's own validation. */
export function isValidMobile(value: unknown): value is string {
  return typeof value === "string" && /^[6-9][0-9]{9}$/.test(value);
}

/**
 * Claims one send against the number's quota. Returns false when the cap is hit.
 *
 * The counting happens in a single SQL upsert so two concurrent requests cannot both slip
 * past the limit.
 */
export async function consumeOtpQuota(
  db: SupabaseClient,
  mobile: string,
): Promise<boolean> {
  const { data, error } = await db.rpc("consume_otp_quota", { p_mobile: mobile });
  if (error) {
    // Fail closed: if the quota cannot be checked, do not spend money on an SMS.
    console.error("consume_otp_quota failed", error);
    return false;
  }
  return data === true;
}

const encoder = new TextEncoder();

/**
 * Session tokens are stored hashed, so a leaked table dump cannot be replayed against the API.
 * SHA-256 is right here: the token is 256 bits of CSPRNG output, so there is nothing to brute
 * force and no need for a slow password hash.
 */
export async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(token));
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export function newSessionToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * How old `last_seen_at` may be before a request stamps it again.
 *
 * Every signed-in call to every function used to write it, which made `user_sessions` as busy with
 * writes as with reads — 15.8k of each an hour in the surge of 2026-09-25, queued in front of the
 * same few PostgREST connections the chat was waiting on. What reads it asks "away three days?"
 * (`dormant`) and "back since the first charge?" (`post_charge_no_return`), and ten minutes is
 * nothing to either.
 */
const LAST_SEEN_EVERY_MS = 10 * 60 * 1000;

/** Whether a session last stamped at [lastSeenAt] is due a fresh stamp. Unset or unreadable is. */
export function lastSeenDue(lastSeenAt: string | null | undefined, now: Date = new Date()): boolean {
  const at = lastSeenAt ? new Date(lastSeenAt).getTime() : NaN;
  return !Number.isFinite(at) || now.getTime() - at >= LAST_SEEN_EVERY_MS;
}

/**
 * Who is calling, and their `users` row when the session lookup brought it — every column but
 * `chart`. Read it through `callerUserRow` in `entitlement.ts`, which cuts it to `USER_COLUMNS`.
 */
export interface Caller {
  userId: string;
  user: Record<string, unknown> | null;
}

/** Resolves a `Authorization: Bearer <token>` header to a user id, or null. */
export async function userIdForBearer(
  db: SupabaseClient,
  authorization: string | null,
): Promise<string | null> {
  return (await resolveCaller(db, authorization, false))?.userId ?? null;
}

/** Like [userIdForBearer], but brings the caller's `users` row along in the same round trip. */
export function callerForBearer(
  db: SupabaseClient,
  authorization: string | null,
): Promise<Caller | null> {
  return resolveCaller(db, authorization, true);
}

/**
 * One `edge_caller` round trip for the session, its stamp, the `users` row and — on an instance
 * with none cached — `app_config`, which it hands to `loadConfig`. Those were up to four requests
 * in a row at the head of every signed-in call, and on 2026-09-28 they were about 20 of the 44 a
 * second behind the project's high-CPU warning.
 *
 * Falls back to the separate reads if the call fails, so a deploy that lands before its migration
 * (or a broken migration) costs requests rather than signing everyone out.
 */
async function resolveCaller(
  db: SupabaseClient,
  authorization: string | null,
  withUser: boolean,
): Promise<Caller | null> {
  const token = authorization?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;

  const tokenHash = await hashToken(token);
  const withConfig = !configCached();
  let answer: Record<string, unknown>;
  try {
    const { data, error } = await db.rpc("edge_caller", {
      p_token_hash: tokenHash,
      p_with_config: withConfig,
      p_with_user: withUser,
      p_stamp_every_seconds: LAST_SEEN_EVERY_MS / 1000,
    });
    if (error) throw error;
    if (!isRecord(data)) throw new Error("edge_caller returned no object");
    answer = data;
  } catch (error) {
    console.error("edge_caller failed; resolving the session with separate reads", error);
    const userId = await sessionUserId(db, tokenHash);
    return userId ? { userId, user: null } : null;
  }

  if (withConfig && Array.isArray(answer.config)) primeConfig(answer.config);
  if (typeof answer.user_id !== "string" || !answer.user_id) return null;
  return { userId: answer.user_id, user: isRecord(answer.user) ? answer.user : null };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** The session lookup as it was before `edge_caller`: a read, then a stamp when one is due. */
async function sessionUserId(db: SupabaseClient, tokenHash: string): Promise<string | null> {
  const { data, error } = await db
    .from("user_sessions")
    .select("user_id, expires_at, last_seen_at")
    .eq("token_hash", tokenHash)
    .maybeSingle();

  if (error || !data) return null;
  const now = new Date();
  if (new Date(data.expires_at as string) < now) return null;

  // Best-effort activity stamp; a failure here must not block the request.
  if (lastSeenDue(data.last_seen_at as string | null, now)) {
    db.from("user_sessions")
      .update({ last_seen_at: now.toISOString() })
      .eq("token_hash", tokenHash)
      .then(() => {});
  }

  return data.user_id as string;
}

/**
 * The first [limit] of rows read before [limit] was known, under a [cap] — or null when the cap
 * may have cut off rows the limit wants, and the read has to be made again with the limit itself.
 *
 * For a read that runs in the same round as the `app_config` that sizes it: the round is only one
 * round if nothing in it waits on another part of it.
 */
export function withinCap<T>(rows: T[], { limit, cap }: { limit: number; cap: number }): T[] | null {
  if (limit > cap && rows.length >= cap) return null;
  return rows.slice(0, limit);
}
