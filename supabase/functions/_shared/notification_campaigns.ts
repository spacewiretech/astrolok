/**
 * Every push this app can send, and the rules of time that apply to all of them.
 *
 * Pure. The registry says what each campaign is — which screen it opens, whether it is a
 * transactional message or a marketing one, whether it may wake someone at night — and the helpers
 * below turn "now" into "send now" or "send at". `notify.ts` does the I/O; the SQL in
 * `20260917000002_notifications.sql` finds who qualifies for the scheduled ones.
 *
 * The route allowlist here must match `kPushRoutes` in the app's `push_payload.dart`. A route the app
 * does not recognise is dropped on tap, so a mismatch fails safe — but silently.
 */

export const PUSH_ROUTES = [
  "/home",
  "/palm",
  "/face",
  "/chat",
  "/kundali",
  "/subscribe",
  "/birth",
  "/leaving",
  "/profile",
] as const;
export type PushRoute = typeof PUSH_ROUTES[number];

export const CAMPAIGN_KEYS = [
  "mid_cancel",
  "billing_issue",
  "kundali_ready",
  "kundali_ready_lapsed",
  "kundali_halfway",
  "kundali_not_opened",
  "palm_no_face",
  "reading_no_chat",
  "trial_no_reading",
  "paywall_abandoned",
  "onboarding_incomplete",
  "post_charge_no_return",
  "winback_paid",
  "dormant",
] as const;
export type CampaignKey = typeof CAMPAIGN_KEYS[number];

export type CampaignKind = "transactional" | "marketing";

export interface Campaign {
  /**
   * Transactional: about something the user did or is owed — their kundali, their payment. Sent
   * even to accounts that turned marketing pushes off. Marketing: everything else.
   */
  kind: CampaignKind;
  /** Where a tap goes, unless `notify.ts` decides otherwise at send time (billing, lapsed kundali). */
  route: PushRoute;
  /** Found by `notification-dispatch` through `notification_candidates`. False: enqueued inline. */
  scheduled: boolean;
  /** Only the cancellation reason: it is worth nothing tomorrow morning. */
  bypassQuietHours: boolean;
  /** Counts toward `notif_daily_cap` and `notif_min_gap_minutes`. */
  countsTowardCap: boolean;
  /** Minutes after the trigger, for the segments that wait (`notif_<key>_delay_minutes`). */
  defaultDelayMinutes: number;
}

export const CAMPAIGNS: Record<CampaignKey, Campaign> = {
  mid_cancel: { kind: "transactional", route: "/leaving", scheduled: false, bypassQuietHours: true, countsTowardCap: false, defaultDelayMinutes: 0 },
  billing_issue: { kind: "transactional", route: "/home", scheduled: false, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 0 },
  kundali_ready: { kind: "transactional", route: "/kundali", scheduled: true, bypassQuietHours: false, countsTowardCap: false, defaultDelayMinutes: 0 },
  // A variant of `kundali_ready`, chosen at send time for an account whose plan lapsed. Never enqueued
  // under its own name, which is why it is not `scheduled`.
  kundali_ready_lapsed: { kind: "marketing", route: "/subscribe", scheduled: false, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 0 },
  kundali_halfway: { kind: "marketing", route: "/kundali", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 0 },
  kundali_not_opened: { kind: "marketing", route: "/kundali", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 0 },
  palm_no_face: { kind: "marketing", route: "/face", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 120 },
  reading_no_chat: { kind: "marketing", route: "/chat", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 180 },
  trial_no_reading: { kind: "marketing", route: "/palm", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 180 },
  paywall_abandoned: { kind: "marketing", route: "/subscribe", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 30 },
  onboarding_incomplete: { kind: "transactional", route: "/birth", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 20 },
  post_charge_no_return: { kind: "marketing", route: "/home", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 0 },
  winback_paid: { kind: "marketing", route: "/subscribe", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 0 },
  dormant: { kind: "marketing", route: "/chat", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 0 },
};

