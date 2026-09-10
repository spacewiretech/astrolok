# supabase/functions/_shared

## Purpose

Everything more than one Edge Function needs. Not deployed on its own — each function imports
from here. This is where the credentials, the billing state machine and the model prompts live.

## Files

**Request plumbing**
- `cors.ts` — Exports: `corsHeaders`, `json`, `fail`, `preflight`.
- `db.ts` — the service-role client and the session-token machinery. Exports: `serviceClient`,
  `isValidMobile`, `consumeOtpQuota`, `hashToken`, `newSessionToken`, `userIdForBearer`.
- `config.ts` — loads the `app_config` table (private rows included). Exports: `AppConfig`,
  `loadConfig`, `configValue`, `isUnset`, `configSetting`, `configFlag`.

**Access and identity**
- `entitlement.ts` — **the single source of truth for "is this account allowed in".** Exports:
  `PaymentType`, `graceHoursFrom`, `UserRow`, `USER_COLUMNS`, `asUserRow`, `isEntitled`,
  `trialAvailable`, `isInTrial`, `entitlementPayload`.
- `fast2sms.ts` — OTP send/resend/verify with the key held server-side. Exports: `OTP_LENGTH`,
  `OTP_EXPIRY_MINUTES`, `Fast2SmsError`, `credentialsFrom`, `sendOtp`, `resendOtp`,
  `VerifyResult`, `verifyOtp`.
- `dev_otp.ts` — the fixed `000000` stand-in, behind two config conditions. Exports:
  `devOtpEnabled`, `DEV_OTP`, `warnDevOtp`.
- `review_account.ts` — one fixed-code sign-in for store reviewers, scoped to a single number.
  Exports: `reviewAccount`, `isReviewMobile`, `consumeReviewVerifyQuota`, `warnReviewAccount`.

**Billing** (the largest and most consequential code here)
- `cashfree.ts` (798 lines) — the UPI Autopay client plus webhook verification. Exports:
  `createSubscription`, `fetchSubscription`, `fetchSubscriptionPayments`, `cancelSubscription`,
  `snapshotOf`, the `is*Status` predicates, `webhookSignature`, `constantTimeEquals`,
  `verifyWebhook`, `dedupeKey`, `notificationKey`, `paymentFrom`, `refundFrom`, `disputeFrom`,
  and date helpers `toIstIso`/`addDays`/`addMonths`.
- `subscription_sync.ts` (1043 lines) — **the billing state machine.** Reconciles a subscription
  against Cashfree (the authority) and writes `subscriptions` + `users`. Exports:
  `syncSubscription`, `userUpdatesFor`, `recordPayment`, `reconcilePayments`,
  `refreshPaymentTotals`, `recordRefund`, `recordDispute`, `trackCancellation`,
  `latestSubscription`, `staleSweepCutoff`, `isResumable`, `paymentKind`, `buysAMonth`.

**The readings**
- `gemini.ts` — the model transport (image reads + multi-turn chat) and the shared status/focus
  vocabulary. Exports: `GeminiError`, `geminiSettings`, `readImage`, `converse`, `text`,
  `STATUSES`, `FOCUS_KEYS`, `FOCUS_LABELS`, `parseFocus`, `focusMismatch`, `ceremony`.
- `pandit.ts` — the shared persona, grounding rules, safety boundaries and style. Exports:
  `PANDIT_VOICE`, `GROUNDING`, `BOUNDARIES`, `STYLE`, `panditSystemPrompt`, `SHARED_LENGTHS`.
- `palm_reading.ts` — prompt, JSON schema and pure normaliser. Exports: `LINE_KEYS`,
  `LINE_TITLES`, `REJECT_REASONS`, `PALM_SCHEMA`, `SYSTEM_PROMPT`, `buildUserPrompt`,
  `normalisePalmReading`.
- `face_reading.ts` — a deliberate mirror of the above. Exports: `FACE_KEYS`, `FACE_TITLES`,
  `TRAIT_KEYS`, `FACE_SCHEMA`, `SYSTEM_PROMPT`, `buildUserPrompt`, `normaliseFaceReading`.
- `astro_chat.ts` — chat prompt, schema and reply normaliser. Exports: `CHAT_TOPICS`, `ASK_FOR`,
  `SYSTEM_PROMPT`, `CHAT_SCHEMA`, `ChatContext`, `buildUserPrompt`, `normaliseChatReply`.
- `jyotish.ts` — **the non-LLM astronomy.** Julian day, Sun/Moon longitudes, ayanamsa, sidereal
  rashi/nakshatra chart. Exports: `julianDay`, `sunLongitude`, `moonLongitude`, `ayanamsa`,
  `toSidereal`, `RASHIS`, `NAKSHATRAS`, `computeChart`, `describeChart`, `IST_OFFSET_HOURS`.

**Analytics**
- `mixpanel.ts` — server-side events the client can never observe (renewals, holds,
  chargebacks). Exports: `configureMixpanel`, `mixpanelConfigured`, `trackServer`, `setProfile`.

**Small helpers**
- `person.ts` — Exports: `ageFrom`, `firstName`.

## Notes

- **`entitlement.ts` derives, it never stores.** Entitlement is computed from `payment_type`
  plus `trial_ends_at` / `current_period_end`, so a stalled webhook expires an account by the
  clock instead of leaving it entitled forever, and a renewal is just a date moving forward.
- **Cashfree is the authority on money, never the client and never the SDK callback.**
  `syncSubscription` reconciles against it; the webhook only triggers that.
- `jyotish.ts` is real astronomy, not model output — the chart is computed here and passed to
  Gemini as grounding. Validated against Meeus worked examples in `../tests/jyotish_test.ts`.
- The three reading modules share `pandit.ts` for voice and `gemini.ts` for the focus/status
  vocabulary; `face_reading.ts` and `palm_reading.ts` re-export the focus symbols so their
  callers do not need both imports.
- Every normaliser is **pure** — no network, no DB — which is what makes the tests next door
  fast and exhaustive.
- `cors.ts` is the only file with no header comment.
