# supabase/functions/_shared

## Purpose

Everything more than one Edge Function needs. Not deployed on its own — each function imports
from here. This is where the credentials, the billing state machine and the model prompts live.

## Files

**Request plumbing**
- `cors.ts` — Exports: `corsHeaders`, `json`, `fail`, `preflight`.
- `db.ts` — the service-role client and the session-token machinery. `userIdForBearer` stamps a
  session's `last_seen_at` only when it is ten minutes stale (`lastSeenDue`), and `withinCap` cuts a
  read made before `app_config` said how many rows it wants. Exports: `serviceClient`,
  `isValidMobile`, `consumeOtpQuota`, `hashToken`, `newSessionToken`, `lastSeenDue`,
  `userIdForBearer`, `withinCap`.
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
  `latestSubscription`, `staleSweepCutoff`, `isResumable`, `paymentKind`, `buysAMonth`, `planProps`.
- `pricing.ts` — the ₹499 / ₹299 price split. Which plan an account pays (`planFor`, the one answer
  both the paywall payload and `subscription-start` read), whether new signups alternate
  (`splitEnabled`), and the once-per-account assignment at signup (`assignPlanVariant`). Exports:
  `PlanVariant`, `DEFAULT_VARIANT`, `PricingPlan`, `PricingPlans`, `pricingPlans`, `planFor`,
  `splitEnabled`, `planPayload`, `assignPlanVariant`.

**The readings**
- `gemini.ts` — the model transport (image reads + multi-turn chat) and the shared status/focus
  vocabulary. Exports: `GeminiError`, `geminiSettings`, `readImage`, `converse`, `text`,
  `STATUSES`, `FOCUS_KEYS`, `FOCUS_LABELS`, `parseFocus`, `focusMismatch`, `ceremony`.
- `pandit.ts` — the shared persona, grounding rules, safety boundaries and style. Exports:
  `PANDIT_VOICE`, `GROUNDING`, `BOUNDARIES`, `STYLE`, `TIPS_RULE`, `TIMING_RULE`,
  `panditSystemPrompt`, `SHARED_LENGTHS`. `panditSystemPrompt` takes optional `grounding` and
  `voice` overrides; `BOUNDARIES` is deliberately not overridable, because it is the safety layer
  — except for its counsel bullet (`tips`) and its timing bullet (`timing`), which the chat
  replaces with narrower rules of its own. Palm and face keep both byte for byte.
- `palm_reading.ts` — prompt, JSON schema and pure normaliser. Exports: `LINE_KEYS`,
  `LINE_TITLES`, `REJECT_REASONS`, `PALM_SCHEMA`, `SYSTEM_PROMPT`, `buildUserPrompt`,
  `normalisePalmReading`.
- `face_reading.ts` — a deliberate mirror of the above. Exports: `FACE_KEYS`, `FACE_TITLES`,
  `TRAIT_KEYS`, `FACE_SCHEMA`, `SYSTEM_PROMPT`, `buildUserPrompt`, `normaliseFaceReading`.
- `astro_chat.ts` — chat prompt, schema and reply normaliser. Exports: `CHAT_TOPICS`, `ASK_FOR`,
  `CHAT_VOICE`, `CHAT_REMEDIES_RULE`, `CHAT_TIMING_RULE`, `PROMPT_V1`…`PROMPT_V4`,
  `promptVersion`, `chatSystemPrompt`, `CHAT_SCHEMA`, `ChatContext`, `BirthHourAsks`,
  `birthHourAsks`, `buildUserPrompt`, `normaliseChatReply`. The prompt is a **function**, not a
  constant: it varies by `chat_prompt_version` (the rollback) and by the language of the turn.
  The craft exists once per version on purpose — see the file header before factoring them
  together. v4 (current) answers "when" with a computed window, asks for the birth hour once
  (`birthHourAsks` counts it in code), writes plain Hindi/Hinglish and halves everything below
  the verdict.
