import { inBackground } from "../_shared/background.ts";
import { AppConfig, configFlag, configSetting, loadConfig } from "../_shared/config.ts";
import { corsHeaders, fail, json } from "../_shared/cors.ts";
import { isCronRequest } from "../_shared/cron_auth.ts";
import { serviceClient } from "../_shared/db.ts";
import { configureMixpanel } from "../_shared/mixpanel.ts";
import {
  campaignDelayKey,
  campaignFlagKey,
  CAMPAIGNS,
  CampaignKey,
  isCampaignKey,
  SCHEDULED_CAMPAIGNS,
} from "../_shared/notification_campaigns.ts";
import {
  configureNotifications,
  enqueue,
  NotificationRow,
  notificationSettings,
  processRow,
  sendDue,
} from "../_shared/notify.ts";

type Db = ReturnType<typeof serviceClient>;

/**
 * The scheduled half of the push pipeline. pg_cron calls it every five minutes
 * (`20260917000002_notifications.sql`), authenticated with `x-cron-secret`.
 *
 *   POST {}                                          → 202; finds and enqueues, then sends what is due
 *   POST {action: "dry_run", campaign?}              → {candidates: {campaign: count}}, sends nothing
 *   POST {action: "send_test", user_id, campaign}    → {notification_id, status}
 *
 * `dry_run` and `send_test` are for an operator with the same secret, before switching a campaign
 * on: how many people would get it, and what it looks like on a real phone. `send_test` ignores the
 * flags, quiet hours, the cap and eligibility; it still needs the account to have a device that can
 * show it.
 *
 * Nothing happens at all while `notifications_enabled` is false, except those two.
 */

/** Stop starting new sends after this, so the run fits inside the runtime's wall clock. */
const RUN_BUDGET_MS = 100_000;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const db = serviceClient();
  const config = await loadConfig(db);
  if (!isCronRequest(req, config)) return new Response("forbidden", { status: 403, headers: corsHeaders });

  configureMixpanel(config, "notification-dispatch");
  configureNotifications(config, "notification-dispatch");

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    // pg_cron sends `{}`; an empty body is the scheduled run too.
  }

  switch (body.action) {
    case undefined:
    case "run":
      await inBackground("notification-dispatch run", run(db, config));
      return json({ accepted: true }, 202);

    case "dry_run": {
      const only = isCampaignKey(body.campaign) ? [body.campaign] : [...SCHEDULED_CAMPAIGNS];
      const candidates: Record<string, number | string> = {};
      for (const campaign of only) {
        if (!CAMPAIGNS[campaign].scheduled) {
          candidates[campaign] = "inline";
          continue;
        }
        const { data, error } = await findCandidates(db, config, campaign, 1000);
        candidates[campaign] = error ? `error: ${error.message}` : (data?.length ?? 0);
      }
      return json({ candidates });
    }

    case "send_test": {
      const userId = typeof body.user_id === "string" ? body.user_id : "";
      if (!/^[0-9a-f-]{36}$/i.test(userId) || !isCampaignKey(body.campaign)) {
        return fail("invalid_request", "Expected {user_id, campaign}.", 400);
      }
      const id = await enqueue(db, {
        userId,
        campaign: body.campaign,
        dedupeKey: `test:${crypto.randomUUID()}`,
        params: typeof body.params === "object" && body.params !== null ? body.params as Record<string, unknown> : {},
        trigger: "test",
        expiresAt: new Date(Date.now() + 3600_000),
      });
      if (!id) return fail("server_error", "Could not enqueue the test push.", 500);

      const { data } = await db.rpc("claim_notification", { p_id: id });
      const row = (Array.isArray(data) ? data[0] : data) as NotificationRow | undefined;
      if (!row) return fail("server_error", "Could not claim the test push.", 500);

      const status = await processRow(db, config, row, { force: true });
      return json({ notification_id: id, status });
    }

    default:
      return fail("invalid_request", "Unknown action.", 400);
  }
});

function findCandidates(db: Db, config: AppConfig, campaign: CampaignKey, limit: number) {
  const delay = Number(configSetting(config, campaignDelayKey(campaign)));
  return db.rpc("notification_candidates", {
    p_campaign: campaign,
    p_now: new Date().toISOString(),
    p_delay_minutes: Number.isFinite(delay) && configSetting(config, campaignDelayKey(campaign)) !== ""
      ? delay
      : CAMPAIGNS[campaign].defaultDelayMinutes,
    p_min_build: notificationSettings(config).minAppBuild,
    p_limit: limit,
  }) as unknown as Promise<{
    data: Array<{ user_id: string; dedupe_key: string; params: Record<string, unknown>; scheduled_for: string; expires_at: string }> | null;
    error: { message: string } | null;
  }>;
}

async function run(db: Db, config: AppConfig): Promise<void> {
  if (!configFlag(config, "notifications_enabled")) return;
  const startedAt = Date.now();
  let enqueued = 0;

  for (const campaign of SCHEDULED_CAMPAIGNS) {
    // `kundali_ready` also carries its lapsed variant, chosen at send time — so it is looked for when
    // either is switched on.
    const on = configFlag(config, campaignFlagKey(campaign)) ||
      (campaign === "kundali_ready" && configFlag(config, campaignFlagKey("kundali_ready_lapsed")));
    if (!on) continue;

    const { data, error } = await findCandidates(db, config, campaign, 200);
    if (error) {
      console.error(`notification-dispatch: ${campaign} candidates failed`, error);
      continue;
    }

    for (const candidate of data ?? []) {
      const id = await enqueue(db, {
        userId: candidate.user_id,
        campaign,
        dedupeKey: candidate.dedupe_key,
        params: candidate.params ?? {},
        trigger: "cron",
        scheduledFor: candidate.scheduled_for,
        expiresAt: candidate.expires_at,
      });
      if (id) enqueued += 1;
    }
  }

  const tally = await sendDue(db, config, startedAt + RUN_BUDGET_MS);
  console.log(`notification-dispatch: enqueued=${enqueued} ${JSON.stringify(tally)} in ${Date.now() - startedAt}ms`);
}
