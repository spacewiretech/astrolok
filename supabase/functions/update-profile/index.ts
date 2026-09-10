import { isSupported, supportedLanguages } from "../_shared/chat_language.ts";
import { loadConfig } from "../_shared/config.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer } from "../_shared/db.ts";
import {
  asUserRow,
  entitlementPayload,
  graceHoursFrom,
  USER_COLUMNS,
} from "../_shared/entitlement.ts";

/**
 * Sets the name and the date of birth collected in the steps after OTP.
 *
 * Both fields are optional and each is sent by its own screen, so the update is built from
 * whichever keys are present. A request carrying neither is rejected rather than silently
 * doing nothing.
 *
 * The user id comes from the session token, never from the request body — otherwise anyone
 * could rewrite any account by guessing a uuid.
 */

/** `YYYY-MM-DD`, the only form the client sends and the shape a Postgres `date` accepts. */
const DOB_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

/**
 * True only for a date that exists and has already happened.
 *
 * The round-trip through `toISOString` is what rejects 2023-02-31: `new Date` rolls it forward
 * to 3 March, which then no longer matches the input. A plain parse would accept it and store
 * the wrong birthday.
 */
function isRealPastDate(value: string): boolean {
  if (!DOB_PATTERN.test(value)) return false;

  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime())) return false;
  if (parsed.toISOString().slice(0, 10) !== value) return false;

  // Compared in UTC against today's date, matching the column's `<= current_date` CHECK.
  const today = new Date().toISOString().slice(0, 10);
  if (value > today) return false;

  // Mirrors the lower bound on the column, so a typo fails here with a readable message
  // instead of as a constraint violation.
  return value >= "1900-01-01";
}

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  const db = serviceClient();
  const userId = await userIdForBearer(db, req.headers.get("Authorization"));
  if (!userId) {
    return fail("unauthorized", "Please sign in again.", 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail("invalid_request", "Malformed request.", 400);
  }

  // Loaded before the validation rather than after the write, because `language` is checked
  // against the list in `app_config` — the dashboard is what decides which languages exist, and
  // a hardcoded enum here would mean adding one needed a deploy after all.
  const config = await loadConfig(db);

  const update: Record<string, string | null> = {};

  if ("name" in body) {
    const name = body.name;
    const trimmed = typeof name === "string" ? name.trim() : "";
    if (trimmed.length < 1 || trimmed.length > 80) {
      return fail("invalid_request", "Please enter your name.", 400);
    }
    update.name = trimmed;
  }

  if ("dob" in body) {
    const dob = body.dob;
    if (typeof dob !== "string" || !isRealPastDate(dob)) {
      return fail("invalid_request", "Please enter a valid date of birth.", 400);
    }
    update.dob = dob;
  }

  // The two the chat collects. Both nullable on the row, and both accept an explicit null so a
  // user who realises they gave the wrong hour can take it back rather than being stuck with a
  // chart built on it.
  if ("birth_time" in body) {
    const value = body.birth_time;
    if (value === null) {
      update.birth_time = null;
    } else if (typeof value === "string" && /^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/.test(value)) {
      update.birth_time = value;
    } else {
      return fail("invalid_request", "Please give the time of birth as HH:MM.", 400);
    }
  }

  if ("birth_place" in body) {
    const value = body.birth_place;
    if (value === null) {
      update.birth_place = null;
    } else {
      const trimmed = typeof value === "string" ? value.trim() : "";
      if (trimmed.length < 1 || trimmed.length > 120) {
        return fail("invalid_request", "Please give a place of birth.", 400);
      }
      update.birth_place = trimmed;
    }
  }

  // Which language Astro answers in. Null resets to the configured default rather than storing
  // the default's current value, so someone who never expressed a preference keeps following it.
  if ("language" in body) {
    const value = body.language;
    if (value === null) {
      update.language = null;
    } else if (typeof value === "string" && isSupported(value, config)) {
      // Stored as the list spells it, not as the client sent it — otherwise "hindi" and "Hindi"
      // both persist and the picker cannot tell which row is selected.
      update.language = supportedLanguages(config)
        .find((entry) => entry.toLowerCase() === value.trim().toLowerCase())!;
    } else {
      return fail("invalid_request", "That language is not available.", 400);
    }
  }

  if (Object.keys(update).length === 0) {
    return fail("invalid_request", "Nothing to update.", 400);
  }

  const { data: user, error } = await db
    .from("users")
    .update(update)
    .eq("user_id", userId)
    .select(USER_COLUMNS)
    .single();

  if (error || !user) {
    console.error("profile update failed", error);
    return fail("server_error", "Could not save your details. Please try again.", 500);
  }

  return json({ user: entitlementPayload(asUserRow(user), graceHoursFrom(config)) });
});
