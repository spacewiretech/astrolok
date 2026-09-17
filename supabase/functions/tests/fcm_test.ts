import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  ANDROID_CHANNEL_ID,
  buildFcmMessage,
  classifyFcmError,
  parseServiceAccount,
  signServiceAccountJwt,
} from "../_shared/fcm.ts";

async function generatedAccount() {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let binary = "";
  for (const b of pkcs8) binary += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(binary).match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----\n`;
  return { pair, json: JSON.stringify({ project_id: "astrolok-21088", client_email: "push@astrolok.iam.gserviceaccount.com", private_key: pem }) };
}

function base64UrlDecode(part: string): Uint8Array<ArrayBuffer> {
  const padded = part.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((part.length + 3) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

Deno.test("a service account JSON is read, and anything less is not one", async () => {
  const { json } = await generatedAccount();
  const account = parseServiceAccount(json)!;
  assertEquals(account.projectId, "astrolok-21088");
  assertEquals(account.clientEmail, "push@astrolok.iam.gserviceaccount.com");

  assertEquals(parseServiceAccount(""), null);
  assertEquals(parseServiceAccount("not json"), null);
  assertEquals(parseServiceAccount(JSON.stringify({ project_id: "x", client_email: "y" })), null);
});

Deno.test("the OAuth assertion is a real RS256 JWT for the messaging scope", async () => {
  const { pair, json } = await generatedAccount();
  const jwt = await signServiceAccountJwt(parseServiceAccount(json)!, 1_800_000_000);
  const [header, claims, signature] = jwt.split(".");

  assertEquals(JSON.parse(new TextDecoder().decode(base64UrlDecode(header))), { alg: "RS256", typ: "JWT" });
  const body = JSON.parse(new TextDecoder().decode(base64UrlDecode(claims)));
  assertEquals(body.iss, "push@astrolok.iam.gserviceaccount.com");
  assertEquals(body.scope, "https://www.googleapis.com/auth/firebase.messaging");
  assertEquals(body.aud, "https://oauth2.googleapis.com/token");
  assertEquals(body.exp - body.iat, 3600);

  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    pair.publicKey,
    base64UrlDecode(signature),
    new TextEncoder().encode(`${header}.${claims}`),
  );
  assert(valid);
});

Deno.test("a key pasted with escaped newlines still signs", async () => {
  const { json } = await generatedAccount();
  const escaped = JSON.parse(json);
  escaped.private_key = escaped.private_key.replace(/\n/g, "\\n");
  const jwt = await signServiceAccountJwt(parseServiceAccount(JSON.stringify(escaped))!, 1_800_000_000);
  assertEquals(jwt.split(".").length, 3);
});

Deno.test("the message carries string data, the app's channel, and a collapse key", () => {
  const message = buildFcmMessage({
    token: "tok",
    title: "✨ Your Kundali is ready",
    body: "Tap to reveal it.",
    data: { route: "/kundali", campaign: "kundali_ready", notification_id: "n1", params: "{}" },
    collapseKey: "kundali_ready",
  }) as any;

  assertEquals(message.message.token, "tok");
  assertEquals(message.message.notification.title, "✨ Your Kundali is ready");
  assert(Object.values(message.message.data).every((v) => typeof v === "string"));
  assertEquals(message.message.android.notification.channel_id, ANDROID_CHANNEL_ID);
  assertEquals(message.message.android.notification.tag, "kundali_ready");
  assertEquals(message.message.apns.headers["apns-collapse-id"], "kundali_ready");
});

Deno.test("send failures are classified into what to do next", () => {
  const fcmError = (status: number, errorCode: string, message = "") =>
    JSON.stringify({ error: { code: status, message, details: [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode }] } });

  assertEquals(classifyFcmError(404, fcmError(404, "UNREGISTERED")), "delete_token");
  assertEquals(classifyFcmError(403, fcmError(403, "SENDER_ID_MISMATCH")), "delete_token");
  assertEquals(classifyFcmError(400, fcmError(400, "INVALID_ARGUMENT", "The registration token is not a valid FCM registration token")), "delete_token");
  assertEquals(classifyFcmError(400, fcmError(400, "INVALID_ARGUMENT", "Invalid JSON payload")), "fail");
  assertEquals(classifyFcmError(429, fcmError(429, "QUOTA_EXCEEDED")), "retry");
  assertEquals(classifyFcmError(503, "<html>"), "retry");
  assertEquals(classifyFcmError(401, JSON.stringify({ error: { status: "UNAUTHENTICATED" } })), "reauth");
  assertEquals(classifyFcmError(401, fcmError(401, "THIRD_PARTY_AUTH_ERROR")), "fail");
});
