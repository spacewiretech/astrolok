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
  // The daily drip. Six fixed slots through the day rather than one push per event, so the app has a
  // reason to be opened on a day when nothing has happened. See `DRIP_SLOTS` below.
  "daily_today",
  "daily_palm",
  "daily_kundali",
  "daily_face",
  "daily_chat",
  "daily_evening",
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
  // Home, not `/kundali`, for the same reason as `kundali_halfway` below: the gate shows the
  // kundali form whenever its status call does not come back, and the reveal push is tapped on a
  // cold start. Home shows the card, which opens the reveal in one more tap. Note `notify.ts`
  // hardcodes this campaign's route at send time, so that has to agree with this.
  kundali_ready: { kind: "transactional", route: "/home", scheduled: true, bypassQuietHours: false, countsTowardCap: false, defaultDelayMinutes: 0 },
  // A variant of `kundali_ready`, chosen at send time for an account whose plan lapsed. Never enqueued
  // under its own name, which is why it is not `scheduled`.
  kundali_ready_lapsed: { kind: "marketing", route: "/subscribe", scheduled: false, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 0 },
  // Home rather than `/kundali`, and deliberately so. `/kundali` opens `KundaliGateView`, which
  // asks the server for the summary and shows the kundali *form* whenever that answer does not
  // arrive — a failed status call and "this account has no kundali" are the same null to it. The
  // halfway reminder only goes to people who have not come back to the waiting screen, so every
  // recipient is cold-starting the app with the session still resolving, which is exactly when
  // that answer goes missing. They were being offered a re-cast of the chart they were waiting on.
  //
  // The app-side fix needs a Play Store release. This does not: the route travels in the push
  // payload and `/home` is already in `kPushRoutes` on the shipped build. Home carries the kundali
  // card with the same countdown, and tapping it reaches the waiting screen with a summary already
  // in hand. Put this back to `/kundali` once the build that tells the two nulls apart is live.
  kundali_halfway: { kind: "marketing", route: "/home", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 0 },
  kundali_not_opened: { kind: "marketing", route: "/home", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 0 },
  palm_no_face: { kind: "marketing", route: "/face", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 120 },
  reading_no_chat: { kind: "marketing", route: "/chat", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 180 },
  trial_no_reading: { kind: "marketing", route: "/palm", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 180 },
  paywall_abandoned: { kind: "marketing", route: "/subscribe", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 30 },
  onboarding_incomplete: { kind: "transactional", route: "/birth", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 20 },
  post_charge_no_return: { kind: "marketing", route: "/home", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 0 },
  winback_paid: { kind: "marketing", route: "/subscribe", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 0 },
  dormant: { kind: "marketing", route: "/chat", scheduled: true, bypassQuietHours: false, countsTowardCap: true, defaultDelayMinutes: 0 },

  // ---- the daily drip ----
  //
  // `countsTowardCap` is false for all six, and not because they are exempt from a budget: their
  // budget is the schedule itself. The SQL emits at most one row per slot per account per IST day,
  // and only the two bookend slots for a paying account, so the count is structural — six a day for
  // everyone else, two for `active`. Running them through `capDeferral` as well would only defer a
  // slot past the hour it was written for.
  //
  // The routes below are defaults. `resolveForSend` picks the real one per row, because a variant
  // that says "read your palm" must open `/palm` while one that says "ask Astro about your palm"
  // must open `/chat` — and neither may be offered to an account that has since lapsed.
  daily_today: { kind: "marketing", route: "/chat", scheduled: true, bypassQuietHours: false, countsTowardCap: false, defaultDelayMinutes: 0 },
  daily_palm: { kind: "marketing", route: "/palm", scheduled: true, bypassQuietHours: false, countsTowardCap: false, defaultDelayMinutes: 0 },
  // `/kundali` is safe here where it is not for the three reveal campaigns. `KundaliGateView` shows
  // the kundali *form* whenever its status call does not come back — and this campaign's `new`
  // variant only goes to accounts that have never cast one, for whom the form is the right screen.
  // The `ask` variant goes to `/chat` and never touches the gate.
  daily_kundali: { kind: "marketing", route: "/kundali", scheduled: true, bypassQuietHours: false, countsTowardCap: false, defaultDelayMinutes: 0 },
  daily_face: { kind: "marketing", route: "/face", scheduled: true, bypassQuietHours: false, countsTowardCap: false, defaultDelayMinutes: 0 },
  daily_chat: { kind: "marketing", route: "/chat", scheduled: true, bypassQuietHours: false, countsTowardCap: false, defaultDelayMinutes: 0 },
  daily_evening: { kind: "marketing", route: "/chat", scheduled: true, bypassQuietHours: false, countsTowardCap: false, defaultDelayMinutes: 0 },
};

