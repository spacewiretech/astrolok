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
  `retrySubscriptionPayment` (manage-payment RETRY; the retry comes back as a new charge),
  `snapshotOf`, the `is*Status` predicates, `webhookSignature`, `constantTimeEquals`,
  `verifyWebhook`, `dedupeKey`, `notificationKey`, `paymentFrom`, `refundFrom`, `disputeFrom`,
  and date helpers `toIstIso`/`addDays`/`addMonths`.
- `subscription_sync.ts` (1043 lines) — **the billing state machine.** Reconciles a subscription
  against Cashfree (the authority) and writes `subscriptions` + `users`. Exports:
  `syncSubscription`, `userUpdatesFor`, `recordPayment`, `reconcilePayments`,
  `refreshPaymentTotals`, `recordRefund`, `recordDispute`, `trackCancellation`,
  `latestSubscription`, `staleSweepCutoff`, `isResumable`, `paymentKind`, `buysAMonth`, `planProps`.
- `payment_retry.ts` — when to retry a debit that failed for insufficient funds: failure day + 2,
  + 4, then the next 5th, skipped when it would not come before the regular monthly charge. Pure;
  `payment-retry` does the I/O. Exports: `planRetry`, `retryPolicy`, `DEFAULT_POLICY`,
  `MAX_ATTEMPTS`, `istDate`, `addDaysToDate`, `onOrAfterDayOfMonth`, `isInsufficientFunds`.
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
  see `effectiveVersion` in `astro_chat.ts`). Every answer has one shape, held in code: the model
  writes `answer` (seedha jawab, kyun), `upay` and `sawal` as fields, and `normaliseChatReplyV5`
  assembles the bubbles in that order — four at most, under 100 words, so 100 is one too many
  (`MAX_BUBBLES`, `MAX_WORDS`; the sawal cut to one question by `oneQuestion`; the upay's why is
  the last thing cut before a "jo…" clause, never its day, count, length or hook). No reply
  offers an upay any more: it comes in the answer when `chat_upay.ts` says it is due, and the
  question at the end is `chat_sawal.ts`'s, which also sets `ask_for` (now `none`, `birth_time`,
  `dob` or `birth_place`) — the model writes neither. An offer stored before 28 Sep still
  renders, keeps its hidden `remedy_bubbles`, and a yes to it is still served by `astro-chat`.
  THE GOOD IN THEIR CHART (`goodInChart`) hands the model only true strengths — a window opening
  within the year, a Guru or Shukra dasha, Guru in a good house from Chandra, Shani easing — and
  takes the mini kundli's as `more` (`mini_kundli.ts`), whose THEIR KUNDALI rides inside THEIR
  CHART once the date, hour, place and zone are all on file. A place just saved is said back as a
  check ("Rampur, Uttar Pradesh — sahi hai na?"), which is that reply's sawal and only question;
  without THEIR KUNDALI the reply never calls the kundali complete; and no date, time or place is
  ever called saved without THE DETAIL THEY JUST GAVE. A window for every
  "kab", love/one-person, names, "fake",
  stated-rashi and crisis rules, few-shot examples with placeholder windows, and follow-up chips
  kept to the topic (a menu per topic in the prompt; `onTopicOptions` in code, which with
  `answers: true` keeps a yes that answers the sawal and drops any chip asking for an upay).
  Once the chart is whole (date and hour on file), THE KUNDALI LINE opens the first reply — or
  the turn whose captured hour completed it — once a thread: their rashi and nakshatra (only the
  nakshatra when the first reply already named the same rashi, `rashiNamed`), "sthan"
  only with a place that is located (`astro-chat` passes `birthPlace` only then — words alone are
  not a place), and "the time ahead looks good" only when some matter's window
  runs now or opens within a year (`kundaliLineFor`, `kundaliLineTurn`; the `kundali_line` marker
  on the stored body). Never above a message about a death, an illness or despair (`notTheMoment`,
  which holds back an upay too): then the reply is marked `kundali_line_owed` and the line waits
  for their next question on a matter the chart reads. A reply that gives a helpline (Tele-MANAS,
  iCall) is a `care` reply, whoever wrote it — no upay, no ask, no astrology chip, no top-up, and
  `astro-chat` flags the thread. `v5Body` fills the legacy fields and stores what the thread must
  remember: `upay_topic`, `upay_id`, `upay_day`, `sawal_id`, `hook`. Exports:
  `chatSystemPromptV5`, `CHAT_SCHEMA_V5`, `ASK_FOR_V5`, `normaliseChatReplyV5`, `oneQuestion`,
  `MAX_BUBBLES`, `MAX_WORDS`, `onTopicOptions`, `v5Body`, `buildUserPromptV5`, `goodInChart`,
  `kundaliLineFor`, `kundaliLineTurn`, `notTheMoment`, `hasWholeChart`, `mattersOpeningSoon`,
  `isRemedyAccept`, `acceptChipFor`, `CHAT_TIMING_RULE_V5`, `CHAT_HEALTH_RULE_V5`,
  `CHAT_REMEDIES_RULE_V5`.
