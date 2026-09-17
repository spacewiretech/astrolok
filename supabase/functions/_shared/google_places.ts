/**
 * Google Places (New) and the Time Zone API, called with the key held server-side.
 *
 * The same arrangement as `gemini.ts`: the key never ships in the app, where it would be
 * extractable, and it lives in a private `app_config` row so rotating it is a dashboard edit. The
 * transport is thin; the parsers and the error classification are pure and tested.
 *
 * Billing notes that shaped this file:
 *   - Autocomplete and the Details call that follows it share a session token, which bills the
 *     whole search as one session rather than per keystroke.
 *   - Details asks only for `id,formattedAddress,location`, which stays inside the Essentials SKU.
 *     `displayName` would move it up a tier; the label comes from the autocomplete row instead.
 *   - The Time Zone API is only used for its zone id. The offset at the moment of birth comes from
 *     the runtime's own tz database (`birth_timezone.ts`), which knows the history Google's
 *     `rawOffset` does not return.
 */

import { AppConfig, configSetting } from "./config.ts";

const PLACES = "https://places.googleapis.com/v1";
const TIME_ZONE = "https://maps.googleapis.com/maps/api/timezone/json";
const TIMEOUT_MS = 8_000;

export function placesApiKey(config: AppConfig): string {
  return configSetting(config, "google_places_api_key");
}

export type PlacesErrorKind = "not_found" | "quota" | "config" | "upstream" | "invalid";

export class PlacesError extends Error {
  constructor(readonly kind: PlacesErrorKind, readonly detail: string) {
    super(detail);
  }
}

/** A UUID, the session-token shape Google recommends and the only one accepted here. */
export function isSessionToken(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

export interface PlaceSuggestion {
  place_id: string;
  primary: string;
  secondary: string;
}

export interface PlaceLocation {
  place_id: string;
  formatted_address: string;
  lat: number;
  lng: number;
}

/**
 * Which way a failure points: at the user's input, at our quota, at our configuration, or at
 * Google. Only the first is ever the user's to fix, and none of the detail is ever shown to them.
 */
export function classifyPlacesError(httpStatus: number, body: string): PlacesErrorKind {
  let status = "";
  try {
    status = String((JSON.parse(body) as { error?: { status?: string } })?.error?.status ?? "");
  } catch {
    // Not JSON — classify on the HTTP status alone.
  }

  if (httpStatus === 404 || status === "NOT_FOUND") return "not_found";
  if (httpStatus === 429 || status === "RESOURCE_EXHAUSTED") return "quota";
  if (httpStatus === 401 || httpStatus === 403 || status === "PERMISSION_DENIED" || status === "UNAUTHENTICATED") {
    return "config";
  }
  // A malformed place id comes back as INVALID_ARGUMENT; to the caller that is a place that does
  // not exist.
  if (httpStatus === 400) return "not_found";
  return "upstream";
}

export function parseAutocomplete(body: unknown): PlaceSuggestion[] {
  const suggestions = (body as { suggestions?: unknown[] } | null)?.suggestions;
  if (!Array.isArray(suggestions)) return [];

  const out: PlaceSuggestion[] = [];
  for (const entry of suggestions) {
    const prediction = (entry as { placePrediction?: Record<string, any> })?.placePrediction;
    if (!prediction) continue;
    const placeId = String(prediction.placeId ?? "").trim();
    const primary = String(prediction.structuredFormat?.mainText?.text ?? prediction.text?.text ?? "").trim();
    if (!placeId || !primary) continue;
    out.push({
      place_id: placeId,
      primary: primary.slice(0, 120),
      secondary: String(prediction.structuredFormat?.secondaryText?.text ?? "").trim().slice(0, 120),
    });
    if (out.length === 5) break;
  }
  return out;
}

export function parseDetails(body: unknown): PlaceLocation | null {
  const b = (body ?? {}) as Record<string, any>;
  const lat = Number(b.location?.latitude);
  const lng = Number(b.location?.longitude);
  const placeId = String(b.id ?? "").trim();
  if (!placeId || !Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return { place_id: placeId, formatted_address: String(b.formattedAddress ?? "").trim(), lat, lng };
}

/** The zone id from a Time Zone API answer, or the kind of failure it was. */
export function parseTimeZone(body: unknown): { ok: true; timeZoneId: string } | { ok: false; kind: PlacesErrorKind } {
  const b = (body ?? {}) as Record<string, unknown>;
  switch (b.status) {
    case "OK":
      return typeof b.timeZoneId === "string" && b.timeZoneId
        ? { ok: true, timeZoneId: b.timeZoneId }
        : { ok: false, kind: "upstream" };
    case "ZERO_RESULTS":
      // Open ocean, mostly. Nobody is born there often enough to design for.
      return { ok: false, kind: "not_found" };
    case "OVER_DAILY_LIMIT":
    case "OVER_QUERY_LIMIT":
      return { ok: false, kind: "quota" };
    case "REQUEST_DENIED":
      return { ok: false, kind: "config" };
    case "INVALID_REQUEST":
      return { ok: false, kind: "invalid" };
    default:
      return { ok: false, kind: "upstream" };
  }
}

async function call(url: string, init: RequestInit): Promise<unknown> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetch(url, { ...init, signal: controller.signal });
  } catch (error) {
    throw new PlacesError("upstream", `fetch failed: ${error}`);
  } finally {
    clearTimeout(timer);
  }

  const raw = await response.text().catch(() => "");
  if (!response.ok) {
    throw new PlacesError(classifyPlacesError(response.status, raw), `${response.status}: ${raw.slice(0, 300)}`);
  }
  try {
    return JSON.parse(raw);
  } catch {
    throw new PlacesError("upstream", `unparseable body: ${raw.slice(0, 120)}`);
  }
}

