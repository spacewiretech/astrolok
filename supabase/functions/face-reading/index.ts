import { loadConfig } from "../_shared/config.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer } from "../_shared/db.ts";
import {
  asUserRow,
  graceHoursFrom,
  isEntitled,
  USER_COLUMNS,
} from "../_shared/entitlement.ts";
import { GeminiError, geminiSettings, readImage } from "../_shared/gemini.ts";
import {
  buildUserPrompt,
  FACE_SCHEMA,
  FOCUS_KEYS,
  FocusKey,
  focusMismatch,
  normaliseFaceReading,
  SYSTEM_PROMPT,
} from "../_shared/face_reading.ts";

/**
 * Reads a photograph of a face and returns a written reading.
 *
 * A deliberate mirror of `palm-reading`, down to the order of the checks. The two endpoints
 * spend money the same way and have to be defended the same way, and a reader comparing them
 * should be able to see at a glance that neither has quietly lost a guard the other has.
 *
 * The photograph is never stored. It arrives as base64, goes to the model, and is gone when this
 * function returns — there is no column and no bucket that could hold one. The only copy that
 * outlives the request is on the user's own device. That promise matters more here than it did
 * for palms: this is a photograph of someone's face.
 *
 * The user id comes from the session token, never from the request body, so no request can ask
 * for a reading against another account or bill one to it.
 *
 * Entitlement is re-checked here rather than trusted from the app. `EntitlementGate` on the
 * client is a convenience that keeps a lapsed user out of the UI; it is not a boundary, and
 * this endpoint spends money.
 */

/** Roughly 1.1 MB of image once decoded. The app targets ~250 KB, so this is a ceiling. */
const MAX_BASE64_CHARS = 1_500_000;

/** Fails the whole request rather than letting a retry run past Supabase's own ceiling. */
const DEADLINE_MS = 70_000;

/**
 * What the user is told for each way a photo can fail to be a face.
 *
 * Each one names the fix. "We couldn't read that" sends people back to try the identical shot
 * again; "hold the camera at eye level" gets a different photograph on the second attempt.
 */
const REJECT_MESSAGES: Record<string, string> = {
  no_face: "We couldn't find a face in that photo. Hold the camera at eye level and look ahead.",
  not_a_face:
    "We couldn't find a face in that photo. Hold the camera at eye level and look ahead.",
  too_dark: "That photo is a bit too dark. Try again somewhere brighter.",
  too_blurry: "That photo came out blurry. Hold steady and try again.",
  too_far: "You're a little far away. Bring the camera closer so your face fills the frame.",
  obstructed: "Something is covering your face. Move it aside and try again.",
  incomplete: "We couldn't read enough of that photo. Try again facing the camera.",
};

function ageFrom(dob: string | null): number | null {
  if (!dob) return null;
  const born = new Date(`${dob}T00:00:00Z`);
  if (Number.isNaN(born.getTime())) return null;

  const now = new Date();
  let age = now.getUTCFullYear() - born.getUTCFullYear();
  const monthDelta = now.getUTCMonth() - born.getUTCMonth();
  if (monthDelta < 0 || (monthDelta === 0 && now.getUTCDate() < born.getUTCDate())) age -= 1;

  return age >= 0 && age < 130 ? age : null;
}

