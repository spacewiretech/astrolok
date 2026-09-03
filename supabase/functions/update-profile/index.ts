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

  const update: Record<string, string> = {};

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

  const config = await loadConfig(db);
  return json({ user: entitlementPayload(asUserRow(user), graceHoursFrom(config)) });
});
