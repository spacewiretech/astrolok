/**
 * The send pipeline. Every push — scheduled or inline — goes through [processRow]:
 *
 *   resolve (is it still true? which variant?) → flags → expiry → opt-out → quiet hours → cap
 *   → tokens → copy → FCM → record → Mixpanel
 *
 * A row is enqueued once per real-world occurrence (`dedupe_key` is unique), claimed with SKIP
 * LOCKED, and ends as `sent`, `failed` or `skipped` — or goes back to `queued` with a later
 * `scheduled_for` when it is deferred or worth retrying. Nothing here throws into its caller: the
 * inline path hangs off the Cashfree webhook, and a push must never cost anyone their subscription.
 *
 * Eligibility is re-checked at send time against the live account — entitlement through the same
 * `isEntitled` every function uses — because a row can sit in the queue overnight, and "you haven't
 * tried a face reading" is wrong the moment they have.
 */

import { SupabaseClient } from "jsr:@supabase/supabase-js@2";

import { eachBounded, inBackground } from "./background.ts";
import { resolveLanguage } from "./chat_language.ts";
import { AppConfig, configFlag, configSetting } from "./config.ts";
import { asUserRow, graceHoursFrom, isEntitled, USER_COLUMNS, UserRow } from "./entitlement.ts";
import { fcmAccessToken, sendFcm, serviceAccountFrom } from "./fcm.ts";
import { trackServer } from "./mixpanel.ts";
import {
  CAMPAIGNS,
  CampaignKey,
  campaignFlagKey,
  CAPPED_CAMPAIGNS,
  capDeferral,
  insertIdFor,
  istMidnight,
  PushRoute,
  quietHoursDeferral,
} from "./notification_campaigns.ts";
import { renderCopy } from "./notification_copy.ts";

type Db = SupabaseClient;

export interface NotificationRow {
  id: string;
  user_id: string;
  campaign: CampaignKey;
  dedupe_key: string;
  kind: string;
  route: string;
  params: Record<string, unknown>;
  status: string;
  trigger: "cron" | "inline" | "test";
  scheduled_for: string;
  expires_at: string;
  attempts: number;
  created_at: string;
}

// ---------------------------------------------------------------- configuration

let configured: { config: AppConfig; functionName: string } | null = null;

/** Set once per request, like `configureMixpanel`. The inline hooks do nothing until it is. */
export function configureNotifications(config: AppConfig, functionName: string): void {
  configured = { config, functionName };
}

export function notificationFunctionName(): string {
  return configured?.functionName ?? "unknown";
}

export function notificationConfig(): AppConfig | null {
  return configured?.config ?? null;
}

function numberSetting(config: AppConfig, key: string, fallback: number): number {
  const raw = configSetting(config, key);
  const parsed = Number(raw);
  return raw !== "" && Number.isFinite(parsed) ? parsed : fallback;
}

export function notificationSettings(config: AppConfig) {
  return {
    dailyCap: numberSetting(config, "notif_daily_cap", 2),
    minGapMinutes: numberSetting(config, "notif_min_gap_minutes", 180),
    quietStart: numberSetting(config, "notif_quiet_start_ist", 22),
    quietEnd: numberSetting(config, "notif_quiet_end_ist", 8),
    minAppBuild: numberSetting(config, "notif_min_app_build", 0),
    midCancelMaxAgeMinutes: numberSetting(config, "notif_mid_cancel_max_age_minutes", 180),
  };
}

export function campaignEnabled(config: AppConfig, key: CampaignKey): boolean {
  return configFlag(config, "notifications_enabled") && configFlag(config, campaignFlagKey(key));
}

// ---------------------------------------------------------------- enqueue

export interface EnqueueInput {
  userId: string;
  campaign: CampaignKey;
  dedupeKey: string;
  params?: Record<string, unknown>;
  trigger: NotificationRow["trigger"];
  scheduledFor?: Date | string;
  expiresAt: Date | string;
}

