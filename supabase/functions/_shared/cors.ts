export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * Error shape the Flutter client maps onto its exception types.
 *
 * `code` is a stable machine-readable string; `message` is already safe to show to a user —
 * the real cause of a configuration failure stays in the function logs.
 */
export function fail(
  code:
    | "invalid_request"
    | "invalid_otp"
    | "otp_expired"
    | "throttled"
    | "unauthorized"
    | "send_failed"
    | "server_error"
    // Cashfree refused, or is unreachable. The user can retry; nothing was charged.
    | "payment_failed"
    // The caller is already entitled, so starting a mandate would charge them twice.
    | "already_subscribed"
    // Signed in, but the subscription has lapsed. Distinct from `unauthorized`: the session is
    // valid, so the caller must be sent to the paywall rather than back to sign-in.
    | "not_entitled"
    // add-person: this pair is already linked, in whatever direction.
    | "already_connected"
    // add-person: the caller is at max_tracked_people, or the day's palm readings are used up.
    | "limit_reached"
    // The photo did not show a readable palm. Distinct from a failure: nothing went wrong, the
    // user simply needs to take another photo, so the app sends them back to the camera.
    | "no_palm"
    // The reading model is unreachable, overloaded, or answered with something unusable.
    // Retryable, and nothing is wrong with the user's photo.
    | "ai_unavailable",
  message: string,
  status = 400,
): Response {
  return json({ error: { code, message } }, status);
}

export function preflight(req: Request): Response | null {
  return req.method === "OPTIONS"
    ? new Response("ok", { headers: corsHeaders })
    : null;
}
