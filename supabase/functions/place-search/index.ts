import { localToUtc, offsetSecondsAt } from "../_shared/birth_timezone.ts";
import { configFlag, configSetting, loadConfig } from "../_shared/config.ts";
import { fail, json, preflight } from "../_shared/cors.ts";
import { serviceClient, userIdForBearer } from "../_shared/db.ts";
import { asUserRow, graceHoursFrom, isEntitled, USER_COLUMNS } from "../_shared/entitlement.ts";
import {
  autocomplete,
  isSessionToken,
  placeDetails,
  PlacesError,
  placesApiKey,
  timeZoneAt,
} from "../_shared/google_places.ts";
import { consumeRateLimit } from "../_shared/rate_limit.ts";

/**
 * Birth-place search for the kundali form, proxied so the Google key never reaches the device.
 *
 *   POST {action: "autocomplete", input, session_token}
 *     → {suggestions: [{place_id, primary, secondary}]}
 *   POST {action: "details", place_id, session_token, dob?, birth_time?}
 *     → {place: {place_id, label, lat, lng, time_zone_id, utc_offset_seconds}}
 *
 * Entitled callers only, and metered per user per hour (`place_search_per_hour`): this spends
 * money on every keystroke that gets past the app's debounce, and the key cannot be IP-restricted
 * because Supabase's egress addresses are not fixed.
 *
 * `utc_offset_seconds` is the offset in force at the birth moment when the date and time are
 * given, and today's otherwise. It is informational — `kundali` recomputes it from the zone id.
 */

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  const db = serviceClient();
  const userId = await userIdForBearer(db, req.headers.get("Authorization"));
  if (!userId) return fail("unauthorized", "Please sign in again.", 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail("invalid_request", "Malformed request.", 400);
  }

  const config = await loadConfig(db);
  const unavailable = () =>
    fail("place_unavailable", "Place search isn't available right now. Please try again shortly.", 503);

  if (configSetting(config, "place_search_enabled") && !configFlag(config, "place_search_enabled")) {
    return unavailable();
  }

  const { data: userRow, error: userError } = await db
    .from("users")
    .select(USER_COLUMNS)
    .eq("user_id", userId)
    .single();
  if (userError || !userRow) {
    console.error("place-search: user lookup failed", userError);
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }
  if (!isEntitled(asUserRow(userRow), graceHoursFrom(config))) {
    return fail("not_entitled", "Your subscription has ended. Renew to continue.", 402);
  }

  const sessionToken = body.session_token;
  if (!isSessionToken(sessionToken)) return fail("invalid_request", "Malformed request.", 400);

  const perHour = Number(configSetting(config, "place_search_per_hour") || "120");
  const allowed = await consumeRateLimit(db, `places:${userId}`, {
    windowSeconds: 3600,
    max: Number.isFinite(perHour) && perHour > 0 ? perHour : 120,
  });
  if (!allowed) {
    return fail("throttled", "Too many searches for now. Please wait a few minutes and try again.", 429);
  }

  const apiKey = placesApiKey(config);

  try {
    switch (body.action) {
      case "autocomplete": {
        const input = typeof body.input === "string" ? body.input.trim().replace(/\s+/g, " ") : "";
        if (input.length < 2 || input.length > 100) {
          return fail("invalid_request", "Type at least two letters of the place.", 400);
        }
        return json({ suggestions: await autocomplete(apiKey, { input, sessionToken }) });
      }

      case "details": {
        const placeId = typeof body.place_id === "string" ? body.place_id.trim() : "";
        if (!/^[A-Za-z0-9_-]{1,300}$/.test(placeId)) {
          return fail("invalid_request", "Please choose your birth place from the list.", 400);
        }

        const place = await placeDetails(apiKey, { placeId, sessionToken });
        const birth = birthMoment(body.dob, body.birth_time);
        const timeZoneId = await timeZoneAt(apiKey, {
          lat: place.lat,
          lng: place.lng,
          atMs: birth ?? Date.now(),
        });

        const offsetSeconds = birth !== null
          ? (localToUtcOffset(body.dob as string, body.birth_time as string, timeZoneId) ??
            offsetSecondsAt(timeZoneId, birth))
          : offsetSecondsAt(timeZoneId, Date.now());

        return json({
          place: {
            place_id: place.place_id,
            label: place.formatted_address,
            // Four places is about eleven metres, far finer than a lagna can tell apart.
            lat: Math.round(place.lat * 10_000) / 10_000,
            lng: Math.round(place.lng * 10_000) / 10_000,
            time_zone_id: timeZoneId,
            utc_offset_seconds: offsetSeconds,
          },
        });
      }

      default:
        return fail("invalid_request", "Malformed request.", 400);
    }
  } catch (error) {
    if (error instanceof PlacesError) {
      if (error.kind === "not_found") {
        return fail("not_found", "We couldn't find that place. Please pick another from the list.", 404);
      }
      if (error.kind === "invalid") return fail("invalid_request", "Malformed request.", 400);
      // Quota, configuration and outages all look the same to the user, and all need a human.
      console.error(`place-search: ${error.kind}: ${error.detail}`);
      return unavailable();
    }
    console.error("place-search failed", error);
    return unavailable();
  }
});

/** The approximate birth instant for the zone lookup, or null without a usable date and time. */
function birthMoment(dob: unknown, time: unknown): number | null {
  if (typeof dob !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(dob)) return null;
  const clock = typeof time === "string" && /^\d{2}:\d{2}/.test(time) ? time.slice(0, 5) : "12:00";
  const ms = Date.parse(`${dob}T${clock}:00Z`);
  return Number.isFinite(ms) ? ms : null;
}

function localToUtcOffset(dob: string, time: unknown, timeZoneId: string): number | null {
  if (typeof time !== "string" || !/^\d{2}:\d{2}/.test(time)) return null;
  const [year, month, day] = dob.split("-").map(Number);
  const [hour, minute] = time.slice(0, 5).split(":").map(Number);
  return localToUtc({ year, month, day, hour, minute }, timeZoneId)?.offsetSeconds ?? null;
}
