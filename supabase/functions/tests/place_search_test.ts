import { assertEquals } from "jsr:@std/assert@1";

import {
  classifyPlacesError,
  isSessionToken,
  parseAutocomplete,
  parseDetails,
  parseTimeZone,
} from "../_shared/google_places.ts";

Deno.test("session tokens must be UUIDs", () => {
  assertEquals(isSessionToken("9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"), true);
  assertEquals(isSessionToken("not-a-token"), false);
  assertEquals(isSessionToken(""), false);
  assertEquals(isSessionToken(null), false);
});

Deno.test("autocomplete keeps up to five usable predictions", () => {
  const body = {
    suggestions: [
      { placePrediction: { placeId: "a", structuredFormat: { mainText: { text: "Tirupati" }, secondaryText: { text: "Andhra Pradesh, India" } } } },
      { placePrediction: { placeId: "", structuredFormat: { mainText: { text: "No id" } } } },
      { queryPrediction: { text: { text: "tirupati temple" } } },
      { placePrediction: { placeId: "b", text: { text: "Tiruppur, Tamil Nadu, India" } } },
      ...Array.from({ length: 6 }, (_, i) => ({ placePrediction: { placeId: `c${i}`, structuredFormat: { mainText: { text: `P${i}` } } } })),
    ],
  };
  const out = parseAutocomplete(body);
  assertEquals(out.length, 5);
  assertEquals(out[0], { place_id: "a", primary: "Tirupati", secondary: "Andhra Pradesh, India" });
  assertEquals(out[1], { place_id: "b", primary: "Tiruppur, Tamil Nadu, India", secondary: "" });
  assertEquals(parseAutocomplete({}), []);
  assertEquals(parseAutocomplete(null), []);
});

Deno.test("details need an id and a location on the globe", () => {
  assertEquals(
    parseDetails({ id: "a", formattedAddress: "Tirupati, AP, India", location: { latitude: 13.6288, longitude: 79.4192 } }),
    { place_id: "a", formatted_address: "Tirupati, AP, India", lat: 13.6288, lng: 79.4192 },
  );
  assertEquals(parseDetails({ id: "a", location: {} }), null);
  assertEquals(parseDetails({ location: { latitude: 1, longitude: 2 } }), null);
  assertEquals(parseDetails({ id: "a", location: { latitude: 95, longitude: 2 } }), null);
});

Deno.test("time zone answers map onto the failure the user or an operator can act on", () => {
  assertEquals(parseTimeZone({ status: "OK", timeZoneId: "Asia/Calcutta" }), { ok: true, timeZoneId: "Asia/Calcutta" });
  assertEquals(parseTimeZone({ status: "ZERO_RESULTS" }), { ok: false, kind: "not_found" });
  assertEquals(parseTimeZone({ status: "OVER_QUERY_LIMIT" }), { ok: false, kind: "quota" });
  assertEquals(parseTimeZone({ status: "REQUEST_DENIED" }), { ok: false, kind: "config" });
  assertEquals(parseTimeZone({ status: "OK" }), { ok: false, kind: "upstream" });
  assertEquals(parseTimeZone(null), { ok: false, kind: "upstream" });
});

Deno.test("HTTP failures are classified without trusting the body to be JSON", () => {
  assertEquals(classifyPlacesError(404, ""), "not_found");
  assertEquals(classifyPlacesError(400, '{"error":{"status":"INVALID_ARGUMENT"}}'), "not_found");
  assertEquals(classifyPlacesError(429, "<html>"), "quota");
  assertEquals(classifyPlacesError(403, '{"error":{"status":"PERMISSION_DENIED"}}'), "config");
  assertEquals(classifyPlacesError(200, '{"error":{"status":"RESOURCE_EXHAUSTED"}}'), "quota");
  assertEquals(classifyPlacesError(503, "oops"), "upstream");
});
