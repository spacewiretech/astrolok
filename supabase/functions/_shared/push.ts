/**
 * Push-token registration: the pure half of `push-token`, kept out of the handler so it can be
 * tested without a database.
 */

export type PushPlatform = "android" | "ios";

export interface PushRegistration {
  token: string;
  platform: PushPlatform;
}

/**
 * Matches the CHECK on `push_tokens.token`. FCM tokens are around 160 characters today; the bound
 * is generous so a format change upstream is not an outage.
 */
export const MAX_PUSH_TOKEN_LENGTH = 4096;

const PLATFORMS: ReadonlySet<string> = new Set(["android", "ios"]);

/**
 * Reads a registration out of an untrusted request body, or null if it is not one.
 *
 * Everything the table would refuse is refused here first, so a malformed request is a 400 the app
 * can act on rather than a 500 from a failed insert.
 */
export function parsePushRegistration(body: unknown): PushRegistration | null {
  if (typeof body !== "object" || body === null || Array.isArray(body)) return null;
  const { token, platform } = body as Record<string, unknown>;

  if (typeof token !== "string" || typeof platform !== "string") return null;

  const trimmed = token.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_PUSH_TOKEN_LENGTH) return null;

  // A real token has no whitespace in it. One that does is a paste or a concatenation bug, and
  // storing it would only produce a row no push can ever be delivered to.
  if (/\s/.test(trimmed)) return null;

  const normalised = platform.trim().toLowerCase();
  if (!PLATFORMS.has(normalised)) return null;

  return { token: trimmed, platform: normalised as PushPlatform };
}