export const SCHEDULED_CAMPAIGNS: readonly CampaignKey[] = CAMPAIGN_KEYS.filter((key) => CAMPAIGNS[key].scheduled);
export const CAPPED_CAMPAIGNS: readonly CampaignKey[] = CAMPAIGN_KEYS.filter((key) => CAMPAIGNS[key].countsTowardCap);

// ---------------------------------------------------------------- the daily drip

/**
 * The six slots, in the order they land, with the IST hour each is written for.
 *
 * Fractional hours are half past. Every one of them sits inside the waking window
 * (`notif_quiet_start_ist` 22 → `notif_quiet_end_ist` 8), so a drip push is never deferred to the
 * morning — which matters, because a "what does today hold" that arrives tomorrow is a lie.
 *
 * The hours are also seeded into `app_config` as `notif_drip_slot_<slot>`, and the SQL reads them
 * from there. These are the fallbacks, and the source of truth for the tests.
 */
export const DRIP_SLOTS = [
  { campaign: "daily_today", slot: "today", hour: 8 },
  { campaign: "daily_palm", slot: "palm", hour: 10.5 },
  { campaign: "daily_kundali", slot: "kundali", hour: 13 },
  { campaign: "daily_face", slot: "face", hour: 15.5 },
  { campaign: "daily_chat", slot: "chat", hour: 18 },
  { campaign: "daily_evening", slot: "evening", hour: 20 },
] as const satisfies ReadonlyArray<{ campaign: CampaignKey; slot: string; hour: number }>;

export type DripSlot = typeof DRIP_SLOTS[number]["slot"];
export type DripCampaignKey = typeof DRIP_SLOTS[number]["campaign"];

/**
 * The fourteen event campaigns: everything that is not a drip slot.
 *
 * The two families keep their copy in different files, because a drip slot has a pool of variants and
 * an event has one sentence. Splitting the key type here is what makes `deno check` insist on that —
 * `COPY` must cover every event campaign and no drip one, and `DRIP_COPY` the other way round.
 */
export type EventCampaignKey = Exclude<CampaignKey, DripCampaignKey>;

export const DRIP_CAMPAIGNS: readonly DripCampaignKey[] = DRIP_SLOTS.map((entry) => entry.campaign);

export const EVENT_CAMPAIGN_KEYS: readonly EventCampaignKey[] = CAMPAIGN_KEYS.filter(
  (key): key is EventCampaignKey => !(DRIP_CAMPAIGNS as readonly string[]).includes(key),
);

/** The two slots a paying account gets. The other four carry `payment_type <> 'active'` in SQL. */
export const DRIP_ACTIVE_CAMPAIGNS: readonly CampaignKey[] = ["daily_today", "daily_evening"];

export function isDripCampaign(key: CampaignKey): boolean {
  return (DRIP_CAMPAIGNS as readonly string[]).includes(key);
}

export function dripSlotFor(key: CampaignKey): typeof DRIP_SLOTS[number] | null {
  return DRIP_SLOTS.find((entry) => entry.campaign === key) ?? null;
}

/** `app_config.notif_drip_slot_<slot>` — the IST hour this slot is written for. */
export function dripSlotHourKey(slot: DripSlot): string {
  return `notif_drip_slot_${slot}`;
}

/**
 * What the reader has already done about this slot's subject, worked out at send time.
 *
 * `new` — never scanned this, never cast this. `ask` — has, so the push points at Astro instead of
 * at the camera. `locked` — not entitled, so every feature route would bounce off the paywall and the
 * push says so honestly rather than promising a reading that is one tap away.
 */
export type DripState = "new" | "ask" | "locked";

/**
 * Where each slot goes, per state. `locked` is `/subscribe` for all six, which is the only route a
 * non-entitled account can actually open — `resolvePushNavigation` bounces the rest.
 *
 * The `ask` states and the three chat-first slots go to `/chat`, carrying the variant's own question
 * in `params.q`. `daily_kundali`'s `new` state is the one campaign that may safely use `/kundali`:
 * the gate's "show the form when the status call does not come back" behaviour is a bug for the three
 * reveal campaigns, whose recipients already own a chart — and exactly the right screen for someone
 * who does not. `resolveDrip` guarantees `new` only reaches accounts with no live kundali.
 */
export const DRIP_ROUTES: Record<DripSlot, Record<DripState, PushRoute>> = {
  today: { new: "/chat", ask: "/chat", locked: "/subscribe" },
  palm: { new: "/palm", ask: "/chat", locked: "/subscribe" },
  kundali: { new: "/kundali", ask: "/chat", locked: "/subscribe" },
  face: { new: "/face", ask: "/chat", locked: "/subscribe" },
  chat: { new: "/chat", ask: "/chat", locked: "/subscribe" },
  evening: { new: "/chat", ask: "/chat", locked: "/subscribe" },
};

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
