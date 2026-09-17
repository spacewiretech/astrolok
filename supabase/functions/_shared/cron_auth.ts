import { constantTimeEquals } from "./cashfree.ts";
import { AppConfig, configSetting } from "./config.ts";

/**
 * Whether a request came from our own pg_cron job.
 *
 * The scheduled functions (`kundali-worker`, `notification-dispatch`) spend money and send pushes,
 * so they must not be callable by anyone who guesses the URL. pg_cron sends
 * `app_config.reconcile_secret` in `x-cron-secret` — the same secret `subscription-reconcile`
 * already uses, so there is one value to rotate rather than one per job.
 *
 * Fails closed: with no secret configured, nothing is a cron request.
 */
export function isCronRequest(req: Request, config: AppConfig): boolean {
  const expected = configSetting(config, "reconcile_secret");
  const provided = req.headers.get("x-cron-secret") ?? "";
  return expected.length > 0 && constantTimeEquals(expected, provided);
}
