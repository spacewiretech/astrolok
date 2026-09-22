import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";

import {
  CAMPAIGN_KEYS,
  CAMPAIGNS,
  capDeferral,
  DRIP_ACTIVE_CAMPAIGNS,
  DRIP_CAMPAIGNS,
  DRIP_ROUTES,
  DRIP_SLOTS,
  dripSlotFor,
  EVENT_CAMPAIGN_KEYS,
  isDripCampaign,
  istHour,
  istMidnight,
  PUSH_ROUTES,
  quietHoursDeferral,
} from "../_shared/notification_campaigns.ts";

/** The production values, from `20260923000001_daily_drip.sql` and NOTIFICATIONS.md. */
const QUIET_START = 22;
const QUIET_END = 8;
const DRIP_GAP_MINUTES = 45;
const DRIP_TOTAL = 6;

/** The UTC instant of a given IST hour on a fixed day. */
const atIst = (hour: number) =>
  new Date(Date.UTC(2026, 8, 23, 0, 0, 0) + Math.round(hour * 60) * 60_000 - 5.5 * 3600_000);

Deno.test("the registry and the slot table agree with each other", () => {
  assertEquals(DRIP_SLOTS.length, 6);
  assertEquals(DRIP_CAMPAIGNS.length, 6);

  for (const { campaign, slot } of DRIP_SLOTS) {
    assert((CAMPAIGN_KEYS as readonly string[]).includes(campaign), `${campaign} is not a campaign`);
    assert(isDripCampaign(campaign));
    assertEquals(dripSlotFor(campaign)?.slot, slot);
    // The SQL derives the config key as `'notif_drip_slot_' || right(p_campaign, -6)`, so the slot
    // name must be exactly the campaign key with `daily_` stripped, or the two read different rows.
    assertEquals(campaign, `daily_${slot}`);
  }

  // The two families partition the keys — nothing in both, nothing in neither.
  assertEquals(EVENT_CAMPAIGN_KEYS.length + DRIP_CAMPAIGNS.length, CAMPAIGN_KEYS.length);
  for (const key of EVENT_CAMPAIGN_KEYS) assertFalse(isDripCampaign(key));

  // The 2-a-day track is a subset of the 6-a-day one, and it is the two bookends.
  assertEquals([...DRIP_ACTIVE_CAMPAIGNS], ["daily_today", "daily_evening"]);
  for (const key of DRIP_ACTIVE_CAMPAIGNS) assert(isDripCampaign(key));
});

Deno.test("every drip campaign is registered the way the drip needs", () => {
  for (const key of DRIP_CAMPAIGNS) {
    const campaign = CAMPAIGNS[key];
    // Marketing, so `push_marketing_opt_out` blocks the whole drip. Nobody is owed a daily push.
    assertEquals(campaign.kind, "marketing", `${key} must be marketing or opt-out cannot stop it`);
    assertEquals(campaign.scheduled, true, `${key} is found by notification_candidates`);
    // Its budget is the schedule. Running it through `capDeferral`'s ceiling as well would only ever
    // push a slot past the hour it was written for; `notify.ts` applies the per-track total instead.
    assertEquals(campaign.countsTowardCap, false, `${key} must not use notif_daily_cap`);
    // Only `mid_cancel` may wake someone at night, and every slot is inside the waking window anyway.
    assertEquals(campaign.bypassQuietHours, false, `${key} must respect quiet hours`);
    assertEquals(campaign.defaultDelayMinutes, 0, `${key} is scheduled by slot, not by delay`);
  }
});

Deno.test("every slot lands inside the waking window", () => {
  for (const { campaign, hour } of DRIP_SLOTS) {
    assert(hour >= QUIET_END, `${campaign} at ${hour} is before quiet hours end`);
    assert(hour < QUIET_START, `${campaign} at ${hour} is after quiet hours start`);

    // The real check: `quietHoursDeferral` must not move it. A "what does today hold" deferred to
    // tomorrow morning is a lie, and the drip has no `bypassQuietHours` escape.
    const at = atIst(hour);
    assertEquals(istHour(at), hour, `atIst is wrong for ${hour}`);
    assertEquals(
      quietHoursDeferral(at, QUIET_START, QUIET_END, 30),
      null,
      `${campaign} at ${hour} IST would be deferred`,
    );
  }
});