- `chat_upay.ts` — **the v5 upay: when one is due, and which.** Due (`upayDue`): never in a care
  thread or above a loss; at once when they ask (`asksForUpay`, eight languages — and after an
  upay, "upay kaise karun?" or "subah karna hai or shaam ko?" is about that one, and only an
  "another" beside the upay word, "aur koi upay", asks for another); asked for alone after an
  answer on the subject (`onlyAsksForUpay`), it is the answer and the window is not said again
  (`afterAnswer`); else on the third answer of a thread — counted from its last upay, when it had
  one (`answersSinceUpay`) — when the date is known and the hour and place are known or were
  asked for, and on the fourth anyway; one per topic in a thread. `astro-chat` counts all of it
  from the whole thread (`readArc`), not the prompt's twenty rows. Which (`upayFor`): the product team's
  table plus one remedy per day's deity, picked for the topic and today's weekday in India
  (`indiaDay`, from the request's clock) — the topic's own on today's day, else today's deity's
  where it suits the topic (Monday's 16 Somvar for a shaadi question), else the topic's own with
  its day named; a morning practice asked for after midday starts the next morning; a weak graha
  from the mini kundli, then the running Antardasha and Mahadasha lords, break ties; a health
  worry gets Hanuman Chalisa and a doctor only, and a Mangal dosh or a fear, said in any of the
  languages, Hanuman Chalisa every day for 40 days; nothing given twice in a thread. Every remedy has
  a day, a count and a length, and costs no more than a diya or a handful of daal.
  `describeUpay` writes THE UPAY FOR TODAY block with THE HOOK (3-month plan, or a return to see
  the upay work — "kal wapas aaiye" only for one begun today — or none once a session).
  `remediesGiven` (an answer's `upay_topic`, and a legacy `kind: "remedy"` turn), `upaysGiven`,
  `answersIn`, `answersSinceUpay`, `topicsAnswered` and `turnTopic` read the thread. Exports:
  `WEEKDAYS`, `Weekday`, `indiaDay`, `RemedyId`, `Upay`, `upayFor`, `asksForUpay`,
  `onlyAsksForUpay`, `UPAY_WITH_CONTEXT`, `UPAY_BY_THEN`, `UpayDue`, `upayDue`, `remediesGiven`,
  `upaysGiven`, `answersIn`, `answersSinceUpay`, `topicsAnswered`, `turnTopic`, `describeUpay`.
- `chat_sawal.ts` — **the one question a v5 reply ends on**, chosen in code (`sawalFor`): under a
  crisis or a death, an accident or despair (`notTheMoment`), only about them, no birth detail
  asked; after a place just found, the check on it alone; then the date
  of birth when it is missing (twice at most), called wrong or unreadable; the hour when missing
  and not yet asked or declined in the thread, or once more when it came without morning or
  night, could not be read, or was called wrong; the place when it is not located (coordinates,
  or the Google place id that outlives them) and not yet asked, or once more — the town and the
  state — when the map could not find it, they said "nahi" to it said back, or called it wrong
  (ahead of a missing hour: it is what they just answered about); otherwise a question about
  their situation from the topic's menu, as a pandit ji would ask it, never one the thread asked
  (`sawal_id`) — with first-person answers the options follow, each passing the topic's chip
  guard. A greeting, or a message that asks nothing, is asked what they want; a question on no
  subject the chat reads is asked what lies behind it. `describeSawal`
  writes THE QUESTION TO ASK block (naming a place said once but never located). Exports:
  `SituationQuestion`, `SawalContext`, `SawalPlan`, `sawalFor`, `isGreeting`, `asksFor`,
  `sawalsAsked`, `describeSawal`.
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
  Chandra, within two years; Shani named only when his hard stretch is ending. On a day the Moon
  changed sign, with no hour to settle it (44% of birth dates), both signs are read and each
  matter gets the season they share, or the stretch covering both (`transitTimingEither`). With
  the hour, it
  also answers any matter whose dasha window opens more than two years out (`nearerSeasons`; the
  dasha window is kept for "and after that?"). `guruFavoursNow` is Guru's house from Chandra today
  when it is one of his good ones, for THE GOOD IN THEIR CHART. Exports: `stays`, `transitTiming`,
  `transitTimingEither`, `describeTransits`, `nearerSeasons`, `nearerWindows` (the same seasons
  as windows), `guruFavoursNow`.
- `birth_details.ts` — reading a DOB or hour of birth out of a chat reply (day-first dates in
  every script, Indian digits, "7 baje subah", "12 pm 9 minit", "0630 ಸಂಜೆ"), and whether they
  said the saved one is wrong. `correctsOwnDate` is the one date read unasked: a correction, the
  date of birth named, a word that it is theirs, and nobody else's. `saysOwnDetailWrong` is which
  of their own details they call wrong, said outright, for the sawal to ask for again ("shaadi ka
  sahi time kab hai?" is not one) — the date, the hour or, since 28 Sep, the place ("mera janm
  sthan galat hai"); a bare "time", "date" or "jagah" only right after "my", and never in "mera
  time galat chal raha hai", which is a bad phase. `changedDetails` is the part of a captured date
  or hour that differs from the one on file: the same one said again is written nowhere and
  re-casts nothing. Exports: `parseDob`, `parseHour`, `correctionIntent`, `correctsOwnDate`,
  `saysOwnDetailWrong`, `changedDetails`.
- `chat_birth_place.ts` — **the place of birth, told in the v5 chat: read, found on the map,
  saved.** Only when the last reply asked for it (`ask_for: "birth_place"`), when the app sends a
  row picked in its search (`birth_place: {place_id, description, session_token?}` — Details by
  id, with the app's session token, which the app sends), or as a "nahi" to a place just said
  back — which is a no and nothing else: the place comes off the account again (its words back,
  its id, coordinates and zone gone) and nothing is searched. Typed words: plainly-not-a-place
  never searched (a question with nothing before it, a subject the chat reads — a locality like
  "Laxmi Nagar" is not money — "pata nahi", a yes, a date or hour — `readPlace`, `placeQuery`),
  the part before a question when one follows, the words around the town dropped (never "Town"
  in "Cape Town"; the southern scripts' fused "in" too), then Places
  autocomplete (India-biased, cities) → top suggestion → Details → Time Zone, one session token,
  five seconds for the lot. Saves `birth_place` (a pick's own words, or Google's name for typed
  ones, postcode dropped), `birth_place_id`, `birth_lat`/`birth_lng` (four places),
  `birth_tz` and `birth_coords_at` (so `purge_expired` treats them like the form's) — filling a
  blank, or on a correction (`correctionIntent`, or answering again after this thread said one
  back); a located place is otherwise never overwritten nor looked up. Nothing found, or Google
  failing: nothing saved, `failed: "birth_place"`, and the sawal asks once more. Returns the
  refreshed `entitlementPayload`. Never logs the words or the place, never touches `kundalis`,
  never re-casts; honours `place_search_enabled`. `answersPlaceAsk` says a message is the place
  answer, so `astro-chat` takes that turn's topic from the thread. Exports: `pickedPlace`,
  `readPlace`, `placeQuery`, `deniesPlace`, `spokenPlace`, `locatePlace`, `questionBefore`,
  `answersPlaceAsk`, `captureBirthPlace`, `PickedPlace`, `PlaceAnswer`, `LocatedPlace`,
  `PlaceCapture`.
- `mini_kundli.ts` — **the chat's own small kundli** (the product team's "make a small and simple
  kundli … but dont show it to user"). `miniKundli` casts the whole chart with
  `computeKundaliChart` once dob, hour, coordinates and zone are all on file, on the birth place's
  clock (`localToUtc`) — every turn, well under a millisecond, never stored. `describeKundli` is THEIR KUNDALI:
  the lagna and its lord, each graha's rashi, house from the lagna and dignity, the houses THE
  TIMING reads each matter from with their lords (`timingRule`), and where the running dasha's
  lords sit. Chandra is named only where it agrees with the chat's India-clock chart, and the
  dasha is always THEIR CHART's, so the prompt never holds two answers (born abroad, the two
  clocks differ). `kundliStrengths` (a strong lagna lord, exalted and own-sign grahas, Guru or
  Shukra in a kendra or trikona; four at most, only true ones) feeds THE GOOD IN THEIR CHART;
  `weakGrahas` (debilitated, then beside Rahu or Ketu, among the grahas that bear on the matter)
  feeds `upayFor`. Exports: `miniKundli`, `describeKundli`, `kundliStrengths`, `weakGrahas`,
  `KundliDetails`.
- `kundali_recast.ts` — re-casts the live kundali after a chat correction, through the Kundali
  screen's own RPC and generation, under its regeneration limit; never re-locks a revealed one.
  A date or hour only: a place told in the chat never comes here. Exports: `recastKundali`.
- `chat_timing.ts` — the windows v4 answers "when" with, computed from the dasha rather than
  chosen by the model: per matter (marriage, career, money, home, studies), the soonest
  Antardasha of a karaka or of the lord of its house from Chandra, or a favoured Mahadasha when
  that is more than four years off. No marriage timing under 18, no marriage window before 21, no
  children topic at all. Exports: `TIMING_TOPICS`, `chatTiming`, `describeTiming`, `monthYear`,
  and `timingRule` (a matter's karakas and houses, for `mini_kundli.ts` to count from the lagna).
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