export async function autocomplete(
  apiKey: string,
  { input, sessionToken }: { input: string; sessionToken: string },
): Promise<PlaceSuggestion[]> {
  if (!apiKey) throw new PlacesError("config", "google_places_api_key is empty in app_config");
  const body = await call(`${PLACES}/places:autocomplete`, {
    method: "POST",
    headers: {
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask":
        "suggestions.placePrediction.placeId,suggestions.placePrediction.structuredFormat,suggestions.placePrediction.text",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      input,
      sessionToken,
      // Cities, towns and villages — the unit a birth place is given in. Not addresses.
      includedPrimaryTypes: ["(cities)"],
      // A bias, not a restriction: Indian places rank first, and someone born in Dubai still finds it.
      regionCode: "in",
      languageCode: "en",
    }),
  });
  return parseAutocomplete(body);
}

export async function placeDetails(
  apiKey: string,
  { placeId, sessionToken }: { placeId: string; sessionToken: string },
): Promise<PlaceLocation> {
  if (!apiKey) throw new PlacesError("config", "google_places_api_key is empty in app_config");
  const url = `${PLACES}/places/${encodeURIComponent(placeId)}?sessionToken=${encodeURIComponent(sessionToken)}`;
  const body = await call(url, {
    method: "GET",
    headers: { "X-Goog-Api-Key": apiKey, "X-Goog-FieldMask": "id,formattedAddress,location" },
  });
  const place = parseDetails(body);
  if (!place) throw new PlacesError("upstream", "details answered without a usable location");
  return place;
}

export async function timeZoneAt(
  apiKey: string,
  { lat, lng, atMs }: { lat: number; lng: number; atMs: number },
): Promise<string> {
  if (!apiKey) throw new PlacesError("config", "google_places_api_key is empty in app_config");
  // The API refuses timestamps before 1970 with INVALID_REQUEST on some zones; the zone *id* does
  // not depend on the date, so an early birth is asked about as of the epoch instead.
  const timestamp = Math.max(0, Math.floor(atMs / 1000));
  const url = `${TIME_ZONE}?location=${lat},${lng}&timestamp=${timestamp}&key=${encodeURIComponent(apiKey)}`;
  const parsed = parseTimeZone(await call(url, { method: "GET" }));
  if (!parsed.ok) throw new PlacesError(parsed.kind, `time zone lookup failed: ${parsed.kind}`);
  return parsed.timeZoneId;
}