/** The new row's id, or null when this occurrence was already enqueued (or the insert failed). */
export async function enqueue(db: Db, input: EnqueueInput): Promise<string | null> {
  const campaign = CAMPAIGNS[input.campaign];
  const iso = (value: Date | string) => typeof value === "string" ? value : value.toISOString();

  const { data, error } = await db.from("notifications").upsert({
    user_id: input.userId,
    campaign: input.campaign,
    dedupe_key: input.dedupeKey.slice(0, 200),
    kind: campaign.kind,
    route: campaign.route,
    params: input.params ?? {},
    trigger: input.trigger,
    scheduled_for: iso(input.scheduledFor ?? new Date()),
    expires_at: iso(input.expiresAt),
  }, { onConflict: "dedupe_key", ignoreDuplicates: true }).select("id");

  if (error) {
    console.error(`notify: enqueue ${input.campaign} failed`, error);
    return null;
  }
  return (data as Array<{ id: string }> | null)?.[0]?.id ?? null;
}

// ---------------------------------------------------------------- resolution

type Resolution = { campaign: CampaignKey; route: PushRoute } | { skip: string };

async function exists(query: PromiseLike<{ count: number | null; error: unknown }>): Promise<boolean | null> {
  const { count, error } = await query;
  if (error) {
    console.error("notify: eligibility query failed", error);
    return null;
  }
  return (count ?? 0) > 0;
}

/**
 * Is this still true, and which variant and route does it take? `null` from a query means "could
 * not tell", which is treated as ineligible: a push we cannot justify is a push we do not send.
 */
async function resolveForSend(
  db: Db,
  row: NotificationRow,
  user: UserRow,
  entitled: boolean,
  config: AppConfig,
): Promise<Resolution> {
  const base = { campaign: row.campaign, route: CAMPAIGNS[row.campaign].route };
  const count = (table: string) => db.from(table).select("id", { count: "exact", head: true });
  const kundaliId = typeof row.params?.kundali_id === "string" ? row.params.kundali_id : null;

  const kundali = async () => {
    if (!kundaliId) return null;
    const { data } = await db.from("kundalis")
      .select("id, status, superseded_at, first_viewed_at, unlock_at, waiting_last_viewed_at, requested_at")
      .eq("id", kundaliId).maybeSingle();
    return data as Record<string, string | null> | null;
  };

  switch (row.campaign) {
    case "mid_cancel": {
      const subscriptionId = String(row.params?.subscription_id ?? "");
      const answered = await exists(count("cancellation_feedback").eq("user_id", user.user_id).eq("subscription_id", subscriptionId));
      const resubscribed = await exists(count("subscriptions").eq("user_id", user.user_id).eq("status", "ACTIVE"));
      if (answered !== false || resubscribed !== false) return { skip: "no_longer_eligible" };
      return base;
    }

    case "billing_issue": {
      const { data } = await db.from("subscriptions").select("status, last_payment_status")
        .eq("subscription_id", String(row.params?.subscription_id ?? "")).maybeSingle();
      // Fixed since: the retry went through, or the mandate is live again with nothing failing.
      if (data?.last_payment_status === "SUCCESS" && data?.status === "ACTIVE") return { skip: "no_longer_eligible" };
      return { campaign: "billing_issue", route: entitled ? "/home" : "/subscribe" };
    }

    case "kundali_ready":
    case "kundali_ready_lapsed": {
      const k = await kundali();
      if (!k || k.superseded_at || k.first_viewed_at || k.status !== "ready") return { skip: "no_longer_eligible" };
      // `/home`, not `/kundali`, and it must stay in step with the registry — see the note on
      // `kundali_ready` there. The lapsed variant is unaffected: `/subscribe` never touches the gate.
      if (entitled) return { campaign: "kundali_ready", route: "/home" };
      return { campaign: "kundali_ready_lapsed", route: "/subscribe" };
    }

    case "kundali_halfway": {
      const k = await kundali();
      if (!k || k.superseded_at || k.status === "failed" || !entitled) return { skip: "no_longer_eligible" };
      const unlock = Date.parse(k.unlock_at ?? "");
      if (!(Date.now() < unlock - 3600_000)) return { skip: "no_longer_eligible" };
      const viewed = k.waiting_last_viewed_at ? Date.parse(k.waiting_last_viewed_at) : 0;
      if (viewed > Date.parse(k.requested_at ?? "") + 30 * 60_000) return { skip: "no_longer_eligible" };
      return base;
    }

    case "kundali_not_opened": {
      const k = await kundali();
      if (!k || k.superseded_at || k.first_viewed_at || k.status !== "ready" || !entitled) return { skip: "no_longer_eligible" };
      return base;
    }

    case "palm_no_face": {
      const face = await exists(count("face_readings").eq("user_id", user.user_id).eq("status", "ready"));
      return entitled && face === false ? base : { skip: "no_longer_eligible" };
    }

    case "reading_no_chat": {
      const chatted = await exists(count("chat_messages").eq("user_id", user.user_id).eq("role", "user"));
      return entitled && chatted === false ? base : { skip: "no_longer_eligible" };
    }

    case "trial_no_reading": {
      if (user.payment_type !== "trial" || !entitled) return { skip: "no_longer_eligible" };
      const since = user.trial_started_at ?? user.creation_time ?? new Date(0).toISOString();
      const palm = await exists(count("palm_readings").eq("user_id", user.user_id).eq("status", "ready").gte("created_at", since));
      const face = await exists(count("face_readings").eq("user_id", user.user_id).eq("status", "ready").gte("created_at", since));
      return palm === false && face === false ? base : { skip: "no_longer_eligible" };
    }

    case "paywall_abandoned":
      return user.payment_type === "none" && !entitled ? base : { skip: "no_longer_eligible" };

    case "onboarding_incomplete":
      return entitled && (!user.name || !user.dob) ? base : { skip: "no_longer_eligible" };

    case "post_charge_no_return": {
      if (!entitled) return { skip: "no_longer_eligible" };
      const hasKundali = await exists(count("kundalis").eq("user_id", user.user_id));
      const kundaliOn = configFlag(config, "kundali_enabled");
      return { campaign: "post_charge_no_return", route: kundaliOn && hasKundali === false ? "/kundali" : "/home" };
    }

    case "winback_paid": {
      const live = await exists(count("subscriptions").eq("user_id", user.user_id).eq("status", "ACTIVE"));
      return !entitled && live === false ? base : { skip: "no_longer_eligible" };
    }

    case "dormant":
      return entitled ? base : { skip: "no_longer_eligible" };
  }
}

