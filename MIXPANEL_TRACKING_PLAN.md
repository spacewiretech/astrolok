# Astrolok — Mixpanel Tracking Plan

**Product:** Astrolok (palm reading, face reading, AI astrology chat & Kundali)
**Platforms:** Flutter app (Android + iOS) + Supabase Edge Functions (server)
**SDK:** `mixpanel_flutter` (app) · Mixpanel HTTP Track/Engage API (server)
**`distinct_id`:** `users.user_id` — the database primary key. Never a phone number or email.
**Last updated:** 17 September 2026

---

## 1. Overview

| Source | Live events | What it answers |
|--------|-------------|-----------------|
| **Flutter app** | 128 | Everything the user does in front of the screen: onboarding, paywall, payments, readings, chat, Kundali, push taps, profile |
| **Supabase Edge Functions** | 14 | Everything that happens while the app is closed: recurring UPI debits, mandate holds, cancellations, refunds, disputes, push notifications sent, Kundali readings written |
| **Total live** | **142** | |

Six more events are declared in code but not currently emitted — see [§11](#11-declared-but-not-emitted).

**Two rules that shape the whole plan:**

1. **Event names are Title Case, past tense** (`Payment Completed`, not `complete_payment`). Property keys are `snake_case`. Every name lives as a constant in `lib/data/analytics/analytics_events.dart`, never as a string literal at the call site — a typo in an event name does not fail, it *forks* into a second half-populated column, and a funnel built on the wrong one silently under-counts.
2. **Palm and face share one vocabulary**, separated by the `feature` property (`palm` / `face`). The two flows are exact code mirrors, so one funnel answers "how many captures become readings" across both *and* per feature.

---

## 2. How the plumbing works

```
ViewModel / widget
      ↓  analytics.track("Event Name", {...})
  MultiAnalytics  ──────────────┬──────────────────┐
      ↓                          ↓                  ↓
  MixpanelAnalytics        FacebookAnalytics    (NoopAnalytics in tests / web)
      ↓  queue → SDK            ↓  4 events only
   Mixpanel                 Meta Ads
```

Three things a PM should know about this:

- **The Mixpanel token lives in Supabase `app_config`, not in the build.** It can be rotated or switched off without shipping a new app version. Because the token is not in hand at launch, the first events (`App Launched`, `Session Started`, the first screen views) are **queued** and sent once the token arrives, each carrying `queued_lag_ms` so a delayed event is never mistaken for a slow user. Queue caps: 300 events / 5 minutes.
- **Facebook only ever receives 4 of the 105 events** (see [§9](#9-facebook-ads-conversions)). Mixpanel answers product questions and needs everything; an ad optimiser needs a handful of conversions.
- **Server events never delay a payment.** Mixpanel sends from the webhook run on `EdgeRuntime.waitUntil` with a 4-second timeout, and every failure is logged and swallowed. An unreachable Mixpanel costs us analytics, never someone's subscription.

**Code map**

| Component | Location |
|-----------|----------|
| Event & property name constants | `lib/data/analytics/analytics_events.dart` |
| Mixpanel sink (queue, identify, super properties) | `lib/data/analytics/mixpanel_analytics.dart` |
| Fan-out to multiple sinks | `lib/data/analytics/analytics.dart` |
| Device/app context (super properties) | `lib/data/analytics/analytics_context.dart` |
| Sessions, lifecycle, UPI hand-off | `lib/data/analytics/analytics_session.dart` |
| Screen views & the ambient `screen` property | `lib/app/analytics_observer.dart` |
| Facebook Ads sink | `lib/data/analytics/facebook_analytics.dart` |
| Server Mixpanel helper | `supabase/functions/_shared/mixpanel.ts` |
| Server subscription/payment events | `supabase/functions/_shared/subscription_sync.ts` |
| Webhook entry point | `supabase/functions/cashfree-webhook/index.ts` |

---

## 3. Super properties — attached to every app event

Gathered once at boot and merged into every event, so no call site has to pass them.

| Property | Type | Value |
|----------|------|-------|
| `screen` | string | The screen the user was on when the event fired — filled in by the navigator observer. **This is why no event has to name its own screen.** |
| `is_modal` | boolean | Present only when the current surface is a sheet or dialog |
| `session_id` | string | Survives a process death inside the 30-minute idle window |
| `push_campaign` | string | Present for the rest of a session that a push opened — `kundali_ready`, `mid_cancel`, … **This is what turns a push into an outcome**: `Kundali Viewed` or `Subscribe Tapped` carrying the campaign that caused it. In memory only, cleared when a new session starts; plain `campaign` is the ad campaign |
| `push_notification_id` | string | The `notifications.id` of that push, for joining to `Notification Sent` |
| `install_id` | string | Stable per installation, **survives sign-out** (unlike Mixpanel's `$device_id`). This is what makes "two accounts on one handset" answerable |
| `days_since_install` | number | |
| `is_new_user` | boolean | True on the very first launch |
| `previous_version` | string | Present only on the first launch after an upgrade |
| `app_version`, `build_number` | string | |
| `build_mode` | string | `release` / `profile` / `debug` — **filter `build_mode = release` in every report** |
| `env` | string | From `app_config` |
| `backend_mode` | string | `supabase` / `fast2sms` / `fake` — a developer running against fakes would otherwise pollute production funnels with free subscriptions |
| `app_language`, `app_locale` | string | The language the app is *rendering* in. A Hindi speaker and an English speaker in Lucknow are the same row without this, and they are not the same user |
| `utc_offset_minutes` | number | India is UTC+5:30 and the backend stores UTC |
| `queued_lag_ms` | number | Present only when the event waited for the Mixpanel token |
| `preferred_upi_app` | string | Set once a UPI app is chosen on the paywall — which app a user pays with predicts whether the mandate succeeds |

**Identity super properties** (added on `identify`, **dropped on sign-out** so the next user of the handset does not inherit the last one's account): `is_signed_in`, `payment_type`, `entitled`, `in_trial`, `has_ever_subscribed`, `billing_state`, `has_birth_date`, `plan_variant` (`plan_499` / `plan_299` — which side of the price split the account is on, see §9.1; absent for a payload from before the split).

**Deliberately absent:** device model, manufacturer, OS version, screen size, carrier, library version, and the city/region/country Mixpanel derives from the request IP. The native SDK already attaches all of these. Adding them here would not add a field — it would add a *second* field under a non-standard name, invisible to every built-in Mixpanel report.

---

## 4. Core funnels

```
App Launched
   → Screen Viewed (Onboarding)
   → OTP Requested → OTP Submitted → OTP Verified
   → Name Submitted → Signup Completed
   → Birth Date Submitted
   → Paywall Viewed
   → Subscribe Tapped
   → Mandate Start Succeeded → UPI Intent Launched
   → UPI App Opened → UPI App Returned          ← the 30 seconds we are blind to without these
   → Payment Completed (outcome = success)       ← the one event with money on it
   → Home Viewed
   → Reading Capture Opened → Reading Photo Captured → Reading Scan Started → Reading Succeeded
   → Ask Astro Tapped → Chat Message Sent
   ─────────────────────────────────────────────
   → Mandate Authorised        (server, ₹3 or full price)
   → Subscription Renewed      (server, monthly autopay)
   → Subscription Cancelled    (server, churn)
```

**The funnels worth building first:**

| # | Funnel | Steps | What it tells you |
|---|--------|-------|-------------------|
| 1 | **Acquisition** | `App Launched` → `OTP Requested` → `OTP Verified` → `Signup Completed` | Where phone auth leaks. Break down by `entry_method` to see whether OTP autofill is working |
| 2 | **Purchase** | `Paywall Viewed` → `Subscribe Tapped` → `Mandate Start Succeeded` → `Payment Completed (outcome=success)` | Break down by `flow` (`intent` vs `checkout`) and `app_id`. The Cashfree checkout-screen fallback converts materially worse than a one-tap UPI intent |
| 3 | **Trial vs plan** | Same as #2, broken down by `offer_type` (`trial` / `plan`) | A ₹3 trial and a full-price purchase convert nothing like each other; a single paywall conversion rate averages them into meaninglessness |
| 4 | **Activation** | `Payment Completed` → `Home Viewed` → `Reading Scan Started` → `Reading Succeeded` → `Ask Astro Tapped` | Whether people who pay actually get a reading. Break down by `feature` to compare palm and face |
| 6 | **Kundali** | `Kundali Card Tapped` → `Kundali Requested` → `Kundali Waiting Viewed` → `Kundali Viewed (first_view = true)` → `Kundali PDF Exported` | Whether the 24-hour reveal brings people back. Count `Kundali Waiting Viewed` per `kundali_id` for return visits during the wait |
| 7 | **Push outcome** | `Notification Sent` → `Push Opened` → `Push Routed` → outcome event, held constant on `push_notification_id` / `notification_id` | Per campaign: delivered, opened, landed, and did the thing. `Notification Skipped` by `skip_reason` explains the gap before Sent |
| 5 | **Retention & churn** | `Mandate Authorised` → `Subscription Renewed` (renewal 1) → `Subscription Renewed` (renewal 2+) · vs `Subscription Cancelled` / `Subscription Payment Failed` | The whole paid relationship. All server-side |

---

## 5. App events — lifecycle, navigation & infrastructure

| Event | Fires when | Where | Key properties |
|-------|-----------|-------|----------------|
| `App Launched` | Cold start, once the session is resolved | `analytics_session.dart` | `is_first_launch`, `cold_start`, `seconds_since_last_open` |
| `Session Started` | A new session begins (first launch, or a foreground after 30+ minutes idle) | `analytics_session.dart` | — |
| `Session Ended` | The idle timeout is crossed, or the app detaches | `analytics_session.dart` | `duration_seconds`, `screens_viewed` |
| `App Foregrounded` | App returns to the foreground | `analytics_session.dart` | `seconds_backgrounded` |
| `App Backgrounded` | App goes to the background. **Everything queued is flushed here** — the process may not survive | `analytics_session.dart` | `session_seconds` |
| `App Terminated` | Best-effort on detach (Android often kills the process without delivering this) | `analytics_session.dart` | `session_seconds` |
| `UPI App Opened` | The app backgrounds while a UPI hand-off is outstanding | `analytics_session.dart` | `app_id` |
| `UPI App Returned` | The app foregrounds after that hand-off | `analytics_session.dart` | `app_id`, `seconds_in_upi_app` |
| `Tracking Consent Resolved` | iOS ATT status is answered, or was already standing | `att_consent.dart` | `status`, `granted`, `prompted` |
| `Push Permission Resolved` | The notification permission prompt is answered, or was already standing. Asked by the primer after the language pick (`source = language`), by **Notify me when ready** on the kundali wait (`kundali`), and from Home for anyone never asked (`home`) | `push_messaging.dart` | `status`, `granted`, `prompted`, `source` |
| `Push Opened` | A push notification is tapped | `push_messaging.dart` | `source` (`launch` / `background`), `message_id`, `campaign`, `notification_id`, `route` |
| `Push Received` | A push arrives while the app is on screen and is shown as the in-app banner | `push_messaging.dart` | `message_id`, `campaign`, `notification_id`, `route` |
| `Push Routed` | A tapped push (or banner) is taken to its screen | `push_navigation.dart` | `route`, `campaign`, `notification_id` |
| `Push Dropped` | A tapped push cannot go where it points | `push_navigation.dart` | `drop_reason` (`unknown_route` / `signed_out` / `not_entitled` / `onboarding` / `already_entitled` / `no_longer_needed`), `campaign`, `notification_id`, `route` |
| `Push Primer Shown` | The app's own explanation before the system prompt | `push_primer_sheet.dart` | `source` |
| `Push Primer Answered` | Allow or Not now on it | `push_primer_sheet.dart` | `source`, `choice` (`allow` / `not_now`) |
| `Screen Viewed` | Any route is pushed, replaced, or resurfaced after a back | `analytics_observer.dart` | `screen`, `previous_screen`, `route_path`, `nav_type`, `is_modal`, plus `route_*` params |
| `Screen Exited` | Any route is popped, replaced or removed | `analytics_observer.dart` | `screen`, `exit_type`, `seconds_on_screen` |
| `Back Pressed` | The user goes back (system or in-app) | `analytics_observer.dart` | `screen`, `blocked`, `is_modal` |
| `Element Tapped` | Any tap on a shared widget wrapped in `trackedTap` | `analytics.dart` + call sites | `element_id`, `label` |
| `Error Shown` | An **error** snackbar is shown to the user (success snackbars are not tracked) | `app_snackbar.dart` | `message`, `source` |
| `Edge Call Failed` | Any Supabase Edge Function call fails — one chokepoint, so backend health needs no per-feature instrumentation | `edge_functions.dart` | `function`, `code` (null = never reached the server), `message`, `ms` |
| `Splash Resolved` | The splash decides where to send the user | `splash_viewmodel.dart` | `destination`, `is_signed_in`, `entitled`, `has_name`, `has_birth_date`, `payment_type`, `ms` |

**Screen names** reported by `Screen Viewed`: Splash, Onboarding, Birth Date, Paywall, Payment Status, Home, Palm Capture, Palm Scan, Palm Reading, Palm Line, Face Capture, Face Scan, Face Reading, Face Part, Chat, Profile, Downloads, Astro Memory, Kundali, Kundali Form, Kundali Waiting, Kundali Report, Cancellation Reason.
**Modal names:** UPI App Picker, Chat Drawer, Rename Thread Dialog, Delete Thread Dialog, Forget Fact Dialog, Forget All Dialog.

> Note: `/onboarding` is a single route whose three steps are a query parameter, so phone, OTP and name are **one screen**. The step transitions are covered by the explicit onboarding events below, which carry far more than a screen view could.

---

## 6. App events — onboarding & birth date

All in `lib/features/onboarding/onboarding_viewmodel.dart` and `lib/features/birth/birth_viewmodel.dart`.

| Event | Fires when | Key properties |
|-------|-----------|----------------|
| `Phone Entry Started` | First keystroke in the phone field (once per session) | — |
| `Phone Number Entered` | The phone reaches full length (once per session) | — |
| `OTP Requested` | "Send OTP" tapped — **including when the validator refused it**. A run of `valid: false` is a broken phone field that would otherwise leave no trace | `valid` |
| `OTP Request Failed` | The provider refused to send | `message`, `trigger` (`resend` when it was a resend) |
| `OTP Entry Started` | First keystroke in the OTP field | — |
| `OTP Resend Requested` | Resend accepted | `resends_used` |
| `OTP Resend Blocked` | Resend refused. Separates "the SMS never arrived and they are out of resends" from "they tapped twice inside the cooldown" | `reason` (`exhausted` / `cooldown`), `seconds_remaining`, `resends_used` |
| `OTP Autofill Result` | Android finished trying to read the code from the SMS (Android only) | `method` (`sms_consent` — one-tap Allow sheet / `sms_retriever` — zero tap, needs the app hash in the SMS), `result` (`filled` / `none` — declined, timed out, or no matching SMS) |
| `OTP Submitted` | Verify attempt starts | `entry_method` (`button` / `auto_complete` — typed or Gboard suggestion / `sms_consent` / `sms_retriever`), `attempts_used`, `resends_used` |
| `OTP Verified` | Code accepted | `entry_method`, `attempts_used`, `resends_used`, `is_new_user`, `has_name`, `has_birth_date`, `entitled`, `destination`, `seconds_to_verify` |
| `OTP Verification Failed` | Code rejected, expired or the send failed | `reason` (`expired` / `send_failed` / …), `attempts_used`, `attempts_left`, `resends_used`, `error`, `seconds_to_verify` |
| `OTP Attempts Exhausted` | The attempt budget runs out | `resends_used` |
| `Name Entry Started` | First keystroke in the name field | — |
| `Name Submitted` | Name sheet submitted | `name_length` (the length, never the name) |
| `Name Save Failed` | Server refused the name | `message` |
| **`Signup Completed`** | Name saved — **the end of onboarding and the denominator of everything after it** | `destination` |
| `Signed Out` | Logout, fired **before** the identity reset so it lands on the account that actually left | `source` (`profile` / `paywall`) |
| `Birth Entry Started` | First wheel touched | — |
| `Birth Wheel Changed` | Any wheel moved | `field` (`day` / `month` / `year`) |
| `Birth Date Submitted` | Date saved | `birth_year`, `age_years`, `destination` |
| `Birth Save Failed` | Save refused | `message` or `error` |

> **`is_new_user` on `OTP Verified` is the property that separates signup from login.** A returning user on a wiped device already has a name and must not be counted as a signup.

---

## 7. App events — paywall & payment

The single most instrumented flow in the app. **Every event in one checkout attempt carries `payment_attempt_id`** (format `pa_<microseconds>_<n>`) and `attempt_number` — without it, a user who tries three times is one indistinguishable smear of events.

### 7.1 Paywall

| Event | Fires when | Where | Key properties |
|-------|-----------|-------|----------------|
| `Paywall Viewed` | The paywall paints (once per visit) — **the denominator of the purchase funnel** | `subscription_view.dart` | `trial_available`, `state` (`loaded` / `error`), `upi_app_count`, `payment_type` |
| `Paywall Offer Loaded` | Offer, user and UPI app list all resolve | `subscription_viewmodel.dart` | `trial_price`, `plan_price` (the account's own price — ₹499 or ₹299), `plan_variant`, `trial_days`, `trial_available`, `upi_app_count` (**zero here means the Cashfree checkout screen stands in for the one-tap intent — a materially worse flow**), `ms` |
| `Paywall Offer Load Failed` | Any of the three fail | `subscription_viewmodel.dart` | `error`, `ms` |
| `Promo Video Toggled` | Mute/unmute on the promo video | `subscription_view.dart` | `muted` |

### 7.2 UPI app selection

| Event | Fires when | Where | Key properties |
|-------|-----------|-------|----------------|
| `UPI Apps Discovered` | Cashfree returns the installed UPI apps | `cashfree_checkout.dart` | `count`, `app_ids` (**which apps, not just how many** — mandate success rates differ sharply between PSPs), `ms` |
| `UPI Discovery Failed` | Discovery throws or times out | `cashfree_checkout.dart` | `reason` (`timeout` / `error`), `error`, `ms` |
| `UPI App Preselected` | An app is picked for the user on load | `subscription_viewmodel.dart` | `app_id`, `source` (`remembered` / `first` / `none`) |
| `UPI Picker Opened` | "Change" tapped | `subscription_view.dart` | `app_id`, `available_count` |
| `UPI App Changed` | A different app is chosen | `subscription_viewmodel.dart` | `from_app_id`, `to_app_id`, `position_in_list`, `available_count` |

### 7.3 Checkout

| Event | Fires when | Where | Key properties |
|-------|-----------|-------|----------------|
| **`Subscribe Tapped`** | The subscribe button is pressed and accepted | `subscription_viewmodel.dart` | `payment_attempt_id`, `attempt_number`, `app_id`, `offer_type` (`trial` / `plan`), `amount`, `plan_variant`, `plan_amount` (the account's monthly price as a number — what the Facebook and Google sinks value a `plan` purchase at), `flow` (`intent` / `checkout`) |
| `Subscribe Tap Ignored` | The button was tapped while busy or loading. **A run of these means the button looks tappable while it is working** | `subscription_viewmodel.dart` | `reason` (`loading` / `busy`), `attempt_number` |
| `Mandate Start Requested` | The create-subscription call goes out | `subscription_viewmodel.dart` | attempt properties |
| `Mandate Start Succeeded` | Server returns a mandate session | `subscription_viewmodel.dart` | `subscription_id`, `environment` |
| `Mandate Start Refused` | Server declined to open a mandate | `subscription_viewmodel.dart` | `message` |
| `Mandate Already Entitled` | Server refused because the account is already in a trial or paid month. **Nothing was charged** | `subscription_viewmodel.dart` | attempt properties |
| `UPI Intent Launched` | Control is handed to the UPI app (or Cashfree's screen) | `subscription_viewmodel.dart` | `app_id`, `app_name`, `flow`, `subscription_id` |
| `Checkout Verified Callback` | Cashfree's SDK reports the UPI app handed control back. **Explicitly not proof of payment** | `cashfree_checkout.dart` | `subscription_id`, `seconds_in_checkout` |
| `Checkout Failed Callback` | Cashfree's SDK reports a failure | `cashfree_checkout.dart` | `cf_status`, `cf_code`, `cf_type`, `message`, `seconds_in_checkout` — **the code and type are what separate "our mandates are misconfigured" from "our paywall is unconvincing"** |
| `Checkout Orphan Callback` | A result arrives for an attempt nobody is waiting on (usually the app was killed mid-payment) | `cashfree_checkout.dart` | `outcome` |
| `Checkout Restarted` | A second attempt starts over an unfinished first | `cashfree_checkout.dart` | `app_id` |
| `Checkout Launch Failed` | The SDK could not be launched at all | `cashfree_checkout.dart` | `app_id`, `error` |
| `Checkout Timed Out` | No callback arrived inside the timeout | `cashfree_checkout.dart` | `app_id`, `seconds_in_checkout` |

### 7.4 Confirmation

| Event | Fires when | Where | Key properties |
|-------|-----------|-------|----------------|
| `Entitlement Poll Started` | The app starts asking the server whether money actually moved (8 attempts if the SDK verified, 3 if not) | `subscription_viewmodel.dart` | `max_attempts`, `sdk_verified` |
| `Entitlement Poll Failed` | One poll round trip failed. **A dropped poll is not a failed payment** | `subscription_viewmodel.dart`, `payment_status_view.dart` | `attempt`, `error` |
| **`Payment Completed`** | **The single exit from every checkout path** — success, failure and pending all report here with `outcome` as a property, so the funnel has one step to break down. Timed with Mixpanel's own stopwatch, so `$duration` survives the app being backgrounded for the whole UPI hand-off | `subscription_viewmodel.dart` | `outcome` (`success` / `failed` / `pending`), `sdk_verified`, `poll_attempts`, `reason`, `error`, `app_id`, `offer_type`, `plan_variant`, `plan_amount`, `total_seconds`, `$duration` |
| `Payment Status Viewed` | The status screen opens. **The verdict the user was shown, which is not always the verdict that was true** | `payment_status_view.dart` | `outcome` |
| `Payment Status Checked` | The status screen re-polls | `payment_status_view.dart` | `trigger` (`auto` / `manual`), `attempt` |
| **`Payment Confirmed Late`** | The entitlement lands *after* the paywall gave up. **Counting these separately is what turns "our checkout is unreliable" into "our webhook is slow"** | `payment_status_view.dart` | `attempt`, `trigger`, `seconds_since_checkout`, `offer_type`, `plan_variant`, `plan_amount` |
| `Payment Status Exhausted` | The status screen runs out of patience on a payment that may still be real. **These users are the most likely to pay twice or ask for a refund** | `payment_status_view.dart` | `attempt`, `seconds_since_checkout` |
| `Retry Payment Tapped` | "Try again" / "Back to plans" on the status screen | `payment_status_view.dart` | `outcome`, `source` |
| `Entitlement Lapsed` | The gate throws a user out mid-use — signed out, or no longer entitled | `entitlement_gate.dart` | `reason` (`signed_out` / `not_entitled`), `screen`, `previous_payment_type`, `billing_state` |

> **Revenue is deliberately not booked from the app.** The only amounts the client has are the paywall's display strings (`₹3`, `₹249`) — copy, not what Cashfree charged. The authoritative number arrives server-side under `Mandate Authorised` and `Subscription Renewed`. **There is exactly one revenue number in Mixpanel and it is the server's.**

---

## 8. App events — home, readings, chat & profile

### 8.1 Home

| Event | Fires when | Where | Key properties |
|-------|-----------|-------|----------------|
| `Home Viewed` | Home paints (once per visit) | `home_view.dart` | `thread_count`, `billing_state`, `payment_type` |
| `Billing Issue Shown` | The billing warning banner is displayed — shown while there is still time to fix the mandate | `home_view.dart` | `billing_state` |
| `Reading Card Tapped` | Palm or face card tapped | `home_view.dart` | `destination`, `source` |

### 8.2 Readings — palm & face

**One vocabulary for both flows, split by `feature` (`palm` / `face`).** All events below carry `feature`.

| Event | Fires when | Where | Key properties |
|-------|-----------|-------|----------------|
| `Reading Capture Opened` | The camera screen resolves for the first time | `*_capture_viewmodel.dart` | `camera_ready` |
| `Camera Permission Result` | Camera permission resolves — **the only way this app can answer the permission question** | `*_capture_viewmodel.dart` | `result` (`granted` / `denied`), `error`, `trigger` (`open` / `retry`; a retry is the user going to Settings and coming back) |
| `Reading Focus Selected` | The user picks what they want read, **before the photo**. A stated intent, volunteered before any result exists to bias it | `*_capture_viewmodel.dart` | `focus`, `previous_focus` |
| `Reading Photo Captured` | A photo is taken and prepared | `*_capture_viewmodel.dart` | `focus`, `bytes` (the *downscaled* size that goes to the model), `ms_to_capture`, `source` |
| `Reading Photo Picked` | A photo is chosen from the gallery (face flow only) | `face_capture_viewmodel.dart` | same as above, `source = gallery` |
| `Reading Capture Failed` | Shutter failed, image unreadable, gallery pick cancelled, or an exception | `*_capture_viewmodel.dart` | `reason` (`shutter_failed` / `unreadable` / `cancelled` / `exception`), `source`, `focus`, `error` |
| `Reading Scan Started` | The image goes to the model | `*_scan_viewmodel.dart` | `focus`, `bytes`, `attempt` |
| **`Reading Succeeded`** | A reading comes back and is saved | `*_scan_viewmodel.dart` | `reading_id`, `focus`, `line_count` (palm) / `section_count` (face), `attempt`, `ms` (**to the model's answer, not to the screen** — the progress animation's padding is excluded) |
| `Reading Failed` | No palm/face detected, daily or trial limit reached, or an error | `*_scan_viewmodel.dart` | `outcome` (`rejected` / `limitReached` / `trialLimitReached` / `notEntitled` / `signedOut` / `failed`), `message`, `focus`, `attempt`, `blocked` (**`true` = a dead end with no retry, the worst moment this flow has**), `ms` |
| `Trial Scan Limit Shown` | The popup telling a trial user their one palm or face reading is spent | `lib/app/trial_scan_guard.dart` | `source` (`carousel` / `card` / `downloads` = stopped at the tap, before the camera opened; `server` = the server refused a photo the device did not know to stop — a reinstall, or a reading taken on another phone) |
| `Reading Viewed` | The results screen paints | `*_reading_viewmodel.dart` | `reading_id`, `state` (`with_image` / `no_image`) |
| `Reading Detail Opened` | A specific line or facial part is opened | `*_reading_view.dart` | `reading_id`, `detail` |
| `Reading Narrated` | Text-to-speech starts | `*_reading_viewmodel.dart`, `chat_viewmodel.dart` | `surface` (`reading` / `chat`), `reading_id` or `thread_id`, `chars` |
| `Reading Narration Stopped` | Text-to-speech is stopped by the user | same | same |
| `Reading PDF Exported` | The share sheet **returns** — this counts an export the user saw through | `*_reading_viewmodel.dart` | `reading_id`, `bytes` |
| **`Ask Astro Tapped`** | The bridge from a reading into the chat. **The app's main cross-sell, and the only way to tell an organic chat from a prompted one** | `*_reading_view.dart`, `*_line_view.dart`, `face_part_view.dart` | `reading_id`, `source` (`palm_reading` / `palm_detail` / `face_reading` / `face_detail`), `detail` |

### 8.3 Chat

| Event | Fires when | Where | Key properties |
|-------|-----------|-------|----------------|
| `Chat Opened` | The chat screen opens | `chat_view.dart` | `has_opener`, `source` (`reading` / `direct`), `thread_count` |
| `Chat Topic Tapped` | An opening topic pill is picked | `chat_view.dart` | `topic` |
| `Chat Message Sent` | A message is sent — **counted before the send, so a turn that fails still has its question counted** | `chat_viewmodel.dart` | `thread_id`, `entry_method` (`typed` / `topic` / `quick_reply` / `opener` — three different levels of intent), `chars`, `turn_index` |
| `Chat Reply Received` | The sage answers | `chat_viewmodel.dart` | `thread_id`, `turn_index`, `ms`, `section_count`, `has_verdict`, `option_count`, `ask_for`, `count` (**daily allowance remaining — the turn where this hits zero is the turn a conversation ends against its will**) |
| `Chat Reply Failed` | The reply failed or the daily limit was hit | `chat_viewmodel.dart` | `reason` (`limit_reached` / `failed` / …), `message`, `chars` |
| `Chat Quick Reply Tapped` | A suggested reply chip is tapped | `chat_composer.dart` | `option_index`, `label`, `option_count` |
| `Chat Drawer Opened` | The conversation history drawer opens | `chat_view.dart` | — |
| `Chat Thread Created` | "New chat" tapped. **The intent to start one, not a thread on the server** — the gap between this and `Chat Message Sent (turn_index = 0)` is people opening a blank chat and thinking better of it | `chat_view.dart` | `source` |
| `Chat Thread Switched` | Another conversation is opened from the drawer | `chat_view.dart` | `thread_id` |
| `Chat Thread Renamed` | Rename confirmed **by the server** (the optimistic rename is undone on failure and not counted) | `chat_threads_viewmodel.dart` | `thread_id`, `chars` |
| `Chat Thread Deleted` | Delete confirmed | `chat_threads_viewmodel.dart` | `thread_id`, `thread_count` (**what is left afterwards** — deleting your last conversation is a different signal from tidying one out of twelve) |
| `Chat Rating Shown` | A reply asks for the five-face rating. **At most once per account** — the server stops asking once they answer or dismiss, so this against the two below is a response rate | `chat_viewmodel.dart` | `thread_id`, `turn_index` |
| `Chat Rated` | The rating card is submitted with a face picked, and an optional written comment | `chat_viewmodel.dart` | `thread_id`, `rating` (1 worst – 5 best), `has_comment`, `comment_chars` (length only — **the words are never sent to Mixpanel**; read them in `chat_feedback.comment`), `turn_index`, `chat_language` |
| `Chat Rating Dismissed` | The rating card is closed without a score | `chat_viewmodel.dart` | `thread_id`, `turn_index`, `chat_language` |

### 8.4 Profile

| Event | Fires when | Where | Key properties |
|-------|-----------|-------|----------------|
| `Downloads Viewed` | The saved-readings list loads | `downloads_viewmodel.dart` | `palm_count`, `face_count` (**split by feature — which one users come back for says which is carrying the product**) |
| `Download Opened` | A saved reading is reopened | `downloads_view.dart` | `feature`, `reading_id`, `age_days` (**anything beyond a day or two is a user treating a reading as a keepsake — the retention story**) |
| `Memory Viewed` | The "what Astro remembers" screen loads | `memory_viewmodel.dart` | `fact_count` (**no facts after several conversations means extraction is broken, which is invisible in the chat itself**) |
| `Memory Fact Forgotten` | One fact is erased | `memory_viewmodel.dart` | `fact_count` (before), `count` (after) |
| `Memory Cleared` | Everything is erased. **The strongest privacy signal this app gets** — counted separately from correcting one wrong fact | `memory_viewmodel.dart` | `fact_count`, `count` |
| `Support Link Opened` | Contact / policy links tapped | `profile_view.dart` | `link`, `result` (`opened` / `failed`) — **both stores check these at review time and a dead one fails a review** |
| `Renew Tapped` | "Renew to keep your readings" tapped | `profile_view.dart` | — |
| `Notification Preference Changed` | Profile → "Offers & reminders" switched | `profile_view.dart` | `marketing_opt_out` |
| `Element Tapped` | Profile menu rows and the profile button on Home | `profile_view.dart`, `home_view.dart` | `element_id` (`profile_button`, `profile_downloads`, `profile_memory`) |

---

### 8.5 Kundali

The fourth reading. Cast from date, time and place of birth; **revealed 24 hours after the request** (`kundali_unlock_hours`) so there is a reason to come back. The reading is written by `kundali-worker` minutes after the request and held; the server refuses the report before the reveal. **The place, coordinates, date and time of birth are never sent to Mixpanel.**

| Event | Fires when | Where | Key properties |
|-------|-----------|-------|----------------|
| `Reading Card Tapped` | The Kundali card on Home (same event as palm/face) | `kundali_card.dart` | `destination = kundali`, `source` |
| `Kundali Card Tapped` | The same tap, with where the kundali stands | `kundali_card.dart` | `kundali_state` (`none` / `waiting` / `delayed` / `ready` / `failed`), `hours_remaining` |
| `Kundali Form Viewed` | The birth-details form opens | `kundali_form_viewmodel.dart` | `is_edit`, `prefilled_dob`, `prefilled_time`, `prefilled_place` |
| `Place Search Started` | First search of a Google Places session (one per session token, not per keystroke) | `kundali_form_viewmodel.dart` | — |
| `Place Selected` | A suggestion resolves to a place | `kundali_form_viewmodel.dart` | `result_rank`, `suggestion_count`, `time_zone`, `ms` |
| `Place Search Failed` | Autocomplete or details refused or unreachable | `kundali_form_viewmodel.dart` | `code` |
| **`Kundali Requested`** | The chart is cast and the wait starts. **The denominator of the kundali funnel** | `kundali_form_viewmodel.dart` | `kundali_id`, `is_regeneration`, `regenerations_left`, `time_zone`, `unlock_hours` |
| `Kundali Request Failed` | The request was refused | `kundali_form_viewmodel.dart` | `code`, `message` |
| `Kundali Waiting Viewed` | The waiting screen opens. **Counted per open — returns during the wait are the recurrence the feature exists for** | `kundali_waiting_view.dart` | `kundali_id`, `kundali_state`, `hours_remaining`, `stage` (0-4) |
| `Kundali Notify Tapped` | "Notify me when ready" | `kundali_waiting_view.dart` | `permission_before`, `permission_after`, `prompted` |
| `Kundali Cross Sell Tapped` | A palm / face / chat card under "While you wait" | `kundali_waiting_view.dart` | `destination` |
| **`Kundali Viewed`** | The report paints | `kundali_report_viewmodel.dart` | `kundali_id`, `first_view` (**true exactly once — the reveal**), `hours_since_unlock`, `language` |
| `Kundali Insight Opened` | A life-insight tile opens its detail | `kundali_report_viewmodel.dart` | `kundali_id`, `insight` (`love` / `career` / `finance` / `year_ahead`) |
| `Kundali PDF Exported` | The share sheet returns | `kundali_report_viewmodel.dart` | `kundali_id`, `language`, `rasterised` (Indic text drawn as images), `bytes`, `ms` |
| `Kundali PDF Failed` | The export threw | `kundali_report_viewmodel.dart` | `error` |
| `Ask Astro Tapped` | "Ask Astro about your Kundali" | `kundali_report_view.dart` | `source = kundali_report`, `kundali_id` |

### 8.6 Cancellation reason

Asked by the `mid_cancel` push minutes after a mandate is cancelled (the reason was null on every one of 525 trial cancellations). `/leaving` is **ungated** — the person it asks has usually just lost access. The comment text is stored in `cancellation_feedback.comment` and never sent to Mixpanel.

| Event | Fires when | Where | Key properties |
|-------|-----------|-------|----------------|
| `Cancellation Reason Viewed` | The screen opens | `cancellation_reason_viewmodel.dart` | `source` (`push` / `in_app`), `notification_id`, `entitled` |
| **`Cancellation Reason Submitted`** | A reason is sent | `cancellation_reason_viewmodel.dart` | `reason` (`too_expensive` / `not_accurate` / `not_useful` / `only_exploring` / `payment_trouble` / `technical_issue` / `found_alternative` / `other`), `has_comment`, `recorded` (false = already answered), `was_in_trial`, `notification_id` |
| `Cancellation Reason Dismissed` | "Skip" | `cancellation_reason_viewmodel.dart` | `notification_id` |

---

## 9. Server events (11)

Sent from Supabase Edge Functions when Cashfree reports a payment-lifecycle change, or when the hourly reconcile sweep catches one that never arrived. **Never sent from the app.**

Every server event carries `source: "server"`, `server_function` (which Edge Function raised it: `cashfree-webhook`, `subscription-reconcile`, `subscription-start`, `subscription-status`, `subscription-cancel`), and `$ip: "0"` so Mixpanel does not overwrite the user's real city with a Supabase data centre.

| Event | Fires when | Dedupe key (`$insert_id`) | Key properties |
|-------|-----------|---------------------------|----------------|
| **`Mandate Authorised`** | A successful **AUTH** charge — the first ₹3 trial fee, or a returning subscriber's full first month | `pay:{cf_payment_id}:{status}` | `amount`, `currency`, `kind`, `cf_payment_id`, `subscription_id`, `payment_status`, `already_credited`, `trigger`, `plan_variant`, `plan_id`, `plan_name` |
| **`Subscription Renewed`** | A successful **RECURRING** monthly debit. **The one server event with a second sink** — it is also reported to Meta as a `Purchase`, see the note below | `pay:{cf_payment_id}:{status}` | same as above |
| **`Subscription Payment Failed`** | A charge attempt is declined. **The single most actionable event this system produces — the moment a paying customer starts silently churning** | `pay:{cf_payment_id}:{status}` | `failure_reason`, `amount`, `kind`, `cf_event_type`, … |
| `Subscription Payment Pending` | A charge is neither successful nor failed yet | `pay:{cf_payment_id}:{status}` | same |
| `Subscription Status Changed` | Cashfree's mandate status differs from ours (e.g. `ACTIVE → ON_HOLD`) | `sub:{id}:{from}:{to}:{minute}` | `from_status`, `to_status`, `transition` (pre-computed name), `billing_state`, `payment_type`, `recurring_amount`, `next_billing_at`, `authorized_at`, `plan_variant`, `plan_id`, `plan_name` |
| **`Subscription Cancelled`** | The mandate ends, from any of four places: Cashfree webhook, reconcile sweep, in-app cancel endpoint, or the stale/duplicate-mandate cleanup | `cancel:{subscription_id}` — no time bucket, because **a subscription is cancelled exactly once** | `cancelled_by` (`user_in_app` / `system` / …), `cf_status`, `from_status`, `reason` (`replaced_by_new_mandate` / `duplicate_mandate` / …), `was_in_trial`, `entitled_until`, `recurring_amount`, `days_subscribed`, `plan_variant`, `plan_id`, `plan_name` |
| `Refund Recorded` | Cashfree reports a refund | `refund:{cf_refund_id}:{status}` | `amount`, `currency`, `refund_status`, `refund_reason`, `attributed` (**false = we cannot tie it to a subscription, which usually means the charge it reverses was never recorded either**) |
| `Dispute Recorded` | Cashfree reports a chargeback/dispute | `dispute:{cf_dispute_id}:{status}` | `amount`, `dispute_status`, `dispute_type`, `dispute_reason`, `respond_by`, `lost`, `attributed` |
| `Webhook Retrying` | One notification crosses the retry-storm threshold — a webhook Cashfree cannot deliver successfully | `wh:{notification}:retry_storm` | `cf_event_type`, `deliveries`, `signature_ok`, `subscription_id` |
| **`Referral Attributed`** | A referral relationship is created by `referral-claim`. Fires **once per referred user, ever** — the `referrals` primary key makes a second one impossible | `ref:{referred_user_id}` | `referral_code`, `referred_by`, `attribution_type`, `acquisition_source` |
| **`Referral Converted`** | A referred user's first successful charge — the ₹3 mandate. **This is the event a referral programme is judged on** | `refconv:{referred_user_id}` | `referred_by`, `referral_code`, `cf_payment_id`, `amount`, `currency` |
| `Attribution Recorded` | `attribution-report` stores a user's acquisition. **Distinct from the app's `Attribution Resolved`** — that one fires when an install works out where it came from, including for the many installs that never sign up; this one fires when the backend stores it against an account | `attr:{user_id}:{source}:{channel}` | `acquisition_source`, `acquisition_channel`, `campaign`, `campaign_id`, `adset`, `ad`, `referral_code`, `is_first_touch` |
| **`Notification Sent`** | A push was delivered to FCM for at least one device (`notify.ts`) | `ns:{notification id}` | `campaign`, `notification_id`, `kind` (`transactional` / `marketing`), `route`, `language`, `trigger` (`cron` / `inline` / `test`), `tokens_attempted`, `tokens_delivered`, `attempt`, `delay_minutes`, `payment_type`, `entitled` |
| `Notification Failed` | FCM refused every device after retries, or FCM is not configured | `nf:{notification id}` | `campaign`, `notification_id`, `error_code`, `tokens_attempted`, `attempt`, `trigger` |
| `Notification Skipped` | A queued push was not sent — **terminal skips only**; deferrals for quiet hours or the daily cap are not events | `nk:{notification id}` | `campaign`, `notification_id`, `skip_reason` (`disabled` / `stale` / `opted_out` / `no_longer_eligible` / `cap` / `no_token` / `no_user`), `trigger` |
| **`Kundali Generated`** | `kundali-worker` wrote a reading | `kg:{kundali id}` | `kundali_id`, `model`, `latency_ms`, `attempts`, `language`, `prompt_version`, `minutes_after_request`, `minutes_before_unlock`, `problem_count` |
| `Kundali Generation Failed` | One attempt failed (`terminal = true` on the last) | `kf:{kundali id}:{attempt}` | `kundali_id`, `attempt`, `terminal`, `error_class` (`model` / `unusable` / `truncated`) |

> **⚠️ The distinction that matters most:** `Payment Completed` (app, `outcome = success`) is the app *believing* a payment landed. `Mandate Authorised` and `Subscription Renewed` (server) are Cashfree confirming money actually moved. **Use the server events for anything revenue-shaped.**

> **Deduplication is load-bearing.** Cashfree redelivers webhooks freely and the reconcile sweep replays history hourly. Every `$insert_id` is keyed on the *occurrence* (the charge, the cancellation), never on the delivery attempt. Without it, one renewal would be counted every hour for a month. Ids longer than 36 characters are hashed, because Mixpanel silently ignores over-long ones.

> **`Subscription Renewed` also goes to Meta.** `_shared/facebook_capi.ts` reports the same charge to the Conversions API as a `Purchase`, valued at what Cashfree actually took, so the ad optimiser can learn to buy ₹499 payers rather than ₹3 trial-starters. Three things about it are worth knowing when reading the numbers. It fires on **`RECURRING` only** — the ₹3 and a returning subscriber's full-price first month are reported by the app itself, and sending them twice would inflate ROAS. Its `event_id` is `pay:{cf_payment_id}`, keyed on the charge for the same reason `$insert_id` is. And it is **off unless configured** (`facebook_capi_enabled`, plus a dataset id and access token), so a project with those rows blank behaves exactly as it did before. Meta's copy of the number will run below Mixpanel's, because not every renewal matches to a person — see `FACEBOOK_ADS_TRACKING_GUIDE.md` §10.

### 9.1 The ₹499 / ₹299 price split

New signups are split between two monthly prices: ₹3 trial → ₹499/month, or ₹3 trial → ₹299/month. `verify-otp` assigns the plan once, when the account is created, from the running user total: odd total → the next account gets ₹499, even → ₹299. Every account that existed before the split stays on ₹499, and an account only ever sees its own price.

`plan_variant` (`plan_499` / `plan_299`) is on:

- **every app event** once the user is identified (identity super property), and on the People profile
- `Paywall Offer Loaded`, `Subscribe Tapped`, `Payment Completed` and `Payment Confirmed Late`, with `plan_amount` on the last three
- **every server subscription event** (`Mandate Authorised`, `Subscription Renewed`, `Subscription Payment Failed` / `Pending`, `Subscription Status Changed`, `Subscription Cancelled`), together with `plan_id` and `plan_name`, the Cashfree plan

| Question | Report |
|----------|--------|
| Is the split really 50/50? | `Signup Completed`, broken down by `plan_variant` |
| Which price converts more trials? | Funnel `Paywall Viewed` → `Subscribe Tapped` → `Mandate Authorised`, broken down by `plan_variant` |
| Which price keeps paying? | Retention `Mandate Authorised` → `Subscription Renewed`, plus `Subscription Cancelled` and `Subscription Payment Failed`, each broken down by `plan_variant` |
| Which earns more? | Sum of `amount` on `Mandate Authorised` + `Subscription Renewed`, broken down by `plan_variant` |

> **Compare only accounts created after `pricing_split_enabled` was turned on.** Before that, and for any signup from an app build older than the split, every account is assigned `plan_499`. Those accounts count toward the ₹499 side without ever having been part of the test.

---

### 9.2 Push campaigns

Every push is a row in `notifications`, unique on a `dedupe_key` that names the real-world occurrence, so the webhook, the hourly reconcile and a status poll racing each other still send one. Each campaign has its own `notif_<campaign>_enabled` switch under the master `notifications_enabled`; all ship **off**. Marketing campaigns respect Profile → "Offers & reminders"; everything except `mid_cancel` waits out quiet hours (22:00–08:00 IST); capped campaigns share `notif_daily_cap` (2 per IST day) and `notif_min_gap_minutes` (180). Copy exists in all seven chat languages (`notification_copy.ts`).

| Campaign | Kind | Trigger | Opens |
|----------|------|---------|-------|
| `mid_cancel` | transactional | **Inline**, the moment a mandate is cancelled from a UPI app (or our cancel endpoint) | `/leaving` |
| `billing_issue` | transactional | **Inline**, a new failed RECURRING debit or a transition to `ON_HOLD` | Home, or the paywall if access lapsed |
| `kundali_ready` / `kundali_ready_lapsed` | transactional / marketing | The reveal; the lapsed variant (renew to reveal) only if its own switch is on | `/kundali` / `/subscribe` |
| `kundali_halfway` | marketing | Halfway through the wait, if the waiting screen was not reopened | `/kundali` |
| `kundali_not_opened` | marketing | Revealed a day ago, not opened | `/kundali` |
| `palm_no_face` | marketing | Palm read 2h+ ago, no face reading | `/face` |
| `reading_no_chat` | marketing | A reading 3h+ ago, no question to Astro | `/chat` |
| `trial_no_reading` | marketing | 3h into a trial, nothing read | `/palm` |
| `paywall_abandoned` | marketing | Chose a language 30 min+ ago, never started a trial | `/subscribe` |
| `onboarding_incomplete` | transactional | Paid 20 min+ ago, no name or birth date | `/birth` |
| `post_charge_no_return` | marketing | First full-price charge 24–72h ago, not back since | `/kundali` or Home |
| `winback_paid` | marketing | A paying subscriber's period ended 1–3 days ago | `/subscribe` |
| `dormant` | marketing | Entitled, away 3+ days; once a week at most | `/chat` |

Not built: "Tarot ready" (no Tarot feature) and UPI hand-off abandonment (separate Payment Leak PRD).

## 9a. Referral & acquisition attribution

Where a user came from. Split into a **last touch** that moves freely and a **first touch** that is written once and never again — see §13 for the People properties.

### App events

| Event | Fires when | Key properties |
|-------|-----------|----------------|
| `Attribution Resolved` | The source is settled for this install, **once** — not per launch | `acquisition_source`, `acquisition_channel`, `campaign`, `campaign_id`, `adset`, `ad`, `referral_code`, `is_first_touch` |
| `Referral Claim Failed` | A claim was refused | `reason` (`invalidCode` / `selfReferral` / `notEligible`), `referral_code`, `attribution_type` |
| `Invite Screen Viewed` | The invite screen opens | — |
| `Invite Shared` | The share sheet was opened for an invite | `referral_code` |
| `Invite Code Copied` | The link was copied to the clipboard | `referral_code` |
| `Invite Code Submitted` | A code was typed by hand — the iOS deferred fallback | `referral_code` |

### `acquisition_source`

`referral` > `google_ads` > `meta` > `paid_other` > `organic`, resolved in that precedence. A referral code outranks any campaign parameter on the same link, because it is an explicit statement that a named user sent this person. Paid beats organic because `utm_medium=organic` is what the Play Store stamps on *every* store visit, including one that began with an ad click.

> **One event name, one source.** `Referral Attributed` is raised **only** by the server, and `Attribution Resolved` **only** by the app. An early draft of this emitted both names from both sides; client SDK events carry no `$insert_id`, so Mixpanel cannot collapse a client event against a server one however carefully the server keys its own, and every referral would have been counted twice.

### `acquisition_channel`

`install_referrer` is Google handing back the code or UTMs we put in the Play Store link — deterministic, and the source of very nearly everything. `manual_code` is the user typing a code, the fallback for an install the referrer could not cover. `deep_link` is reserved for the `astrolok://` scheme.

There is no `ip_match`: the probabilistic iOS recovery path was removed along with the rest of the iOS and web layer when the launch scope became Android-only.

> **⚠️ Campaign detail on App Install campaigns comes from Ads Manager, not Mixpanel.** On Meta and Google App Install campaigns the network controls the Play Store hand-off and sets its own referrer, so custom UTMs do not survive. `acquisition_source` still resolves (`gclid` → `google_ads`, Meta's own stamp → `meta`), but campaign/adset/ad breakdown is only reliable on traffic campaigns pointing at a store link we build ourselves.

> **⚠️ The Facebook SDK does not feed Mixpanel.** It reports installs and conversions to Meta, for Meta's dashboard and optimiser. The Play Install Referrer is the only thing that tells *Mixpanel* where a user came from. Two pipes, two consumers.

---

## 10. Facebook Ads conversions

Only **4** of the 105 app events are forwarded to Meta, chosen to give the ad optimiser a funnel it can train on before there are enough weekly purchases to optimise for purchases directly (which, on a ₹3 trial, takes a while).

| Astrolok event | Facebook event | Value |
|----------------|----------------|-------|
| `Signup Completed` | `CompletedRegistration` (`phone_otp`) | — |
| `Subscribe Tapped` | `InitiatedCheckout` | Amount for `offer_type`, from `app_config` |
| `Payment Completed` (only when `outcome = success`) | `Purchase` + `StartTrial` | Amount for `offer_type` |
| `Payment Confirmed Late` | `Purchase` + `StartTrial` | Amount for `offer_type` |

Facebook takes its amounts from `app_config`, never from a paywall label, and never reaches Mixpanel's revenue series — so the two systems stay independent and Mixpanel keeps exactly one revenue number.

### Google Analytics for Firebase

The same four conversions also reach Firebase, as GA4's recommended events, together with screen views and identity. Nothing else crosses: Mixpanel stays the product-analytics system of record, and Firebase exists for Google's side — Ads conversion import, audiences, crash-free users.

| Astrolok event | GA4 event | Value |
|----------------|-----------|-------|
| `Screen Viewed` | `screen_view` (`screen_name` = `screen`) | — |
| `Signup Completed` | `sign_up` (`method` = `phone_otp`) | — |
| `Subscribe Tapped` | `begin_checkout` | Amount for `offer_type`, from `app_config` |
| `Payment Completed` (only when `outcome = success`) | `purchase` (`transaction_id` = `payment_attempt_id`) | Amount for `offer_type` |
| `Payment Confirmed Late` | `purchase` | Amount for `offer_type` |

Identity is the account id only (`setUserId`, mirrored onto Crashlytics), and `backend_mode` is a user property so fake-tier traffic can be filtered out. Purchases carry their own persisted guard (`astrolok.ga_purchase_reported.v1`), independent of Facebook's, and read the same `app_config` amounts.

---

## 11. Declared but not emitted

These names exist as constants in `analytics_events.dart` but **nothing currently fires them**. Listed so nobody builds a report on an empty column.

| Event | Status |
|-------|--------|
| `App Crashed` | **Crashes are reported to Firebase Crashlytics**, which symbolicates and groups them. This Mixpanel twin stays commented out in `lib/boot/mobile_boot_io.dart`; uncommenting it restores a funnel-joinable crash event with `error`, `stack_head`, `fatal` |
| `Webhook Received` | **Deliberately suppressed** in `cashfree-webhook/index.ts` — foreign Cashfree traffic on a shared account produced an event flood that buried everything else. The full audit row is still written to `payment_events`, so nothing is lost and this can be reconstructed. To restore: deal with the foreign traffic first, then re-enable the block |
| `UPI Picker Dismissed` | No call site |
| `Promo Slide Viewed` | No call site |
| `Manage Billing Tapped` | No call site |
| `Reading Shared` | No call site |
| `Profile Viewed` | No call site — the Profile screen is covered by `Screen Viewed` |
| `Kundali Generated`, `Notification Sent` | **Server-only by design.** Declared in `analytics_events.dart` so the whole funnel is greppable from the app; never passed to `track` there (a client twin would carry no `$insert_id` and double-count) |

---

## 12. Identity management

| Action | When | Behaviour |
|--------|------|-----------|
| **Identify** | Signup, login, app resume while signed in, every entitlement re-resolve | `identify(user.user_id)` + People profile write. **Skipped when nothing changed** — the entitlement gate re-resolves on every resume and a six-hourly timer, so this runs far more often than the account actually changes. Only `last_seen` is written on a no-op |
| **Reset** | Sign-out only (Profile or Paywall) | Mints a new anonymous id and **drops the identity super properties**, so the next user of the handset does not inherit the last one's account. Environment-level super properties are re-registered afterwards |
| **Server identify** | Every payment/status webhook | Same `distinct_id` = `users.user_id`, so a 3am renewal lands on the same profile as the `Subscribe Tapped` that started it |

**Signup order:** `identify()` → `people.set()` → `track("Signup Completed")`.

**Attribution and identity.** There is no `alias()` call anywhere in this app — identity is bound purely by `identify(user_id)`. Events fired before signup therefore sit on an anonymous distinct id and stitch to the account only if the project is on **Simplified ID Merge**. This is why the durable attribution record lives in Supabase (`user_attribution`, keyed on `users.user_id`) and is mirrored onto the profile from the server: the record stays correct regardless of merge mode, and client-side stitching becomes a convenience rather than the thing the data depends on.

---

## 13. People profile properties

| Property | Set by | Notes |
|----------|--------|-------|
| `$name` | App | |
| `$phone` | App | The real number. Support needs to find an account from a call, and it is already the login identifier |
| `$created` | App | `setOnce` |
| `payment_type` | App + server | `trial`, `active`, … |
| `entitled`, `in_trial`, `has_ever_subscribed` | App + server | |
| `has_birth_date`, `birth_year` | App | The **year only** — enough for an age breakdown; the full date is a stronger identifier without answering anything the year does not |
| `billing_state` | App + server | Includes `disputed` when a chargeback is open |
| `plan_variant` | App + server | `plan_499` / `plan_299`, the account's side of the price split (§9.1). Set once at signup and never changed |
| `subscription_status` | Server | Cashfree's own status |
| `trial_ends_at`, `current_period_end` | App | |
| `next_billing_at` | Server | |
| `last_payment_at`, `last_payment_status` | Server | |
| `cancelled_at`, `cancelled_by` | Server | |
| `last_cancel_reason` | Server | From `cancellation-feedback`; never `dismissed` |
| `last_seen` | App | Written on every resume |
| `initial_acquisition_source`, `initial_acquisition_channel`, `initial_campaign`, `initial_campaign_id`, `initial_adset`, `initial_ad`, `initial_referral_code` | Server | **First touch. `setOnce`, and backed by an insert that does nothing on conflict.** Never overwritten — a first touch replaced by a later retargeting click re-attributes the acquisition to the campaign that had the least to do with it, and is invisible once it has happened |
| `acquisition_source`, `acquisition_channel`, `campaign`, `campaign_id`, `adset`, `ad`, `referral_code` | Server | Last touch. Freely updated — this is the half that is *supposed* to move |
| `is_referred` | Server | Boolean, cheap to segment on |
| `referrals_converted` | Server | On the **referrer's** profile. `$add`, incremented once per conversion behind the `qualified_at is null` database guard |

The server never *creates* a profile for someone who has not used the app — `identify()` from the client owns profile creation, and a server `$set` on an unknown id would mint a bare profile with no name, phone or device.

---

## 14. Data we intentionally do NOT collect

- **Raw chat message text** — only `chars` (length), `entry_method` and `turn_index`
- **The user's name** — only `name_length`
- **OTP values**
- **Full birth dates** — only `birth_year` and `age_years`
- **Reading and photo content** — only `bytes`, `focus`, `line_count` / `section_count`
- **Birth place, coordinates, time of birth, and place-search text** — only `time_zone`, `result_rank`, `suggestion_count`
- **Kundali reading text** — only `language`, `insight` keys and counts
- **Cancellation comments** — only `has_comment`; the words stay in `cancellation_feedback.comment`
- **Push copy** — the rendered title and body are kept in `notifications`, not in events
- **Email addresses as `distinct_id`**
- Device/OS/geo fields the SDK already attaches (never duplicated under a second name)

---

## 15. Naming conventions

- **Events:** Title Case, past tense — `Payment Completed`, not `complete_payment`
- **Properties:** `snake_case`
- **Property values:** lowercase where they are enums — `phonepe`, `trial`, `palm`
- **Nulls are stripped** before sending, on both the app and the server — Mixpanel stores an explicit null as a real value and it dirties every breakdown
- **New events must be added as a constant** in `analytics_events.dart`, never as a string literal

---

## 16. Verification checklist

1. **Live View** — run a debug build through each flow and confirm events and properties arrive. Filter `build_mode = debug` to isolate yourself
2. **Filter production reports on `build_mode = release` and `backend_mode = supabase`** — otherwise developer traffic and fake-backend subscriptions land in your funnels
3. **Identity** — signup and login land on the same profile; sign-out starts a fresh anonymous session; `install_id` stays constant across both
4. **App vs server** — `Payment Completed` only from the app, `Mandate Authorised` / `Subscription Renewed` only from the server. Use the server pair for revenue
5. **Dedupe** — redeliver a Cashfree webhook and confirm the renewal count does not move
6. **Lexicon** — add descriptions for all 142 live events in Mixpanel Data Management
7. **Funnels** — build the seven funnels in [§4](#4-core-funnels)
8. **Push** — `notification-dispatch` `send_test` to an internal account; confirm `Notification Sent`, then `Push Opened` and `Push Routed` with the same `notification_id`, then an outcome event carrying `push_campaign`

---

## 17. Event count summary

| Category | Live events |
|----------|-------------|
| Lifecycle & sessions | 11 |
| Navigation & infrastructure | 7 |
| Onboarding & birth date | 20 |
| Paywall & payment | 31 |
| Home | 3 |
| Readings (palm + face, shared vocabulary) | 15 |
| Chat | 11 |
| Profile | 8 |
| Push (received, routed, dropped, primer) | 5 |
| Kundali | 14 |
| Cancellation reason | 3 |
| **App subtotal** | **128** |
| Server / webhook | 9 |
| Server / notifications & kundali | 5 |
| **Total live** | **142** |
| Declared but not emitted | 7 (6 app + 1 server) |
