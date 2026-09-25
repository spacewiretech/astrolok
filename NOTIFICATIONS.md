# Push Notifications

Every push Astrolok can send: what fires it, who qualifies, when it actually lands, and where a tap goes.

Twenty campaigns in two families. **Fourteen are event-driven** — a kundali unlocks, a mandate fails,
a trial goes unused — and fire when something happens. **Six are the daily drip**, which fires because
it is half past ten. They share one queue, one send path and one set of rules; where they differ, the
drip's section says so.

Source of truth, if this doc and the code ever disagree:

| What | Where |
| --- | --- |
| Campaign registry (route, kind, cap, quiet hours, the drip's slots) | [notification_campaigns.ts](supabase/functions/_shared/notification_campaigns.ts) |
| Who qualifies (scheduled campaigns) | [20260917000002_notifications.sql](supabase/migrations/20260917000002_notifications.sql) — `notification_candidates` |
| Who qualifies (the daily drip) | [20260923000001_daily_drip.sql](supabase/migrations/20260923000001_daily_drip.sql) — the same function, rewritten with six more branches |
| Send-time re-check, gating, delivery | [notify.ts](supabase/functions/_shared/notify.ts) |
| The two inline triggers | [notification_triggers.ts](supabase/functions/_shared/notification_triggers.ts) |
| Copy for the 14 event campaigns, 7 languages | [notification_copy.ts](supabase/functions/_shared/notification_copy.ts) |
| Copy for the drip — 26 variants, 7 languages | [drip_copy.ts](supabase/functions/_shared/drip_copy.ts) |
| Where a tap goes | [push_navigation.dart](lib/app/push_navigation.dart) |

---

## How a push gets sent

There are two ways a notification is created, and the daily drip is a variety of the second.

**Inline** — `mid_cancel` and `billing_issue` only. Raised the moment the subscription sync sees the transition, from whichever function observed it (`cashfree-webhook`, `subscription-reconcile`, or `subscription-cancel`). These cannot wait: the average trial cancellation happens 1.7 hours in, and the ask has to land while the phone is still in hand. The hooks never throw and never delay the caller.

**Scheduled** — everything else, the drip included. `pg_cron` calls `notification-dispatch` every 5 minutes (`1-59/5 * * * *`), authenticated with `x-cron-secret`. It runs `notification_candidates` per enabled campaign, enqueues up to `notif_dispatch_batch` rows a pass and asks again while a pass comes back full, then sends whatever is due.

The 14 event campaigns are triggered by something that happened. The 6 drip slots are triggered by the clock: each has an IST time it is written for, and its branch only returns anybody during the hour before that time. See [The daily drip](#the-daily-drip).

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
8. **Daily cap** — and it is asymmetric, because the drip and the event campaigns are counting different things.

   An **event** row counts itself against the other `countsTowardCap` campaigns: 2 per IST day (`notif_daily_cap`), minimum 180 minutes apart (`notif_min_gap_minutes`). Unchanged since before the drip existed. `mid_cancel` and `kundali_ready` don't count toward it.

   A **drip** row counts itself against *everything* sent that day, and against its own per-track total: `notif_drip_daily_total` (6) for an account whose `payment_type` is not `active`, `notif_drip_daily_total_active` (2) for one that is, with `notif_drip_min_gap_minutes` (45) between it and any other push. That way round on purpose — **the drip is what yields.** If `winback_paid` fires at 09:00 it spends one of the day's six and the last slot is skipped `cap`, so six is a real ceiling and not an average.

   Doing it the other way would have been quiet and bad: `billing_issue` and `onboarding_incomplete` are `countsTowardCap: true`, so if drip sends counted toward *their* cap, a non-active account at six sends would have had "your autopay failed" deferred to the next morning.
9. **A device that can show it** — an authorized push token, on a live session, from build ≥ `notif_min_app_build` (currently **9**). No such device → skipped `no_token`.

**Deduplication** is by `dedupe_key`, unique per notification. The webhook, the hourly reconcile and the app's status poll can all observe the same cancellation; the key makes that one push. Every campaign's window is bounded to at most a week, which is what stops the 180-day purge of `notifications` from ever letting a once-only key fire twice.

---

## The 14 event campaigns

`T` = transactional (sent even to accounts that turned marketing pushes off). `M` = marketing. The six drip slots are all marketing and have [their own section](#the-daily-drip).

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

---

## The daily drip

Six pushes a day to everyone whose `payment_type` is not `active`, two to everyone whose is. The 14
campaigns above all wait for something to happen; most days nothing does, and the app goes unopened.
The drip is the other half — a reason to open it on an ordinary Tuesday.

| Campaign | IST | Theme | `active` | everyone else |
| --- | --- | --- | --- | --- |
| `daily_today` | 08:00 | What today holds, and the colour to wear | ✅ | ✅ |
| `daily_palm` | 10:30 | Read your palm — or ask Astro through it | — | ✅ |
| `daily_kundali` | 13:00 | Cast your chart — or ask Astro about it | — | ✅ |
| `daily_face` | 15:30 | Read your face — or ask Astro through it | — | ✅ |
| `daily_chat` | 18:00 | A question worth asking | — | ✅ |
| `daily_evening` | 20:00 | Tomorrow, and a graha from your own chart | ✅ | ✅ |

**The 2-versus-6 split is structural, not configured.** The four middle branches carry
`payment_type <> 'active'`; the two bookends do not. There is no per-user cap to set wrong. All six
are `countsTowardCap: false` for the same reason — their budget is the schedule.

Every slot is inside the waking window, so `quietHoursDeferral` never moves one. A push that says
"what does today hold" and arrives tomorrow is a lie, and the drip has no `bypassQuietHours` escape.

### One Tuesday, three accounts

The same six branches, the same six slots, producing three quite different days. This is the whole
feature in one table.

**A — in trial.** Entitled, Hinglish, has read their palm, has a ready kundali, has never scanned
their face. Gets all six.

| IST | Slot | State, decided at send | Says | Opens |
| --- | --- | --- | --- | --- |
| 08:00 | `daily_today` | — | "Aaj laal pehniye 💫" (Tuesday is Mangal's) | `/chat` + question |
| 10:30 | `daily_palm` | `ask` — a `ready` palm reading exists | "Aapki hatheli pehle se jaanti hai" | `/chat` + question |
| 13:00 | `daily_kundali` | `ask` — a live chart exists | "Aapki Kundali mein aur bhi hai" | `/chat` + question |
| 15:30 | `daily_face` | `new` — no face reading | "Ek pal ke liye upar dekhiye 👁️" | `/face`, the camera |
| 18:00 | `daily_chat` | — | "Din khatam hone se pehle ek sawaal" | `/chat` + question |
| 20:00 | `daily_evening` | `ask` — the report names a graha | "Aapki kundali mein Shani tez hai" | `/chat` + question |

**B — paying (`payment_type = 'active'`).** Two, not six, and structurally so: the four middle
branches carry `payment_type <> 'active'` and never return this account at all.

| IST | Slot | Says |
| --- | --- | --- |
| 08:00 | `daily_today` | the day and its colour |
| 20:00 | `daily_evening` | tomorrow, named after a graha from their own chart |

**C — never paid (`payment_type = 'none'`).** Six pushes, every one of them `locked`. The app bounces
this account off `/palm`, `/face`, `/chat` and `/kundali`, so all six say something true and go to the
paywall — and two of them give the day's colour away for nothing.

| IST | Slot | Says | Opens |
| --- | --- | --- | --- |
| 08:00 | `daily_today` | one of the six `locked_*` | `/subscribe` |
| 10:30 | `daily_palm` | another, because the slot is in the hash | `/subscribe` |
| … | … | … | `/subscribe` |

What happens for each of those rows, in order: the dispatcher finds the account in the hour before the
slot and writes a row scheduled for the slot itself → at the slot, `processRow` re-reads the live
account, picks the state and the route, renders the copy in their language with today's colour → FCM
→ the row records what was actually sent, variant included.

### When a row is made, and when it dies

A slot's branch returns candidates only during the hour before its time
(`notif_drip_enqueue_window_minutes`), and stamps `scheduled_for` with the slot itself. So the
dispatcher has twelve runs to find everybody, and everybody is sent at 10:30 rather than whenever
they were found.

`expires_at` is the slot **plus two hours**. A missed slot is therefore *lost, not queued*: if the
dispatcher is down at 13:00 the kundali push is skipped `stale`, it does not turn up at 16:00 on top
of the 15:30 one, and tomorrow is not double-loaded. The cost of that choice is that **silence is
what a failure looks like** — so watch the daily counts rather than waiting for an error.

`dedupe_key` is `<campaign>:<user_id>:<YYYYMMDD IST>`, so a slot can fire once per account per day
however many times the dispatcher runs.

### Which of the 26 sentences

Nothing here is generated. Two deterministic steps:

**Which pool** — read live in `resolveDrip` at send time, never at enqueue, because a row made at
09:30 is sent at 10:30 and the answer can change in between.

| Slot | `new` | `ask` |
| --- | --- | --- |
| `palm` | no `palm_readings` row with `status = 'ready'` | has one → `/chat` |
| `face` | no `face_readings` row with `status = 'ready'` | has one → `/chat` |
| `kundali` | no live chart, or one whose cast **failed** | `status = 'ready'` → `/chat` |
| `evening` | no readable report | a report exists → names a graha from it |
| `today`, `chat` | always | — |

A kundali that is `queued` or `generating` skips the 13:00 slot entirely: `kundali_halfway` already
owns that person and is already pushing them, and telling someone their chart is uncast while they
are watching it being cast is worse than one fewer push.

There is a third state, **`locked`**, for an account that is not entitled. It has its own pool of six
and every one of them routes to `/subscribe`. This is not politeness: `resolvePushNavigation` bounces
a non-entitled account off `/palm`, `/face`, `/chat` and `/kundali` onto the paywall, so the other
twenty would be a price tag dressed as a palm reading, four times a day. Two of the six give the day's
lucky colour away for nothing, which is the one thing the app can hand someone who has not paid.

**Which sentence in the pool** — `drip_variant(user_id, now, slot)` in SQL: `md5(user, slot, IST day)`
as a 28-bit integer, which `dripVariantFor` takes modulo the pool. The IST day is in the hash so the
wording rotates daily; the user id is in it so two people do not get the same sentence on the same
morning; the slot is in it so 10:30 and 13:00 shuffle independently. The **pool size lives only in
`drip_copy.ts`** — SQL hands over a raw hash — so a twenty-seventh variant is a TypeScript edit, not
a migration.

### All twenty-six, in English

The other six languages say the same things; `drip_copy.ts` is the source, and `drip_copy_test.ts`
asserts every variant exists in all seven, fits a lock screen (48 graphemes of title, 150 of body),
is written in its own script, and carries a seeded question exactly when its route is `/chat`.

| Campaign | Variant | State | Opens | Title | Body |
| --- | --- | --- | --- | --- | --- |
| `daily_today` | `today_0` | new | /chat | Wear {colour} today 💫 | {name}, {planet} rules this day. Ask Astro what else it has planned for you. |
| `daily_today` | `today_1` | new | /chat | Today belongs to {planet} | {colour} is your colour for luck today. One question, and Astro tells you the rest. |
| `daily_today` | `today_2` | new | /chat | Something shifts today 🌙 | {name}, keep {colour} close. Astro can tell you where the day is pointing. |
| `daily_today` | `today_3` | new | /chat | Your day is already written | {planet} is holding the pen. Wear {colour}, and ask Astro what it says. |
| `daily_palm` | `palm_new_0` | new | /palm | Your hand is a map 🖐️ | {name}, thirty seconds and eight lines. See where yours are taking you. |
| `daily_palm` | `palm_new_1` | new | /palm | Nobody else has your lines | Heart, life, head, fate — and four more. Read them before the day turns. |
| `daily_palm` | `palm_ask_0` | ask | /chat | Your palm already knows | {name}, ask Astro what your hand says about today. |
| `daily_palm` | `palm_ask_1` | ask | /chat | Bring your palm a question | You've had it read. Ask Astro what those lines mean for this week. |
| `daily_kundali` | `kundali_new_0` | new | /kundali | Your chart hasn't been cast | {name}, your birth details are saved. One tap and the planets do the rest. |
| `daily_kundali` | `kundali_new_1` | new | /kundali | Nine planets, one moment 🪐 | The sky at the hour you were born is still up there. See what it wrote. |
| `daily_kundali` | `kundali_ask_0` | ask | /chat | Your Kundali has more to say | {name}, ask Astro what your chart says about right now. |
| `daily_kundali` | `kundali_ask_1` | ask | /chat | Ask your chart a real question | Astro has your birth chart open. Love, money, the year ahead — pick one. |
| `daily_face` | `face_new_0` | new | /face | Your face is keeping secrets | {name}, six features, read the way Samudrika Shastra reads them. |
| `daily_face` | `face_new_1` | new | /face | Look up for a moment 👁️ | Eyes, brow, jaw — your face says what your palm cannot. See what. |
| `daily_face` | `face_ask_0` | ask | /chat | Your face reading isn't finished | {name}, ask Astro what your features say about the days ahead. |
| `daily_face` | `face_ask_1` | ask | /chat | What your face didn't tell you | Astro read it once. Ask what it means for the question you're carrying. |
| `daily_chat` | `chat_0` | new | /chat | One question before the day ends | {name}, love, work or money — Astro answers with your own chart open. |
| `daily_chat` | `chat_1` | new | /chat | Astro is still awake 🌗 | Ask the thing you have been turning over all day. |
| `daily_evening` | `evening_new_0` | new | /chat | Tomorrow is already moving | {name}, the planets shift overnight. Ask Astro what you are walking into. |
| `daily_evening` | `evening_ask_0` | ask | /chat | {planet} is loud in your chart | {name}, ask Astro what it has been quietly arranging for you. |
| *(any slot)* | `locked_0` | locked | /subscribe | Your colour for today 💫 | {name}, wear {colour} — that one is free. Unlock your chart to see the rest. |
| *(any slot)* | `locked_1` | locked | /subscribe | The sky moved last night 🌙 | {planet} owns today. Unlock Astrolok to find out what that means for you. |
| *(any slot)* | `locked_2` | locked | /subscribe | Eight lines, six features, nine planets | Your palm, your face, your chart. Unlock all three and Astro reads them for you. |
| *(any slot)* | `locked_3` | locked | /subscribe | Astro is waiting to meet you | {name}, one plan unlocks your palm, your face, your Kundali and every question. |
| *(any slot)* | `locked_4` | locked | /subscribe | Something is written for you ✨ | It has been since the hour you were born. Unlock your chart and read it. |
| *(any slot)* | `locked_5` | locked | /subscribe | Your stars kept your place | {name}, wear {colour} today. When you're ready, unlock what else is waiting. |

`{name}` is the first word of `users.name`, dropped cleanly when there isn't one. `{colour}` and
`{planet}` come from the weekday table above — except on `evening_ask_0`, where `{planet}` is a graha
out of the reader's own chart.

### The lucky colour

`{colour}` and `{planet}` come from a fixed weekday table in `drip_copy.ts`, computed at send time
from the IST date. No stored state, no model, correct every week for ever.

| Day | Lord | Colour |
| --- | --- | --- |
| Sunday | Sun | orange |
| Monday | Moon | white |
| Tuesday | Mars | red |
| Wednesday | Mercury | green |
| Thursday | Jupiter | yellow |
| Friday | Venus | pink |
| Saturday | Saturn | blue |

The evening `ask` variant overrides `{planet}` with one out of the reader's own
`kundalis.report.highlights`, hash-indexed so it moves day to day. An unknown or missing planet falls
back to the weekday's lord — a stale param costs the personalisation, not the push.

### The seeded question

Every drip variant that opens `/chat` carries the question it wants asked, in `params.q`, **already in
the reader's own language**. It lands in the transcript as their own words, so an English sentence in
a Malayalam thread would be wrong — which is why the `ask` strings are translated in `drip_copy.ts`
alongside the title and body, rather than being built in SQL.

The payload a chat-bound drip push actually carries:

```jsonc
{
  "route": "/chat",
  "campaign": "daily_palm",
  "notification_id": "…",
  "params": "{\"slot\":\"palm\",\"day\":\"20260922\",\"pick\":159207737,
              \"variant\":\"palm_ask_0\",
              \"q\":\"Meri hatheli ki reading aaj mere din ke baare mein kya kehti hai?\",
              \"autosend\":\"1\"}"
}
```

`variant` is written back onto the `notifications` row when it sends, so
`select params->>'variant', count(*)` answers "which of the twenty-six actually works" off the table
that is already being written — no new table, no new event.

**`autosend` decides whether the question is sent or merely written**, and it is
`notif_drip_chat_autosend` — server-side, so it changes from the dashboard with no release:

| | What the reader gets |
| --- | --- |
| `autosend = true` *(current production setting)* | Chat opens and the question is **already asked**, with Astro answering. One tap from a lock screen to a reading. |
| `autosend = false` | The question is written into the composer and waits. Nothing is spent until they press send. |

The trade is real and worth restating before anyone flips it back: auto-sending spends a
`chat_messages_per_day` turn and a Gemini call per push, **and starts a new thread each time** —
`ChatView` always selects the draft before sending. At six slots a day that is ~180 threads a month
in the drawer, and six Gemini calls per user per day that nobody asked for. The app has already had a
full chat outage from depleted Gemini credits. If the drawer becomes unusable, the fix is to reuse
the day's thread rather than draft a new one.

Anything the app does not recognise means "write, do not send": an absent, empty, `"0"`, `"true"` or
`"yes"` value all leave it in the composer. Only an explicit `"1"` sends.

**Builds before 11 ignore `params` entirely and open a blank chat.** That is why the whole server side
ships without moving `notif_min_app_build`, and why there is no rollout cliff.

### Fatigue

Six a day is a lot, and one swipe turns an app's notifications off for ever.

- The drip is all `marketing`, so `push_marketing_opt_out` stops every slot. The branches also filter
  on it in SQL, so an opted-out account is never even enqueued.
- **Dormancy step-down:** no session in `notif_drip_dormant_days` (7) drops an account to the two
  bookend slots. Someone ignoring six a day gets two, not silence. `0` turns it off.
- `notif_drip_languages` is the language gate. All seven are on, but `drip_copy.ts` asks for native
  review of Hindi, Telugu, Tamil, Kannada and Malayalam — narrow this to `english,hinglish` to pilot
  on the two that need none, and widen it as review lands.
- Watch `Notification Sent` → `Push Opened` per campaign, and the count of authorized push tokens.
  A token count that starts falling is the drip being switched off by hand, and it does not come back.

### Turning it off

1. `notif_drip_enabled = false` — one key. SQL stops enqueueing immediately, and anything already
   queued dies `disabled` within the 60-second config cache. **This is the kill switch.**
2. One `notif_daily_<slot>_enabled = false` — drops 6/day to 5/day. This is the dial you will
   actually use; launching at three slots and adding the rest is the recommended way in.
3. `notifications_enabled = false` — everything, all 20 campaigns.

---

## What happens when a user taps

The push carries `route`, `campaign`, `notification_id` and `params` as data. On tap, [push_navigation.dart](lib/app/push_navigation.dart) decides where to go **before anything navigates** — a push that launched the app waits for the session to resolve first, so it doesn't race the splash and lose.

### Waiting for the session, not for the splash

`PushNavigator` buffers a tapped push in `_pending` until `_ready`, and then replays it. **What sets
`_ready` is the session resolving** — `PushNavigator.attach` listens to `splashDestinationProvider`,
the same provider the splash waits on:

```dart
_ref.listen(splashDestinationProvider, (_, next) {
  if (next.valueOrNull == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) => onSplashResolved());
}, fireImmediately: true);
```

`SplashView` also calls `onSplashResolved()` when it routes, which is the usual path;
`onSplashResolved` is idempotent, so whichever gets there first wins.
/
⚠️ **This is load-bearing, and it was a real bug until 2026-09-22.** `_ready` used to be set *only*
by `SplashView`. Android can restore a cold start straight onto the route the app was last on — so
the splash never builds, nothing ever calls `onSplashResolved`, and **every push tapped for the rest
of that session sits in `_pending` and is never handled.** It hit all fourteen event campaigns, not
just the drip, and it is almost invisible from the outside: the notification opens the right-looking
screen and does nothing, because the screen is the *restored* route and the push was dropped on the
floor. If a push ever "opens the app but does nothing" again, check `_ready` first.

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

### Carrying the question to the chat screen

A chat-bound drip push hands `ChatView` a `ChatLaunch` — the question, where it came from, and
whether to send it. That object travels **two ways at once**, and both are needed:

| | |
| --- | --- |
| go_router `extra` | Instant for a tap handled in-process. |
| `pendingChatLaunchProvider` | Survives the route being built more than once. |

`extra` is attached to one route entry and does not survive a cold start: the push is replayed after
the session resolves, the route gets built again, and the second build receives `extra: null`. The
symptom is precise — chat opens (the route string survived) with an empty composer (the object did
not). `ChatView` therefore takes `widget.launch ?? ref.read(pendingChatLaunchProvider)` and clears the
provider the moment it has it, so a question is asked once and a later, deliberate visit to chat never
inherits yesterday's.

`ChatLaunch.source` is carried rather than inferred. It used to be derived from `autoSend`, which was
fine only while readings were the only thing that auto-sent — with `notif_drip_chat_autosend` on,
every drip push would have reported as `source: 'reading'` in `Chat Opened` and quietly ruined the one
funnel the drip is judged by. It is `'push'` for a push and `'reading'` for an in-app "Ask Astro", and
a test pins it.

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
| every event `notif_<campaign>_enabled` | `true` (all 13 flipped on 2026-09-18) — the drip's six are separate, below |

And the drip's own. The **Seeded** column is what `20260923000001_daily_drip.sql` writes; **Now** is
what production is actually set to, which is what the drip does today:

| Key | Seeded | Now | |
| --- | --- | --- | --- |
| `notif_drip_enabled` | `false` | `false` | the master switch, read in SQL *and* TypeScript |
| `notif_daily_<slot>_enabled` × 6 | `false` | `false` | per slot |
| `notif_drip_slot_today` … `_evening` | `8`, `10.5`, `13`, `15.5`, `18`, `20` | — | IST hour; fractional is half past |
| `notif_drip_enqueue_window_minutes` | `60` | — | how long before its slot a row may be made |
| `notif_drip_daily_total` | `6` | — | ceiling across **all** campaigns, non-active |
| `notif_drip_daily_total_active` | `2` | — | the same, for `payment_type = 'active'` |
| `notif_drip_min_gap_minutes` | `45` | — | how long a drip push yields to any other |
| `notif_drip_dormant_days` | `7` | — | no session this recently → two slots, not six. `0` disables |
| `notif_drip_languages` | all seven | — | narrow to `english,hinglish` to pilot on the reviewed two |
| `notif_drip_chat_autosend` | `false` | **`true`** | the question sends itself on arrival — see [The seeded question](#the-seeded-question) |
| `notif_dispatch_batch` | `200` | — | rows enqueued per campaign per pass |

**Nothing is being sent yet.** `notif_drip_enabled` is still `false`, so the six branches select
nobody. `notif_drip_chat_autosend` being `true` only decides what a drip push *does when tapped*, and
takes effect the moment the first slot is switched on.

`notif_daily_cap` and `notif_min_gap_minutes` are **unchanged** — the drip does not use them, and
nothing about the 14 event campaigns moves when it is switched on.

There is a helper for all of this at [supabase/scripts/push.sh](supabase/scripts/push.sh):

```bash
export CRON_SECRET='…'                                   # app_config.reconcile_secret

./push.sh dry                                            # who would get what, right now
./push.sh dry dormant
./push.sh send d53877e5-33d0-4fad-bb13-45328e23ee3b      # one real push to one account
./push.sh send <user_id> winback_paid
./push.sh run                                            # run the dispatch without waiting for cron

# The drip. A slot only has candidates inside the hour before it, so this correctly says 0 at noon:
./push.sh dry daily_palm                                 # run it between 09:30 and 10:30 IST
./push.sh send <user_id> daily_today                     # `send` ignores the window
./push.sh send <user_id> daily_kundali '{"variant":"kundali_ask_0"}'
./push.sh send <user_id> daily_evening '{"variant":"evening_ask_0","planet":"saturn"}'
```

`send` on a drip slot takes the variant you name, so all 26 can be read on a real phone in a real
language before any of them is switched on.

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
| `quiet_hours` | Would land in quiet hours, and would expire before they end |
| `cap` | Over the daily cap, and would expire before the cap resets |
| `opted_out` | Marketing campaign, `push_marketing_opt_out` set |
| `disabled` | Campaign switched off between enqueue and send |
| `no_user` | Account gone |

A large `no_token` count is normal during an app rollout: tokens registered by builds older than the push feature have a null `app_build` and are excluded by design. They backfill as users update, because the app re-registers its token on every cold start.