// ---------------------------------------------------------------- processing

export type ProcessOutcome = "sent" | "failed" | "skipped" | "deferred" | "retry";

interface ProcessOptions {
  now?: Date;
  /** `send_test`: ignore flags, quiet hours, the cap and eligibility. Tokens and copy still apply. */
  force?: boolean;
}

export async function processRow(db: Db, config: AppConfig, row: NotificationRow, options: ProcessOptions = {}): Promise<ProcessOutcome> {
  const now = options.now ?? new Date();
  const force = options.force ?? false;
  const settings = notificationSettings(config);

  try {
    if (!force && now.getTime() > Date.parse(row.expires_at)) return await skip(db, row, "stale");

    const { data: userRow, error: userError } = await db.from("users")
      .select(USER_COLUMNS)
      .eq("user_id", row.user_id)
      .maybeSingle();
    if (userError || !userRow) return await skip(db, row, "no_user");
    const user: UserRow = asUserRow(userRow);
    const entitled = isEntitled(user, graceHoursFrom(config), now);

    const resolution = force
      ? { campaign: row.campaign, route: CAMPAIGNS[row.campaign].route }
      : await resolveForSend(db, row, user, entitled, config);
    if ("skip" in resolution) return await skip(db, row, resolution.skip);

    const campaign = CAMPAIGNS[resolution.campaign];

    if (!force) {
      if (!campaignEnabled(config, resolution.campaign)) return await skip(db, row, "disabled", resolution.campaign);
      if (campaign.kind === "marketing" && user.push_marketing_opt_out) {
        return await skip(db, row, "opted_out", resolution.campaign);
      }

      if (!campaign.bypassQuietHours) {
        const later = quietHoursDeferral(now, settings.quietStart, settings.quietEnd, Math.floor(Math.random() * 30));
        if (later) return await defer(db, row, later);
      }

      if (campaign.countsTowardCap) {
        const since = new Date(Math.min(istMidnight(now).getTime(), now.getTime() - settings.minGapMinutes * 60_000));
        const { data: recent } = await db.from("notifications").select("sent_at")
          .eq("user_id", row.user_id).eq("status", "sent").in("campaign", CAPPED_CAMPAIGNS as string[])
          .gte("sent_at", since.toISOString()).order("sent_at", { ascending: false }).limit(20);
        const sentTimes = (recent ?? []).map((r) => new Date(r.sent_at as string));
        const later = capDeferral({
          now,
          sentToday: sentTimes.filter((t) => t >= istMidnight(now)).length,
          cap: settings.dailyCap,
          lastSentAt: sentTimes[0] ?? null,
          minGapMinutes: settings.minGapMinutes,
        });
        if (later) {
          return later.getTime() >= Date.parse(row.expires_at)
            ? await skip(db, row, "cap", resolution.campaign)
            : await defer(db, row, later);
        }
      }
    }

    let tokensQuery = db.from("push_tokens")
      .select("token, user_sessions!inner(expires_at)")
      .eq("user_id", row.user_id)
      .eq("notifications_authorized", true)
      .gt("user_sessions.expires_at", now.toISOString());
    if (settings.minAppBuild > 0) tokensQuery = tokensQuery.gte("app_build", settings.minAppBuild);
    const { data: tokenRows, error: tokenError } = await tokensQuery;
    if (tokenError) throw new Error(`token lookup failed: ${tokenError.message}`);
    const tokens = [...new Set((tokenRows ?? []).map((t) => t.token as string))];
    if (tokens.length === 0) return await skip(db, row, "no_token", resolution.campaign);

    const account = serviceAccountFrom(config);
    if (!account) return await fail(db, row, "fcm_not_configured", 0, resolution.campaign);

    const copy = renderCopy(resolution.campaign, resolveLanguage(user.language, config), { name: user.name });
    const data = {
      route: resolution.route,
      campaign: resolution.campaign,
      notification_id: row.id,
      params: JSON.stringify(row.params ?? {}),
    };

    let accessToken = await fcmAccessToken(account);
    let delivered = 0;
    let retryable = false;
    let removed = 0;
    let lastError = "";
    const messageIds: string[] = [];

    for (const token of tokens) {
      const message = { token, title: copy.title, body: copy.body, data, collapseKey: resolution.campaign };
      let result = await sendFcm(account, accessToken, message);
      if (!result.ok && result.action === "reauth") {
        accessToken = await fcmAccessToken(account, { force: true });
        result = await sendFcm(account, accessToken, message);
      }

      if (result.ok) {
        delivered += 1;
        if (result.name) messageIds.push(result.name);
      } else if (result.action === "delete_token") {
        removed += 1;
        await db.from("push_tokens").delete().eq("token", token);
      } else {
        if (result.action === "retry") retryable = true;
        lastError = result.detail;
      }
    }

    if (delivered > 0) {
      await db.from("notifications").update({
        status: "sent",
        campaign: resolution.campaign,
        kind: campaign.kind,
        route: resolution.route,
        language: copy.language,
        title: copy.title,
        body: copy.body,
        tokens_attempted: tokens.length,
        tokens_delivered: delivered,
        fcm_message_ids: messageIds,
        sent_at: now.toISOString(),
        locked_at: null,
        skip_reason: null,
        error: lastError || null,
      }).eq("id", row.id);

      await trackServer({
        event: "Notification Sent",
        distinctId: row.user_id,
        insertId: insertIdFor("ns", row.id),
        properties: {
          campaign: resolution.campaign,
          notification_id: row.id,
          kind: campaign.kind,
          route: resolution.route,
          language: copy.language,
          trigger: row.trigger,
          tokens_attempted: tokens.length,
          tokens_delivered: delivered,
          attempt: row.attempts,
          delay_minutes: Math.round((now.getTime() - Date.parse(row.created_at)) / 60_000),
          payment_type: user.payment_type,
          entitled,
        },
      });
      return "sent";
    }

    if (removed === tokens.length) return await skip(db, row, "no_token", resolution.campaign);

    if (retryable && row.attempts < 3) {
      await db.from("notifications").update({
        status: "queued",
        locked_at: null,
        error: lastError.slice(0, 500),
        scheduled_for: new Date(now.getTime() + 5 * 60_000 * row.attempts).toISOString(),
      }).eq("id", row.id);
      return "retry";
    }

    return await fail(db, row, lastError || "send_failed", tokens.length, resolution.campaign);
  } catch (error) {
    console.error(`notify ${row.id} (${row.campaign}) failed`, error);
    return await fail(db, row, String(error), 0, row.campaign).catch(() => "failed" as const);
  }
}

