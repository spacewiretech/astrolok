# Push Notifications

Every push Astrolok can send: what fires it, who qualifies, when it actually lands, and where a tap goes.

Source of truth, if this doc and the code ever disagree:

| What | Where |
| --- | --- |
| Campaign registry (route, kind, cap, quiet hours) | [notification_campaigns.ts](supabase/functions/_shared/notification_campaigns.ts) |
| Who qualifies (scheduled campaigns) | [20260917000002_notifications.sql](supabase/migrations/20260917000002_notifications.sql) — `notification_candidates` |
| Send-time re-check, gating, delivery | [notify.ts](supabase/functions/_shared/notify.ts) |
| The two inline triggers | [notification_triggers.ts](supabase/functions/_shared/notification_triggers.ts) |
| Copy, 7 languages | [notification_copy.ts](supabase/functions/_shared/notification_copy.ts) |
| Where a tap goes | [push_navigation.dart](lib/app/push_navigation.dart) |

---

## How a push gets sent

There are two ways a notification is created.

**Inline** — `mid_cancel` and `billing_issue` only. Raised the moment the subscription sync sees the transition, from whichever function observed it (`cashfree-webhook`, `subscription-reconcile`, or `subscription-cancel`). These cannot wait: the average trial cancellation happens 1.7 hours in, and the ask has to land while the phone is still in hand. The hooks never throw and never delay the caller.

**Scheduled** — everything else. `pg_cron` calls `notification-dispatch` every 5 minutes (`1-59/5 * * * *`), authenticated with `x-cron-secret`. It runs `notification_candidates` per enabled campaign, enqueues up to 200 rows each, then sends whatever is due.

Either way the row lands in `public.notifications` and goes through the same send path.

### Every push must clear all of this

Checked in order, at send time, against the live account — not against whatever was true when the row was enqueued.

1. **`notifications_enabled`** — master switch. Off means nothing is even looked for.
2. **`notif_<campaign>_enabled`** — per-campaign switch.
3. **Not expired** — each campaign sets its own `expires_at`. Past it, the row is skipped `stale` rather than sent late.
4. **Still eligible** — the full condition is re-run against the live account (`resolveForSend`). Cancelled since? Read their face already? Opened the kundali? Skipped `no_longer_eligible`.
5. **Entitlement** — decided by the same `isEntitled` every other function uses. Most campaigns require it; the win-back ones require the opposite.
6. **Marketing opt-out** — `users.push_marketing_opt_out` blocks every `marketing` campaign. Transactional ones still go.
7. **Quiet hours** — 22:00–08:00 IST (`notif_quiet_start_ist` / `notif_quiet_end_ist`). Deferred to morning, plus a random 0–30 min jitter so a night's backlog doesn't hit every phone at 08:00:00. **`mid_cancel` is the only campaign that ignores this.**
8. **Daily cap** — 2 per IST day (`notif_daily_cap`), minimum 180 minutes apart (`notif_min_gap_minutes`). Over cap, the row is deferred to the next IST day — or skipped `cap` if it would expire before then. `mid_cancel` and `kundali_ready` don't count toward it.
9. **A device that can show it** — an authorized push token, on a live session, from build ≥ `notif_min_app_build` (currently **9**). No such device → skipped `no_token`.

**Deduplication** is by `dedupe_key`, unique per notification. The webhook, the hourly reconcile and the app's status poll can all observe the same cancellation; the key makes that one push. Every campaign's window is bounded to at most a week, which is what stops the 180-day purge of `notifications` from ever letting a once-only key fire twice.

---

## The 14 campaigns

`T` = transactional (sent even to accounts that turned marketing pushes off). `M` = marketing.