Deno.test("slots are far enough apart that the drip never defers itself", () => {
  const hours = DRIP_SLOTS.map((s) => s.hour);
  for (let i = 1; i < hours.length; i++) {
    const gap = (hours[i] - hours[i - 1]) * 60;
    assert(gap > 0, "slots must be in order");
    assert(gap >= DRIP_GAP_MINUTES, `${hours[i - 1]}→${hours[i]} is ${gap}min, under the ${DRIP_GAP_MINUTES}min gap`);
  }

  // Walk a whole day: six sends, none of them deferred by their own ceiling or their own gap.
  const sent: Date[] = [];
  for (const { campaign, hour } of DRIP_SLOTS) {
    const now = atIst(hour);
    const later = capDeferral({
      now,
      sentToday: sent.filter((t) => t >= istMidnight(now)).length,
      cap: DRIP_TOTAL,
      lastSentAt: sent.at(-1) ?? null,
      minGapMinutes: DRIP_GAP_MINUTES,
    });
    assertEquals(later, null, `${campaign} would be deferred after ${sent.length} sends today`);
    sent.push(now);
  }
  assertEquals(sent.length, DRIP_TOTAL, "six slots is the whole day's allowance");
});

Deno.test("the seventh push of the day is the one that yields", () => {
  // An event campaign firing earlier spends one of the six, so the last slot is the one that gives
  // way. That is the point of the asymmetry: six is a ceiling, not an average.
  const now = atIst(20);
  const alreadySent = DRIP_SLOTS.map((s) => atIst(s.hour)).slice(0, 6);
  const later = capDeferral({
    now,
    sentToday: alreadySent.length,
    cap: DRIP_TOTAL,
    lastSentAt: alreadySent.at(-1) ?? null,
    minGapMinutes: DRIP_GAP_MINUTES,
  });
  assert(later, "a seventh push in one IST day must be deferred");
  // And it is deferred past its own expiry (slot + 2h), so `processRow` skips it 'cap' rather than
  // letting it arrive tomorrow with yesterday's colour in it.
  assert(later.getTime() > atIst(20).getTime() + 2 * 3600_000, "deferral must outlive the row");
});

Deno.test("every route the drip can take is one the app allows", () => {
  for (const [slot, states] of Object.entries(DRIP_ROUTES)) {
    for (const [state, route] of Object.entries(states)) {
      assert((PUSH_ROUTES as readonly string[]).includes(route), `${slot}/${state} → ${route} is not a push route`);
    }
    // A non-entitled reader can only open the paywall; `resolvePushNavigation` bounces the rest.
    assertEquals(states.locked, "/subscribe", `${slot} must send a locked reader to the paywall`);
  }

  // Only the kundali slot's `new` state may use `/kundali`, and only because its reader has no chart
  // for `KundaliGateView` to lose. Everything else that touches the gate goes through chat.
  for (const [slot, states] of Object.entries(DRIP_ROUTES)) {
    for (const [state, route] of Object.entries(states)) {
      if (route === "/kundali") assertEquals([slot, state], ["kundali", "new"]);
    }
  }
});

Deno.test("the slot fallbacks match what the migration seeds", () => {
  // `notification_candidates` carries these same numbers in its `case p_campaign` block, as the
  // fallback when `notif_drip_slot_<slot>` is missing or unparseable. If the two ever disagree, a
  // deployment with no config rows sends at different times than the tests say.
  assertEquals(
    DRIP_SLOTS.map(({ campaign, hour }) => `${campaign}=${hour}`),
    [
      "daily_today=8",
      "daily_palm=10.5",
      "daily_kundali=13",
      "daily_face=15.5",
      "daily_chat=18",
      "daily_evening=20",
    ],
  );
});