async function skip(db: Db, row: NotificationRow, reason: string, campaign: CampaignKey = row.campaign): Promise<ProcessOutcome> {
  await db.from("notifications").update({ status: "skipped", skip_reason: reason, locked_at: null, campaign })
    .eq("id", row.id);
  await trackServer({
    event: "Notification Skipped",
    distinctId: row.user_id,
    insertId: insertIdFor("nk", row.id),
    properties: { campaign, notification_id: row.id, skip_reason: reason, trigger: row.trigger },
  });
  return "skipped";
}

async function defer(db: Db, row: NotificationRow, until: Date): Promise<ProcessOutcome> {
  // A deferral is not an attempt: the claim counted one, so it is handed back.
  await db.from("notifications").update({
    status: "queued",
    locked_at: null,
    scheduled_for: until.toISOString(),
    attempts: Math.max(0, row.attempts - 1),
  }).eq("id", row.id);
  return "deferred";
}

async function fail(db: Db, row: NotificationRow, detail: string, tokens: number, campaign: CampaignKey): Promise<ProcessOutcome> {
  await db.from("notifications").update({ status: "failed", error: detail.slice(0, 500), locked_at: null, campaign })
    .eq("id", row.id);
  await trackServer({
    event: "Notification Failed",
    distinctId: row.user_id,
    insertId: insertIdFor("nf", row.id),
    properties: {
      campaign,
      notification_id: row.id,
      error_code: detail.slice(0, 80),
      tokens_attempted: tokens,
      attempt: row.attempts,
      trigger: row.trigger,
    },
  });
  return "failed";
}