- `astro_chat_v5.ts` — **chat v5, the WhatsApp-style chat** (only for clients sending `chat_ui: 2`;
  see `effectiveVersion` in `astro_chat.ts`). Short `bubbles`, the day's upay offered and written
  as hidden `remedy_bubbles` (served by `astro-chat` on a yes, no model call, unmetered), a window
  for every "kab", love/one-person, names, "fake", stated-rashi and crisis rules, few-shot
  examples with placeholder windows, and follow-up chips kept to the topic of the question (a menu
  per topic in the prompt; `onTopicOptions` in code, which the upay turn goes through too).
  Once the chart is whole (date and hour on file), THE KUNDALI LINE opens the first reply — or
  the turn whose captured hour completed it — once a thread: their rashi and nakshatra, "sthan"
  only with `birth_place` on file, and "the time ahead looks good" only when some matter's window
  runs now or opens within a year (`kundaliLineFor`, `kundaliLineTurn`; the `kundali_line` marker
  on the stored body). Never above a message about a death, an illness or despair: then the reply
  is marked `kundali_line_owed` and the line waits for their next question on a matter the chart
  reads. A reply that gives a helpline (Tele-MANAS, iCall) is a `care` reply, whoever wrote it —
  no offer, no ask, no astrology chip, no top-up, and `astro-chat` flags the thread. Exports: `chatSystemPromptV5`, `CHAT_SCHEMA_V5`, `normaliseChatReplyV5`,
  `onTopicOptions`, `v5Body` (legacy fields filled too), `buildUserPromptV5`, `kundaliLineFor`,
  `kundaliLineTurn`, `hasWholeChart`, `mattersOpeningSoon`, `isRemedyAccept`, `acceptChipFor`,
  `CHAT_TIMING_RULE_V5`, `CHAT_HEALTH_RULE_V5`, `CHAT_REMEDIES_RULE_V5`.