export const SCHEDULED_CAMPAIGNS: readonly CampaignKey[] = CAMPAIGN_KEYS.filter((key) => CAMPAIGNS[key].scheduled);
export const CAPPED_CAMPAIGNS: readonly CampaignKey[] = CAMPAIGN_KEYS.filter((key) => CAMPAIGNS[key].countsTowardCap);

export function isCampaignKey(value: unknown): value is CampaignKey {
  return typeof value === "string" && (CAMPAIGN_KEYS as readonly string[]).includes(value);
}

export function isPushRoute(value: unknown): value is PushRoute {
  return typeof value === "string" && (PUSH_ROUTES as readonly string[]).includes(value);
}

export function campaignFlagKey(key: CampaignKey): string {
  return `notif_${key}_enabled`;
}

export function campaignDelayKey(key: CampaignKey): string {
  return `notif_${key}_delay_minutes`;
}

// ---------------------------------------------------------------- IST

const IST_OFFSET_MS = 5.5 * 3600_000;
const DAY_MS = 86_400_000;

/** `YYYY-MM-DD` of the IST calendar day [now] falls on. */
export function istDate(now: Date): string {
  return new Date(now.getTime() + IST_OFFSET_MS).toISOString().slice(0, 10);
}

/** The UTC instant IST midnight fell at, starting the IST day [now] is in. */
export function istMidnight(now: Date): Date {
  const shifted = now.getTime() + IST_OFFSET_MS;
  return new Date(Math.floor(shifted / DAY_MS) * DAY_MS - IST_OFFSET_MS);
}

/** Hours since IST midnight, fractional. */
export function istHour(now: Date): number {
  return (now.getTime() - istMidnight(now).getTime()) / 3600_000;
}

/**
 * When a push that would land in quiet hours should go instead, or null when it can go now.
 *
 * [startHour]–[endHour] in IST, wrapping midnight when start is later than end (22 → 8). Equal
 * hours mean no quiet hours at all. [jitterMinutes] spreads the morning, so a night's backlog does
 * not arrive on every phone at 08:00:00.
 */
export function quietHoursDeferral(now: Date, startHour: number, endHour: number, jitterMinutes = 0): Date | null {
  if (!Number.isFinite(startHour) || !Number.isFinite(endHour) || startHour === endHour) return null;

  const hour = istHour(now);
  const quiet = startHour > endHour ? (hour >= startHour || hour < endHour) : (hour >= startHour && hour < endHour);
  if (!quiet) return null;

  let resume = istMidnight(now).getTime() + endHour * 3600_000;
  if (resume <= now.getTime()) resume += DAY_MS;
  return new Date(resume + Math.max(0, jitterMinutes) * 60_000);
}

/**
 * When a capped push should go instead, or null when neither the daily cap nor the minimum gap
 * stands in its way. A full day waits for the next IST day; quiet hours are applied after this.
 */
export function capDeferral(
  { now, sentToday, cap, lastSentAt, minGapMinutes }: {
    now: Date;
    sentToday: number;
    cap: number;
    lastSentAt: Date | null;
    minGapMinutes: number;
  },
): Date | null {
  if (cap > 0 && sentToday >= cap) return new Date(istMidnight(now).getTime() + DAY_MS);
  if (lastSentAt && minGapMinutes > 0) {
    const ready = lastSentAt.getTime() + minGapMinutes * 60_000;
    if (ready > now.getTime()) return new Date(ready);
  }
  return null;
}

/**
 * A Mixpanel `$insert_id` for a notification: a two-letter prefix and the row's uuid without dashes.
 * 35 characters — inside the 36 Mixpanel deduplicates on, so it is never hashed and stays readable.
 */
export function insertIdFor(prefix: string, id: string): string {
  return `${prefix.slice(0, 2)}:${id.replace(/-/g, "")}`;
}