| Campaign | | Fires when | Delay | Tap opens |
| --- | --- | --- | --- | --- |
| `mid_cancel` | T | User cancels their mandate | instant | `/leaving` |
| `billing_issue` | T | Autopay fails, or mandate goes on hold | instant | `/home` or `/subscribe` |
| `kundali_ready` | T | Kundali unlocks, unopened | — | `/home` ⚠️ |
| `kundali_ready_lapsed` | M | As above, but plan lapsed | — | `/subscribe` |
| `kundali_halfway` | M | Halfway through the 24h wait | — | `/home` ⚠️ |
| `kundali_not_opened` | M | Revealed 24h ago, still unopened | — | `/home` ⚠️ |
| `palm_no_face` | M | Read their palm, never their face | 120 min | `/face` |
| `reading_no_chat` | M | A reading, but no question to Astro | 180 min | `/chat` |
| `trial_no_reading` | M | Hours into a trial, nothing read | 180 min | `/palm` |
| `paywall_abandoned` | M | Reached the paywall, never started | 30 min | `/subscribe` |
| `onboarding_incomplete` | T | Paid, never gave name + birth date | 20 min | `/birth` |
| `post_charge_no_return` | M | Charged full price, hasn't returned | — | `/kundali` or `/home` |
| `winback_paid` | M | Paid subscriber whose plan just ended | — | `/subscribe` |
| `dormant` | M | Entitled and away 3 days | — | `/chat` |

Delays are configurable per campaign as `notif_<campaign>_delay_minutes`.

---

### `mid_cancel` — transactional, `/leaving`

> **Sorry to see you go, {name}**
> Tell us in one tap what didn't work for you. It helps us make Astrolok better.

**Fires:** inline, the minute a mandate goes to a cancelled status from a non-cancelled one, *and* the cancellation was the user's own — either `CUSTOMER_CANCELLED` (cancelled from their UPI app) or a cancel through our own `subscription-cancel` endpoint. A plain `CANCELLED` from our housekeeping (duplicate or stale mandate) never asks: the user didn't choose to leave.

When the hourly reconcile is what spots it, it only asks if the mandate was last seen live within `notif_mid_cancel_max_age_minutes` (180) — otherwise the cancellation is too old to ask about.

**Skipped at send if:** they've already answered for that subscription, or they've resubscribed.

**Special:** the only campaign that **bypasses quiet hours**, and it doesn't count toward the daily cap. Expires after **6 hours** — it's worth nothing the next morning.

---

### `billing_issue` — transactional, `/home` (or `/subscribe`)

> **Your plan needs attention**
> Your last autopay didn't go through. Fix it now to keep your readings and chat.

**Fires:** inline, on either of two transitions — a recurring debit seen failing for the first time (not a redelivery of a known failure), or a mandate moving to `ON_HOLD`. Access usually still has days to run, which is exactly the window a nudge can save.

**Skipped at send if:** it's fixed — the retry went through *and* the mandate is live again.

**Route depends on the account:** still entitled → `/home`; already lost access → `/subscribe`.

Deduped per subscription **per IST day**, so a mandate failing repeatedly asks once a day, not once an hour. Expires after 2 days.

---

### `kundali_ready` — transactional, `/home` ⚠️ temporarily

> **✨ Your Kundali is ready**
> {name}, your stars have been mapped. Tap to reveal your birth chart and life insights.

**Fires:** the kundali is `ready`, not superseded, never viewed, and `unlock_at` has passed within the last 3 days. Scheduled at `unlock_at` itself, so it lands the moment the chart unlocks.

**Skipped at send if:** superseded, already viewed, or no longer `ready`.

Doesn't count toward the daily cap. Expires 3 days after unlock.

⚠️ **Routed to `/home` since 2026-09-20**, for the reason given under `kundali_halfway` below. The user lands on Home and opens the reveal from the kundali card — one extra tap, instead of being shown the *form* whenever the gate's status call doesn't come back. Note this campaign's route is **hardcoded in `notify.ts`** (`resolveForSend`) as well as set in the registry; both have to agree.

### `kundali_ready_lapsed` — marketing, `/subscribe`

> **✨ Your Kundali is ready**
> Your birth chart is waiting for you. Renew your plan to reveal it.

Not a campaign of its own — it's `kundali_ready` **chosen at send time** when the account has lapsed. Same trigger, different copy, and the tap goes to the paywall instead of the chart. This is why `notif_kundali_ready_enabled` *or* `notif_kundali_ready_lapsed_enabled` being on makes the dispatcher look for candidates.

### `kundali_halfway` — marketing, `/home` ⚠️ temporarily

