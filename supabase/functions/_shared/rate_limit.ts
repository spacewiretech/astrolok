import { SupabaseClient } from "jsr:@supabase/supabase-js@2";

/**
 * Claims one call against a fixed-window allowance. Returns false when the window is spent.
 *
 * The counting happens in a single SQL upsert (`consume_rate_limit`, migration
 * `20260917000001_kundali.sql`) so two concurrent requests cannot both slip past the limit — the
 * same shape as `consumeOtpQuota` in `db.ts`.
 *
 * Fails closed. Every caller guards a metered API, and an allowance that cannot be checked must
 * not become an unmetered one.
 */
export async function consumeRateLimit(
  db: SupabaseClient,
  key: string,
  { windowSeconds, max }: { windowSeconds: number; max: number },
): Promise<boolean> {
  const { data, error } = await db.rpc("consume_rate_limit", {
    p_key: key,
    p_window_seconds: windowSeconds,
    p_max: max,
  });
  if (error) {
    console.error("consume_rate_limit failed", error);
    return false;
  }
  return data === true;
}