// ---------------------------------------------------------------- batches and the inline path

/** Sends whatever is due until nothing is or [deadline] passes. */
export async function sendDue(db: Db, config: AppConfig, deadline: number): Promise<Record<ProcessOutcome, number>> {
  const tally: Record<ProcessOutcome, number> = { sent: 0, failed: 0, skipped: 0, deferred: 0, retry: 0 };

  while (Date.now() < deadline) {
    const { data, error } = await db.rpc("claim_due_notifications", { p_limit: 25, p_stale_minutes: 10 });
    if (error) {
      console.error("notify: claim failed", error);
      break;
    }
    const rows = (Array.isArray(data) ? data : []) as NotificationRow[];
    if (rows.length === 0) break;

    const started = new Set<string>();
    await eachBounded(rows, { concurrency: 5, deadline }, async (row) => {
      started.add(row.id);
      tally[await processRow(db, config, row)] += 1;
    });

    const unstarted = rows.filter((row) => !started.has(row.id));
    for (const row of unstarted) {
      await db.from("notifications").update({ status: "queued", locked_at: null, attempts: Math.max(0, row.attempts - 1) })
        .eq("id", row.id);
    }
    if (unstarted.length > 0) break;
  }

  return tally;
}

/**
 * Enqueue and send straight away, off the caller's response path. For the moments that cannot wait
 * five minutes for the dispatcher: a cancellation that just happened.
 */
export function notifyNow(db: Db, input: Omit<EnqueueInput, "trigger">): Promise<void> {
  const config = notificationConfig();
  if (!config || !campaignEnabled(config, input.campaign)) return Promise.resolve();

  return inBackground(`notify ${input.campaign}`, (async () => {
    const id = await enqueue(db, { ...input, trigger: "inline" });
    if (!id) return;
    const { data, error } = await db.rpc("claim_notification", { p_id: id });
    if (error) throw error;
    const row = (Array.isArray(data) ? data[0] : data) as NotificationRow | undefined;
    if (row) await processRow(db, config, row);
  })());
}