> **Your Kundali is halfway there 🪔**
> The planets are settling into place. Your birth chart will be revealed soon. Take a peek.

**Fires:** past the midpoint between `requested_at` and `unlock_at`, at least 2 hours before unlock, and they haven't come back to the waiting screen (`waiting_last_viewed_at` is null or within 30 min of requesting). Expires 1 hour before unlock.

⚠️ **Routed to `/home` instead of `/kundali` since 2026-09-20.** `/kundali` opens `KundaliGateView`, which shows the kundali **form** whenever the status call doesn't come back — it cannot tell "this account has no kundali" from "I could not find out", both being a null `KundaliSummary?`. This campaign only selects people who haven't returned to the waiting screen, so every recipient cold-starts the app with the session still resolving, which is exactly when that answer goes missing. They were being offered a re-cast of the chart they were waiting on, which would spend a regeneration.

The app-side fix (a `KundaliRefresh` outcome of found/none/unknown) needs a Play Store release. This route change did not — the route travels in the payload and `/home` is already in `kPushRoutes` on the shipped build. Home shows the same countdown on the kundali card, and tapping it reaches the waiting screen with a summary already in hand.

**Put it back to `/kundali`** once a build that distinguishes the two nulls is live.

### `kundali_not_opened` — marketing, `/home` ⚠️ temporarily

> **Your Kundali is still waiting 🔮**
> {name}, your birth chart and life insights are ready. Don't miss what your stars say.

**Fires:** revealed 24h–7d ago, `ready`, never opened. Expires after 2 days.

⚠️ **Routed to `/home` since 2026-09-20**, same reason as the two above.

---

### `palm_no_face` — marketing, `/face`

> **Your face tells a story too**
> You've read your palm. Now see what your face reveals about you.

**Fires:** 120 minutes after their **first** palm reading (within the last 7 days), with no successful face reading on the account. Closes the 594 → 308 drop in the funnel. Expires after 2 days.

### `reading_no_chat` — marketing, `/chat`

> **A question about your reading?**
> Ask Astro anything about love, career or the months ahead.

**Fires:** 180 minutes after their first reading of either kind (within the last 7 days), with no user message ever sent to chat. Closes 308 → 219. Expires after 2 days.

### `trial_no_reading` — marketing, `/palm`

> **Your first reading is waiting 🖐️**
> Your plan includes a palm and a face reading. See what your hand says in 30 seconds.

**Fires:** 180 minutes into a trial started in the last 2 days, with more than 2 hours still left on it, and nothing read since the trial began. Expires 1 hour before the trial ends.

---

### `paywall_abandoned` — marketing, `/subscribe`

> **Your stars are waiting, {name}**
> Start your trial today and unlock palm reading, face reading and chat with Astro.

**Fires:** 30 minutes after signup for an account that picked a language, reached the paywall, and never started anything (`payment_type = 'none'`). Only within the first 24 hours — after that it expires. Targets the 21% paywall bounce.

### `onboarding_incomplete` — transactional, `/birth`

> **Just one step left 🙏**
> Add your birth date to unlock your personal readings.

**Fires:** 20 minutes after payment for an account still missing a name or a date of birth — so Home never opened for them. Window is 3 days; expires after 2.

Transactional, because they've paid and are owed the thing they paid for.

### `post_charge_no_return` — marketing, `/kundali` or `/home`

> **Your readings are waiting**
> Your plan is active. Explore your Kundali, palm reading and chat with Astro today.

**Fires:** 24–72 hours after their first successful **recurring** charge (the real money, after the trial), with no session since that charge. Targets the 48% who don't come back after converting.

**Route is chosen at send time:** if Kundali is on and they've never requested one → `/kundali`, otherwise `/home`.

### `winback_paid` — marketing, `/subscribe`

> **We miss you, {name}**
> Your stars have moved since we last met. Come back and see what's new for you.

**Fires:** paid time ran out 1–3 days ago, on an account that had at least one successful recurring charge (so: a real subscriber, not a trial that lapsed) and has no active mandate now. Targets the 28% post-conversion churn. Deduped per `current_period_end` date, so a re-lapse later asks again.

### `dormant` — marketing, `/chat`

