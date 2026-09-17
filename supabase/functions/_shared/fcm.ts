/**
 * Firebase Cloud Messaging, HTTP v1, authenticated as a service account.
 *
 * The credential is the service-account JSON for project `astrolok-21088`, pasted into the private
 * `app_config` row `fcm_service_account_key` (the `_key` suffix is what keeps the secrets CHECK from
 * ever letting it be marked public). No Firebase SDK: the function signs its own OAuth assertion
 * with WebCrypto and posts JSON, which keeps the bundle small and the behaviour visible.
 *
 * The parsers, the message shape and the error classification are pure and tested in
 * `tests/fcm_test.ts`, including a real RS256 signature against a generated key.
 */

import { AppConfig, configSetting } from "./config.ts";

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TIMEOUT_MS = 8_000;

/** Android channel created by the app's `MainActivity`; a push naming any other lands in "Miscellaneous". */
export const ANDROID_CHANNEL_ID = "astrolok_default";

export interface ServiceAccount {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

export function parseServiceAccount(raw: string): ServiceAccount | null {
  if (!raw.trim()) return null;
  try {
    const json = JSON.parse(raw) as Record<string, unknown>;
    const projectId = String(json.project_id ?? "").trim();
    const clientEmail = String(json.client_email ?? "").trim();
    const privateKey = String(json.private_key ?? "");
    if (!projectId || !clientEmail || !privateKey.includes("PRIVATE KEY")) return null;
    return { projectId, clientEmail, privateKey };
  } catch {
    return null;
  }
}

export function serviceAccountFrom(config: AppConfig): ServiceAccount | null {
  return parseServiceAccount(configSetting(config, "fcm_service_account_key"));
}

// ---------------------------------------------------------------- the OAuth assertion

const encoder = new TextEncoder();

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): ArrayBuffer {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

/** The signed JWT exchanged for an access token. One hour, Google's maximum. */
export async function signServiceAccountJwt(account: ServiceAccount, nowSeconds: number): Promise<string> {
  const header = base64Url(encoder.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = base64Url(encoder.encode(JSON.stringify({
    iss: account.clientEmail,
    scope: SCOPE,
    aud: TOKEN_URL,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  })));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(account.privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(`${header}.${claims}`));
  return `${header}.${claims}.${base64Url(new Uint8Array(signature))}`;
}

/** Cached per isolate, keyed by the account, and refreshed five minutes before it expires. */
let cached: { email: string; token: string; expiresAt: number } | null = null;

export async function fcmAccessToken(account: ServiceAccount, { force = false } = {}): Promise<string> {
  const now = Date.now();
  if (!force && cached && cached.email === account.clientEmail && cached.expiresAt - 300_000 > now) {
    return cached.token;
  }

  const assertion = await signServiceAccountJwt(account, Math.floor(now / 1000));
  const response = await fetchWithTimeout(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  const raw = await response.text();
  if (!response.ok) throw new Error(`fcm oauth ${response.status}: ${raw.slice(0, 300)}`);

  const parsed = JSON.parse(raw) as { access_token?: string; expires_in?: number };
  if (!parsed.access_token) throw new Error("fcm oauth answered without a token");
  cached = {
    email: account.clientEmail,
    token: parsed.access_token,
    expiresAt: now + (parsed.expires_in ?? 3600) * 1000,
  };
  return cached.token;
}

// ---------------------------------------------------------------- the message

export interface PushMessage {
  token: string;
  title: string;
  body: string;
  /** The app's routing contract: `route`, `campaign`, `notification_id`, `params` (JSON text). */
  data: Record<string, string>;
  /** Collapses repeats of the same campaign on the device rather than stacking them. */
  collapseKey: string;
}

export function buildFcmMessage(message: PushMessage): Record<string, unknown> {
  return {
    message: {
      token: message.token,
      notification: { title: message.title, body: message.body },
      // FCM rejects any non-string data value.
      data: Object.fromEntries(Object.entries(message.data).map(([k, v]) => [k, String(v)])),
      android: {
        priority: "HIGH",
        notification: {
          channel_id: ANDROID_CHANNEL_ID,
          icon: "ic_notification",
          color: "#F4B835",
          tag: message.collapseKey,
        },
      },
      apns: {
        headers: { "apns-priority": "10", "apns-collapse-id": message.collapseKey },
        payload: { aps: { sound: "default", "thread-id": message.collapseKey } },
      },
    },
  };
}

export type FcmFailure = "delete_token" | "retry" | "reauth" | "fail";

/**
 * What to do about a failed send.
 *
 *  - `delete_token`: the install is gone or the token belongs to another sender. Keeping it would
 *    only make every future campaign fail the same way.
 *  - `retry`: quota or an outage on Google's side.
 *  - `reauth`: our access token expired between the cache check and the send.
 *  - `fail`: everything else — a malformed message, an APNs credential problem — for a human.
 */
export function classifyFcmError(status: number, body: string): FcmFailure {
  let code = "";
  let message = "";
  try {
    const error = (JSON.parse(body) as { error?: Record<string, unknown> })?.error ?? {};
    message = String(error.message ?? "");
    const details = Array.isArray(error.details) ? error.details as Array<Record<string, unknown>> : [];
    code = String(details.find((d) => typeof d.errorCode === "string")?.errorCode ?? error.status ?? "");
  } catch {
    // Not JSON; the status decides.
  }

  if (code === "UNREGISTERED" || code === "SENDER_ID_MISMATCH" || status === 404) return "delete_token";
  if (status === 400 && /registration token/i.test(message)) return "delete_token";
  if (status === 401 && code !== "THIRD_PARTY_AUTH_ERROR") return "reauth";
  if (status === 429 || status >= 500 || code === "QUOTA_EXCEEDED" || code === "UNAVAILABLE" || code === "INTERNAL") {
    return "retry";
  }
  return "fail";
}

export type SendResult = { ok: true; name: string } | { ok: false; action: FcmFailure; detail: string };

export async function sendFcm(account: ServiceAccount, accessToken: string, message: PushMessage): Promise<SendResult> {
  let response: Response;
  try {
    response = await fetchWithTimeout(`https://fcm.googleapis.com/v1/projects/${account.projectId}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify(buildFcmMessage(message)),
    });
  } catch (error) {
    return { ok: false, action: "retry", detail: `fetch failed: ${error}` };
  }

  const raw = await response.text().catch(() => "");
  if (response.ok) {
    try {
      return { ok: true, name: String((JSON.parse(raw) as { name?: string }).name ?? "") };
    } catch {
      return { ok: true, name: "" };
    }
  }
  return { ok: false, action: classifyFcmError(response.status, raw), detail: `${response.status}: ${raw.slice(0, 300)}` };
}

async function fetchWithTimeout(url: string, init: RequestInit): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}
