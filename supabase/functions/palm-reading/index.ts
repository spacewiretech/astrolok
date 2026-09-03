import { loadConfig } from "../_shared/config.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer } from "../_shared/db.ts";
import {
  asUserRow,
  graceHoursFrom,
  isEntitled,
  USER_COLUMNS,
} from "../_shared/entitlement.ts";
import {
  FOCUS_KEYS,
  FocusKey,
  focusMismatch,
  GeminiError,
  geminiSettings,
  normalisePalmReading,
  readPalm,
} from "../_shared/gemini.ts";

/**
 * Reads a photograph of a palm and returns a written reading.
 *
 * The photograph is never stored. It arrives as base64, goes to the model, and is gone when
 * this function returns — there is no column and no bucket that could hold one. The only copy
 * that outlives the request is on the user's own device.
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

/** What the user is told for each way a photo can fail to be a palm. */
const REJECT_MESSAGES: Record<string, string> = {
  no_hand: "We couldn't find a palm in that photo. Hold your open hand inside the frame.",
  not_a_palm: "We couldn't find a palm in that photo. Hold your open hand inside the frame.",
  too_dark: "That photo is a bit too dark. Try again somewhere brighter.",
  too_blurry: "That photo came out blurry. Hold steady and try again.",
  too_far: "Your hand is a little far away. Bring it closer so it fills the frame.",
  obstructed: "Something is covering your palm. Open your hand fully and try again.",
  incomplete: "We couldn't read enough of that palm. Try again with your hand fully open.",
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
    console.error("palm-reading: user lookup failed", userError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  const user = asUserRow(userRow);
  if (!isEntitled(user, graceHoursFrom(config))) {
    return fail("not_entitled", "Your subscription has ended. Renew to keep reading.", 402);
  }

  // ------------------------------------------------------------ quota
  //
  // Every other spend path in this codebase has a ceiling — `consume_otp_quota` for SMS, and
  // server-side amount resolution for payments. Without one here, a modified client holding a
  // valid session token could loop this endpoint against a metered API at our expense.
  //
  // `failed` rows are excluded: a user should not lose a reading because the model was down.
  const perDay = Number(config.get("palm_readings_per_day") ?? "10");
  const limit = Number.isFinite(perDay) && perDay > 0 ? perDay : 10;
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const { count, error: countError } = await db
    .from("palm_readings")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .neq("status", "failed")
    .gte("created_at", since);

  if (countError) {
    // Fail closed, exactly as `consume_otp_quota` does: if the ceiling cannot be checked, do
    // not spend against it.
    console.error("palm-reading: quota check failed", countError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  if ((count ?? 0) >= limit) {
    return fail(
      "limit_reached",
      `You've used all ${limit} palm readings for today. Come back tomorrow.`,
      429,
    );
  }

  // The row goes in before the model is called, so a request that costs money is counted even
  // if it never comes back — and so the id it returns can name the image file on the device.
  const { data: pending, error: insertError } = await db
    .from("palm_readings")
    .insert({ user_id: userId, focus, status: "pending", image_bytes: imageBase64.length })
    .select("id")
    .single();

  if (insertError || !pending) {
    console.error("palm-reading: could not open a reading", insertError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }

  const readingId = pending.id as string;

  // ------------------------------------------------------------ the reading

  try {
    const settings = geminiSettings(config);
    const result = await readPalm(settings, {
      imageBase64,
      mimeType,
      focus,
      name: firstName(user.name),
      age: ageFrom(user.dob),
    });

    if (focusMismatch(result.parsed, focus)) {
      console.warn(`palm-reading ${readingId}: model echoed a different focus`);
    }

    const reading = normalisePalmReading(result.parsed, focus);

    // Never the base64, never the key, never the reading text.
    console.log(
      `palm-reading ${readingId}: model=${result.model} latency=${result.latencyMs}ms ` +
        `bytes=${imageBase64.length} lines=${reading.lines.length} ` +
        `rejected=${reading.rejected ?? "no"}`,
    );

    if (reading.rejected) {
      await db
        .from("palm_readings")
        .update({
          status: "rejected",
          reject_reason: reading.rejected,
          model: result.model,
          latency_ms: result.latencyMs,
        })
        .eq("id", readingId);

      return fail(
        "no_palm",
        REJECT_MESSAGES[reading.rejected] ?? REJECT_MESSAGES.not_a_palm,
        422,
      );
    }

    const { error: updateError } = await db
      .from("palm_readings")
      .update({
        status: "ready",
        reject_reason: null,
        headline: reading.headline,
        strongest_trait_title: reading.strongestTrait.title,
        strongest_trait_summary: reading.strongestTrait.summary,
        strongest_trait_detail: reading.strongestTrait.detail,
        hand: reading.hand,
        lines: reading.lines,
        model: result.model,
        latency_ms: result.latencyMs,
      })
      .eq("id", readingId);

    if (updateError) {
      // The reading itself is fine and the user waited for it, so it is still returned. Only
      // the ability to re-open it later is lost, and that is not worth failing the request.
      console.error(`palm-reading ${readingId}: could not save`, updateError);
    }

    return json({
      reading: {
        id: readingId,
        created_at: new Date().toISOString(),
        focus: reading.focus,
        headline: reading.headline,
        strongest_trait: reading.strongestTrait,
        hand: reading.hand,
        lines: reading.lines,
      },
    });
  } catch (error) {
    await db
      .from("palm_readings")
      .update({ status: "failed" })
      .eq("id", readingId);

    if (error instanceof GeminiError) {
      // A missing key carries no status code and would otherwise be the one failure nobody
      // ever sees; the user gets the same outage message either way.
      if (error.isConfigurationProblem) {
        console.error(`palm-reading ${readingId}: configuration`, error.detail);
      } else {
        console.error(`palm-reading ${readingId}: ${error.detail}`);
      }
      return fail("ai_unavailable", error.userMessage, 503);
    }

    // Unparseable JSON after a retry lands here. The user gains nothing from being told the
    // model returned invalid JSON, so it stays in the log.
    console.error(
      `palm-reading ${readingId}: failed after ${Date.now() - startedAt}ms`,
      error,
    );
    return fail(
      "ai_unavailable",
      "Our reader is very busy right now. Please try again in a minute.",
      503,
    );
  } finally {
    if (Date.now() - startedAt > DEADLINE_MS) {
      console.warn(`palm-reading ${readingId}: ran ${Date.now() - startedAt}ms`);
    }
  }
});