> **What does this week hold?**
> {name}, ask Astro what the stars say about your week.

**Fires:** entitled, last seen 3–30 days ago. **Hard-limited to once a week** — the SQL excludes anyone who got a `dormant` push in the last 7 days, on top of the normal daily cap.

---

## What happens when a user taps

The push carries `route`, `campaign`, `notification_id` and `params` as data. On tap, [push_navigation.dart](lib/app/push_navigation.dart) decides where to go **before anything navigates** — a push that launched the app waits for the splash to resolve the session first, so it doesn't race the splash and lose.

The rules, in order:

1. **Route not in the allowlist, or nobody signed in** → nothing happens. Dropped as `unknown_route` / `signed_out`.
2. **`/leaving`** → always opens, even for a lapsed account — the person it asks has usually just lost access. Carries `?nid=<notification_id>` so the feedback screen knows which push it came from.
3. **`/subscribe`** → paywall, but only if they aren't entitled. If they already subscribed since, they land on Home instead (`already_entitled`).
4. **`/birth`** → only while onboarding still wants birth details. Otherwise they go wherever onboarding actually is (`no_longer_needed`).
5. **`/home`** → wherever onboarding says they belong.
6. **`/palm`, `/face`, `/chat`, `/kundali`, `/profile`** → these sit behind the entitlement gate. Onboarding must be finished, and they open **on top of Home**, so back lands on Home rather than closing the app. If onboarding isn't done, they go there instead.

Every tap is tracked as `Push Routed`, including the drop reason when it didn't go where it pointed.

**The route allowlist in `notification_campaigns.ts` must match `kPushRoutes` in [push_payload.dart](lib/data/firebase/push_payload.dart).** A route the app doesn't recognise is dropped on tap — so a mismatch fails safe, but silently.

**If the app is already open**, the OS shows nothing. [push_banner.dart](lib/widgets/push_banner.dart) shows an in-app banner instead, and tapping that runs the same routing.

---

## Operating it

Config lives in `app_config`. Current production values:

| Key | Value |
| --- | --- |
| `notifications_enabled` | `true` |
| `notif_min_app_build` | `9` |
| `notif_daily_cap` | `2` |
| `notif_min_gap_minutes` | `180` |
| `notif_quiet_start_ist` / `notif_quiet_end_ist` | `22` / `8` |
| `notif_mid_cancel_max_age_minutes` | `180` |
| every `notif_<campaign>_enabled` | `true` (all 13 flipped on 2026-09-18) |

There is a helper for all of this at [supabase/scripts/push.sh](supabase/scripts/push.sh):

```bash
export CRON_SECRET='…'                                   # app_config.reconcile_secret

./push.sh dry                                            # who would get what, right now
./push.sh dry dormant
./push.sh send d53877e5-33d0-4fad-bb13-45328e23ee3b      # one real push to one account
./push.sh send <user_id> winback_paid
./push.sh run                                            # run the dispatch without waiting for cron
```

Or by hand — `notification-dispatch` takes two operator actions, both needing `x-cron-secret` (= `reconcile_secret`):

```jsonc
// How many people would get this right now? Sends nothing.
{"action": "dry_run", "campaign": "dormant"}

// Send one to a real phone. Ignores flags, quiet hours, the cap and eligibility —
// the account still needs a device that can show it.
{"action": "send_test", "user_id": "<uuid>", "campaign": "dormant"}
```

Always `dry_run` before switching a campaign on.

### Skip reasons

Every skipped row records why, in `notifications.skip_reason`:

| Reason | Meaning |
| --- | --- |
| `no_token` | No authorized device on a live session at build ≥ `notif_min_app_build` |
| `no_longer_eligible` | The condition stopped being true between enqueue and send |
| `stale` | Sat past `expires_at` |
| `cap` | Over the daily cap, and would expire before the cap resets |
| `opted_out` | Marketing campaign, `push_marketing_opt_out` set |
| `disabled` | Campaign switched off between enqueue and send |
| `no_user` | Account gone |

A large `no_token` count is normal during an app rollout: tokens registered by builds older than the push feature have a null `app_build` and are excluded by design. They backfill as users update, because the app re-registers its token on every cold start.
