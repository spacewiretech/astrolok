/**
 * Push-token registration: the pure half of `push-token`, kept out of the handler so it can be
 * tested without a database.
 */

export type PushPlatform = "android" | "ios";

export interface PushRegistration {
  token: string;
  platform: PushPlatform;
  /**
   * The app build that registered. Absent from builds older than the notification sender, which
   * cannot route a push; the sender only targets builds at or above `notif_min_app_build`.
   */
  appBuild?: number;
  /**
   * Whether the OS will actually show a notification. Android issues a token either way, so without
   * this a token is not evidence that anyone will see anything.
   */
  notificationsAuthorized?: boolean;
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
  const { token, platform, app_build, notifications_authorized } = body as Record<string, unknown>;

  if (typeof token !== "string" || typeof platform !== "string") return null;

  const trimmed = token.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_PUSH_TOKEN_LENGTH) return null;

  // A real token has no whitespace in it. One that does is a paste or a concatenation bug, and
  // storing it would only produce a row no push can ever be delivered to.
  if (/\s/.test(trimmed)) return null;

  const normalised = platform.trim().toLowerCase();
  if (!PLATFORMS.has(normalised)) return null;

  const registration: PushRegistration = { token: trimmed, platform: normalised as PushPlatform };

  // Both optional, and only kept when well-formed: an old build sends neither, and a malformed value
  // must not cost the device its registration.
  if (typeof app_build === "number" && Number.isInteger(app_build) && app_build >= 0 && app_build < 1_000_000_000) {
    registration.appBuild = app_build;
  }
  if (typeof notifications_authorized === "boolean") {
    registration.notificationsAuthorized = notifications_authorized;
  }

  return registration;
}