/** First name only. The prompt addresses the user directly; a full legal name reads oddly. */
function firstName(name: string | null): string | null {
  const first = (name ?? "").trim().split(/\s+/)[0];
  return first.length > 0 ? first : null;
}

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  const startedAt = Date.now();
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

  const imageBase64 = typeof body.image === "string" ? body.image : "";
  if (!imageBase64) {
    return fail("invalid_request", "No photo was sent.", 400);
  }
  if (imageBase64.length > MAX_BASE64_CHARS) {
    return fail("invalid_request", "That photo is too large. Please try again.", 413);
  }

  const focus = FOCUS_KEYS.includes(body.focus as FocusKey)
    ? body.focus as FocusKey
    : "life_path";

  const mimeType = body.mime_type === "image/png" ? "image/png" : "image/jpeg";

  const config = await loadConfig(db);

  const { data: userRow, error: userError } = await db
    .from("users")
    .select(USER_COLUMNS)
    .eq("user_id", userId)
    .single();

  if (userError || !userRow) {
    console.error("face-reading: user lookup failed", userError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  const user = asUserRow(userRow);
  if (!isEntitled(user, graceHoursFrom(config))) {
    return fail("not_entitled", "Your subscription has ended. Renew to keep reading.", 402);
  }

  // ------------------------------------------------------------ quota
  //
  // Counted separately from palm readings, on its own config row. A shared ceiling would mean a
  // user who read their palm ten times could not read their face at all, which is not a limit
  // anyone would expect from an app that sells both.
  //
  // `failed` rows are excluded: a user should not lose a reading because the model was down.
  const perDay = Number(config.get("face_readings_per_day") ?? "10");
  const limit = Number.isFinite(perDay) && perDay > 0 ? perDay : 10;
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const { count, error: countError } = await db
    .from("face_readings")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .neq("status", "failed")
    .gte("created_at", since);

  if (countError) {
    // Fail closed, exactly as `consume_otp_quota` does: if the ceiling cannot be checked, do
    // not spend against it.
    console.error("face-reading: quota check failed", countError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  if ((count ?? 0) >= limit) {
    return fail(
      "limit_reached",
      `You've used all ${limit} face readings for today. Come back tomorrow.`,
      429,
    );
  }

  // The row goes in before the model is called, so a request that costs money is counted even
  // if it never comes back — and so the id it returns can name the image file on the device.
  const { data: pending, error: insertError } = await db
    .from("face_readings")
    .insert({ user_id: userId, focus, status: "pending", image_bytes: imageBase64.length })
    .select("id")
    .single();

  if (insertError || !pending) {
    console.error("face-reading: could not open a reading", insertError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  const readingId = pending.id as string;

  // ------------------------------------------------------------ the reading

  try {
    const settings = geminiSettings(config);
    const result = await readImage(settings, {
      imageBase64,
      mimeType,
      systemPrompt: SYSTEM_PROMPT,
      schema: FACE_SCHEMA,
      userPrompt: buildUserPrompt({
        focus,
        name: firstName(user.name),
        age: ageFrom(user.dob),
      }),
    });

    if (focusMismatch(result.parsed, focus)) {
      console.warn(`face-reading ${readingId}: model echoed a different focus`);
    }

    const reading = normaliseFaceReading(result.parsed, focus);

    // Never the base64, never the key, never the reading text.
    console.log(
      `face-reading ${readingId}: model=${result.model} latency=${result.latencyMs}ms ` +
        `bytes=${imageBase64.length} parts=${reading.parts.length} ` +
        `rejected=${reading.rejected ?? "no"}`,
    );

    if (reading.rejected) {
      await db
        .from("face_readings")
        .update({
          status: "rejected",
          reject_reason: reading.rejected,
          model: result.model,
          latency_ms: result.latencyMs,
        })
        .eq("id", readingId);

      return fail(
        "no_face",
        REJECT_MESSAGES[reading.rejected] ?? REJECT_MESSAGES.not_a_face,
        422,
      );
    }

    const { error: updateError } = await db
      .from("face_readings")
      .update({
        status: "ready",
        reject_reason: null,
        invocation: reading.invocation,
        headline: reading.headline,
        core_trait_title: reading.coreTrait.title,
        core_trait_summary: reading.coreTrait.summary,
        core_trait_detail: reading.coreTrait.detail,
        traits: reading.traits,
        face: reading.face,
        parts: reading.parts,
        blessing: reading.blessing,
        model: result.model,
        latency_ms: result.latencyMs,
      })
      .eq("id", readingId);

    if (updateError) {
      // The reading itself is fine and the user waited for it, so it is still returned. Only
      // the ability to re-open it later is lost, and that is not worth failing the request.
      console.error(`face-reading ${readingId}: could not save`, updateError);
    }

    return json({
      reading: {
        id: readingId,
        created_at: new Date().toISOString(),
        focus: reading.focus,
        invocation: reading.invocation,
        headline: reading.headline,
        core_trait: reading.coreTrait,
        traits: reading.traits,
        face: reading.face,
        parts: reading.parts,
        blessing: reading.blessing,
      },
    });
  } catch (error) {
    await db
      .from("face_readings")
      .update({ status: "failed" })
      .eq("id", readingId);

    if (error instanceof GeminiError) {
      // A missing key carries no status code and would otherwise be the one failure nobody
      // ever sees; the user gets the same outage message either way.
      if (error.isConfigurationProblem) {
        console.error(`face-reading ${readingId}: configuration`, error.detail);
      } else {
        console.error(`face-reading ${readingId}: ${error.detail}`);
      }
      return fail("ai_unavailable", error.userMessage, 503);
    }

    // Unparseable JSON after a retry lands here. The user gains nothing from being told the
    // model returned invalid JSON, so it stays in the log.
    console.error(
      `face-reading ${readingId}: failed after ${Date.now() - startedAt}ms`,
      error,
    );
    return fail(
      "ai_unavailable",
      "Our reader is very busy right now. Please try again in a minute.",
      503,
    );
  } finally {
    if (Date.now() - startedAt > DEADLINE_MS) {
      console.warn(`face-reading ${readingId}: ran ${Date.now() - startedAt}ms`);
    }
  }
});
