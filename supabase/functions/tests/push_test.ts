import { assertEquals } from "jsr:@std/assert@1";

import { MAX_PUSH_TOKEN_LENGTH, parsePushRegistration } from "../_shared/push.ts";

const TOKEN = "fGx1pQ:APA91bH-Zx_example_registration_token";

Deno.test("a well-formed registration is read back unchanged", () => {
  assertEquals(parsePushRegistration({ token: TOKEN, platform: "android" }), {
    token: TOKEN,
    platform: "android",
  });
  assertEquals(parsePushRegistration({ token: TOKEN, platform: "ios" })?.platform, "ios");
});

Deno.test("surrounding whitespace and platform case carry no meaning", () => {
  assertEquals(parsePushRegistration({ token: `  ${TOKEN}\n`, platform: " iOS " }), {
    token: TOKEN,
    platform: "ios",
  });
});

Deno.test("a blank token is not a registration", () => {
  assertEquals(parsePushRegistration({ token: "", platform: "android" }), null);
  assertEquals(parsePushRegistration({ token: "   ", platform: "android" }), null);
});

Deno.test("a token with whitespace inside it is refused", () => {
  // Two tokens pasted together, or a line wrap. Stored, it is a row no push can reach.
  assertEquals(parsePushRegistration({ token: `${TOKEN} ${TOKEN}`, platform: "android" }), null);
});

Deno.test("the length bound matches the table's CHECK", () => {
  const atBound = "a".repeat(MAX_PUSH_TOKEN_LENGTH);
  assertEquals(parsePushRegistration({ token: atBound, platform: "ios" })?.token, atBound);
  assertEquals(parsePushRegistration({ token: atBound + "a", platform: "ios" }), null);
});

Deno.test("only the two shipping platforms are accepted", () => {
  for (const platform of ["web", "macos", "windows", "linux", "", "androidx"]) {
    assertEquals(parsePushRegistration({ token: TOKEN, platform }), null, platform);
  }
});

Deno.test("anything that is not an object carrying two strings is refused", () => {
  assertEquals(parsePushRegistration(null), null);
  assertEquals(parsePushRegistration(undefined), null);
  assertEquals(parsePushRegistration(TOKEN), null);
  assertEquals(parsePushRegistration([TOKEN, "ios"]), null);
  assertEquals(parsePushRegistration({ token: TOKEN }), null);
  assertEquals(parsePushRegistration({ platform: "ios" }), null);
  assertEquals(parsePushRegistration({ token: 12345, platform: "ios" }), null);
  assertEquals(parsePushRegistration({ token: TOKEN, platform: 1 }), null);
});