- `chat_topics.ts` — what a v5 chip is about, read from its words in eight languages (whole words
  in Roman letters, word starts in the Indian scripts, look-alikes kept out: "ghar wale" is the
  family, "upay kaam karega" and "will the remedy work" are not work, ಹಣೆ is not ಹಣ; pay, in any
  language's word for it, is both work and money). `offTopic` drops a chip whose subject
  the reply's topic does not allow — marriage and love cross, as do work and studies and money and
  debt; nothing else, and never health — but keeps one about the partner ("Unka career kaisa
  hoga?") under marriage or love. `fallbackOptions` tops a reply up to two chips in its language;
  the southern-language and Marathi lines want a native speaker's read. Exports: `ChipTopic`,
  `topicsOf`, `offTopic`, `fallbackOptions`, `FALLBACK_LANGUAGES`.
- `chat_transits.ts` — v5's "kab" for someone with no birth hour: Guru's stays (weekly samples,
  retrograde blips folded, short dips bridged) occupying or aspecting the topic's house from
  Chandra, within two years; Shani named only when his hard stretch is ending. With the hour, it
  also answers any matter whose dasha window opens more than two years out (`nearerSeasons`; the
  dasha window is kept for "and after that?"). Exports: `stays`, `transitTiming`,
  `describeTransits`, `nearerSeasons`, `nearerWindows` (the same seasons as windows).
- `birth_details.ts` — reading a DOB or hour of birth out of a chat reply (day-first dates in
  every script, Indian digits, "7 baje subah", "12 pm 9 minit", "0630 ಸಂಜೆ"), and whether they
  said the saved one is wrong. `correctsOwnDate` is the one date read unasked: a correction, the
  date of birth named, a word that it is theirs, and nobody else's. Exports: `parseDob`,
  `parseHour`, `correctionIntent`, `correctsOwnDate`.
- `kundali_recast.ts` — re-casts the live kundali after a chat correction, through the Kundali
  screen's own RPC and generation, under its regeneration limit; never re-locks a revealed one.
  Exports: `recastKundali`.
- `chat_timing.ts` — the windows v4 answers "when" with, computed from the dasha rather than
  chosen by the model: per matter (marriage, career, money, home, studies), the soonest
  Antardasha of a karaka or of the lord of its house from Chandra, or a favoured Mahadasha when
  that is more than four years off. No marriage timing under 18, no marriage window before 21, no
  children topic at all. Exports: `TIMING_TOPICS`, `chatTiming`, `describeTiming`, `monthYear`.
- `crisis.ts` — **checked in code before the model on every chat turn.** `detectCrisis` (first-person
  phrase lists in ten languages, tuned on real messages — never bare stems: ಸಾಯ would fire on
  ಸಾಯಂಕಾಲ, "evening"), `crisisReply` (fixed bubbles with Tele-MANAS 14416, iCall, 112),
  `blockedReply` (for a Gemini safety block), `HELPLINES`, `fixedReplyBody` (fills the legacy
  fields so old builds render it). Regional copy still needs a native-speaker review.
- `chat_feedback.ts` — the written answer beside the chat rating. Exports:
  `MAX_FEEDBACK_COMMENT_CHARS` (500 code points, matching the column) and
  `normaliseFeedbackComment`, which tidies whitespace, drops blanks and never splits an emoji.
- `chat_language.ts` — which language Astro answers in. Exports: `LANGUAGES_KEY`,
  `DEFAULT_LANGUAGE_KEY`, `BUILT_IN_LANGUAGES`, `supportedLanguages`, `isSupported`,
  `resolveLanguage`, `languageInstruction`, `languageBlock`. The list is `app_config`, so adding
  a language is a dashboard edit; an unrecognised name still gets a usable generic instruction,
  which is what makes trusting the dashboard safe. `plain: true` (chat v4) swaps in the
  plain-words instructions, which name the common word to use — shaadi, not vivah.
  `detectLanguageSwitch` moves a conversation by request or by script; with `{ v5: true }` it also
  knows the southern scripts and names and tells Marathi from Hindi, while v4 switches exactly as
  it shipped.
- `jyotish.ts` — **the non-LLM astronomy.** Julian day, Sun/Moon longitudes, ayanamsa, sidereal
  rashi/nakshatra chart, Vimshottari dasha. Exports: `julianDay`, `sunLongitude`,
  `moonLongitude`, `ayanamsa`, `toSidereal`, `RASHIS`, `NAKSHATRAS`, `computeChart`,
  `describeChart`, `vimshottariDasha`, `mahadashaSequence`, `antardashaSequence`,
  `PERIOD_HORIZON_YEARS`, `IST_OFFSET_HOURS`. A chart with the hour carries `periods`: the dated
  Antardashas for the next twelve years.

**Analytics**
- `mixpanel.ts` — server-side events the client can never observe (renewals, holds,
  chargebacks). Exports: `configureMixpanel`, `mixpanelConfigured`, `trackServer`, `setProfile`.
- `facebook_capi.ts` — Meta Conversions API, and deliberately one event wide: the recurring debit
  reported as a `Purchase`, which the device can never see. Not a second analytics sink — Meta's
  catalogue is an ad-targeting surface, so the same rule `facebook_analytics.dart` follows on the
  client holds here. Exports: `configureFacebookCapi`, `facebookCapiConfigured`,
  `reportRenewalPurchase`.

**Trial allowance**
- `trial_reading_limit.ts` — one palm and one face reading per trial, checked by both reading
  functions before the daily quota. Counts only `ready` rows (plus `pending` ones younger than
  `PENDING_HOLD_MS`, so concurrent requests cannot both pass) since `trial_started_at`. Exports:
  `ReadingTable`, `TRIAL_LIMIT_KEYS`, `PENDING_HOLD_MS`, `trialReadingLimitFrom`,
  `trialLimitMessage`, `countedReadingsFilter`, `trialReadingsUsed`.

**Push**
- `push.ts` — the pure half of `push-token`: validates a registration body before it reaches the
  table's CHECKs. Exports: `PushPlatform`, `PushRegistration`, `MAX_PUSH_TOKEN_LENGTH`,
  `parsePushRegistration`.

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
