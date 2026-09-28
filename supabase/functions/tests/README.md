# supabase/functions/tests

## Purpose

Unit tests for the backend's pure logic — the normalisers, the entitlement rules and the webhook
signature check. No network, no database.

## Files

- `payments_test.ts` (64 tests) — entitlement boundaries (trial / grace / active / none) and
  webhook signature verification. **The silent-and-expensive logic**, and the largest file here.
- `pricing_test.ts` (6) — the ₹499 / ₹299 price split: which plan an account resolves to, the
  fallback to ₹499 while the ₹299 plan has no Cashfree id, and that the split needs both its switch
  and a plan. The other half, a ₹299 authorisation buying a month, is in `payments_test.ts`.
- `chat_feedback_test.ts` (5) — the written answer beside the chat rating: non-text and blank
  input store nothing, whitespace is tidied, and the 500-character cap matches the column without
  splitting an emoji.
- `chat_test.ts` (85) — `normaliseChatReply`: malformed and partial model replies, `ask_for`
  fallback, verdict clamping, rashi keys. The prompt versions (v4's computed windows, hope, plain
  words and shorter body; v3's dasha and remedies; v2 and v1 as rollbacks), the user prompt's
  correction, known-rashi, timing and hour-of-birth blocks, `birthHourAsks` in every language the
  picker offers, and `detectLanguageSwitch`.
- `chat_v5_test.ts` (66) — chat v5: the prompt's rules (the answer's four parts, the offer gone
  and named only to forbid it, the upay the code's, hope only from THE GOOD IN THEIR CHART, a
  window in the first sentence, santan as a period, names refused, one person's mind never read,
  the crisis stop, examples with no real year, no birth detail called saved unless it was), the
  schema (`answer`, `upay`, `sawal`; no `ask_for`, `offer` or `remedy_bubbles`), the normaliser
  (no offer and no yes chip on a new reply, an upay only where code asked for one, a reply giving
  a helpline made a care reply with no upay and no astrology chip), an offer stored before 28 Sep
  still carrying its hidden upay, accepting that upay in every language, the user prompt's
  blocks (the hook riding with the upay, an old offer never brought up), the birth-detail parsers
  and the one date read unasked, Guru/Shani ingress months, the v5 timing topics, and the
  southern-script and Marathi language switches — v5's only, v4 switching as it shipped. Then
  the chips: a menu per topic and chips on every example, `topicsOf` in every script and its
  look-alikes (ghar wale, upay kaam karega, exam, Dhanu, ಹಣೆ, വരുമാനം, the remedy working),
  English "work" and every language's word for pay, the production drift dropped, the partner's
  work kept under marriage, the allowed pairs, the top-up in their language (Marathi too) and
  never on an ask or after a crisis, nothing already asked or passed over offered again, a yes
  that answers the sawal kept, the upay turn's guard, and every fallback chip on its own topic.
  Then the kundali line: on the first reply with the whole chart (rashi and nakshatra, the rashi
  said once), never without the hour, "sthan" only with a place on file, on the turn a captured
  hour completes the chart, once a thread and never after a crisis, "the time ahead is good" only
  with a window inside a year (the softer line otherwise), only the matter they asked about
  named, never above a death, an illness or despair (owed to their next question instead), and
  none of it in v4. And from the review of 28 Sep: a day the Moon changed sign getting the season
  both signs agree on (15 Aug 1998, live), no birth date in twenty years left without a window
  for want of the hour, the rashi a first reply named not named again when the hour comes, and
  the reply to a place checked, with example 9 the only one that speaks of a whole kundali.
- `chat_upay_test.ts` (44) — the v5 answer turn's arc. The upay: India's weekday across midnight
  UTC, every topic on every day giving one concrete upay with a day, a count and a length and
  nothing costly, today's own before today's deity before a named later day (Tuesday's Hanuman
  Chalisa, Monday's 16 Somvar for shaadi, "Kal Mangalvar hai" for a Monday's debt), a morning
  practice after midday starting tomorrow, Hanuman Chalisa and a doctor for health, the exam row
  for a government job, nothing twice in a thread, the dasha and a weak graha breaking ties, and
  the block's facts and hook. Asking for one in every script, and "upay kaise karun?" after one
  not asking for another. The due rule: third answer with enough context, fourth anyway, at once
  when asked, never in care or above a loss, once per topic. The thread's memory (answers,
  upays given — legacy remedy turns too — questions asked) and each turn's topic. The sawal:
  date, then hour, then place, then their situation, each once; a detail called wrong,
  unreadable or without am/pm asked again once; `saysOwnDetailWrong`; no situational question
  twice; a greeting and a care thread; every question's answers passing the chip guard; a place
  said once named. The shape: jawab, kyun, upay, sawal in that order, four messages and 100 words
  at most — the live 109- and 111-word replies cut at a clause, never the "kyonki…", the window,
  the kundali line or the upay — one question, a chat and an ask and a care reply, `ask_for` from
  code only. The prompt's three new blocks, only when due; THE GOOD IN THEIR CHART only true;
  an offer stored before 28 Sep still served; and none of it in v4. The review of 28 Sep: a Mangal
  dosh or a fear getting Hanuman Chalisa every day; the invitation back fitting when the upay
  starts; the next upay waiting for the third or fourth answer since the last; a long thread read
  whole giving no remedy or hook twice; a bare "upay batao" after its answer being the answer; a
  question about the upay with "aur"/"or" not asking for another; a question on no subject asked
  what is behind it (and the love and abroad phrasings read); a death asked about them, not for a
  birth detail; idioms not read as a detail called wrong, and the same detail again changing
  nothing; the place answer's topic from the thread; THE KUNDALI LINE with an upay (the live 106
  and 116 words) under a hundred, and exactly a hundred cut.
- `chat_birth_place_test.ts` (25) — the place of birth told in the v5 chat, with every Places and
  Time Zone call answered by a recorded `fetch` and the database by one that records each table
  it is asked for. A typed town searched India-first (the sentence around it dropped, in Hindi
  too), its top match located and saved with coordinates, zone and `birth_coords_at`, said back
  without "India" and answering the question asked before the details were; a picked row looked
  up by id with the app's session token, and saved in the words it was shown in; typed words
  saved as Google names the place ("Rampur, UP" was seen live). Never searched: a question, a
  subject, "pata nahi", a yes, a greeting, a date or an hour, an unasked town; place words kept
  in a name ("Cape Town"), the southern scripts' sentences and fused "in" dropped, localities
  named for a subject ("Laxmi Nagar") searched, and a place with a question after it searched as
  the place. Not found, Google
  refusing, a bad id or zone: nothing saved, `failed`, and the sawal asks once more for the town
  and state, then lets it go; no failure ever reaches the log with the place in it, and search
  switched off spends nothing. Coordinates on file (or the place id alone) never overwritten nor
  looked up; words never located replaced; a correction replaces it; any "nahi" to the place said
  back — the live "Nahi abhi tak nahi" too — takes it off the account and searches nothing, while
  ಇಲ್ಲಿ ("here") and അല്ലെങ്കിൽ ("or") are not a no. Every flow writes `users` alone: never
  `kundalis`, never a re-cast. The check as the reply's only question, the no-kundli block that
  never calls the kundali complete, and the not-found block; "sthan" only for a located place.
- `mini_kundli_test.ts` (10) — the chat's small kundli: cast only with the date, hour,
  coordinates and zone (a string latitude too); THEIR KUNDALI inside THEIR CHART only then; for
  a fixed chart every graha's rashi, house and dignity, the matter houses' lords and the dasha
  lords pinned and equal to `computeKundaliChart`'s, and the same over 120 births across forty
  years and three clocks; born off India's clock, Chandra left out where the two charts differ and
  the dasha always THEIR CHART's; every strength checked true against the chart (and none for a
  chart with none); the grahas an upay would strengthen, and `upayFor` choosing the kundli's
  graha's day and saying so; and no database, `kundalis` or re-cast in either new module.
- `chat_timing_test.ts` (17) — the windows v4 answers "when" with: karakas and house lords from
  Chandra, the soonest favoured period and never a past one, back-to-back periods merged, a
  closing period not offered as "now", a favoured Mahadasha bridging a long wait, no marriage
  timing under 18 or before 21, and the same answer every time.
- `crisis_test.ts` (11) — the crisis check against real messages from the week before it existed
  (all caught, each in its own language), and the everyday words that must not fire (ಸಾಯಂಕಾಲ,
  "papa mar gaye", "live with me"); every reply carries all three helpline numbers; a safety block
  is told apart from a failure.
- `face_test.ts` (29) — `normaliseFaceReading`: display ordering, unknown and duplicate part
  keys, server focus winning over the model's echo. The reading keeps the no-remedies rule.
- `jyotish_test.ts` (39) — the astronomy in `jyotish.ts` against **Meeus worked examples**:
  Julian day, Sun/Moon longitude, equinoxes, new and full moon. Then 17 October 1999, a day the
  Moon changed sign: no guessed rashi without the hour, a stated rashi settling it, and the
  Vimshottari dasha — its dated sub-periods back to back and agreeing with the running one.
- `palm_test.ts` (21) — `normalisePalmReading`: ordering, `is_palm` rejection paths, unknown and
  duplicate lines, incompleteness.
- `birth_time_test.ts` (6) — `readClock`: AM/PM, raat/shaam/subah in both scripts, night past
  midnight, and a bare "11:55" left unguessed.
- `mixpanel_test.ts` (11) — server-side Mixpanel: token gating, `$ip` suppression, insert-id
  hashing and dedupe, profile writes.
- `facebook_capi_test.ts` (9) — server-side Meta conversions: the three independent ways reporting
  stays off, phone/account-id normalisation and hashing, the seven-day event window, the device
  marker, the test-event code, and that an unreachable Meta never reaches the caller.
- `push_test.ts` (7) — `parsePushRegistration`: the two platforms, the length bound shared with
  the `push_tokens` CHECK, whitespace inside a token, and bodies that are not objects.
- `trial_reading_limit_test.ts` (7) — the per-trial reading allowance: limit parsing and its
  fallback to one, that only a live trial is limited, and that only `ready` (and still-in-flight
  `pending`) readings count — never `rejected` or `failed`.
- `db_test.ts` (6) — the load rules in `db.ts`: a session stamped only when never stamped,
  unreadable or ten minutes stale (read with the lookup, never for an expired or unknown session),
  and `withinCap`, which cuts `astro-chat`'s early history and memory reads to the configured size
  and asks for a second read only when the cap may have cut rows off.
- `review_account_test.ts` (6) — the store-review sign-in gate, focused on when it must stay
  **off**: half-filled config, placeholder values, malformed input.

- `kundali_chart_test.ts` — the full chart against **Meeus worked examples** (sidereal time,
  the mean node, Venus) and published positions (the 2020 great conjunction, sidereal signs of
  Saturn/Jupiter/Rahu, retrograde windows), the ascendant on the eastern horizon, dignity,
  whole-sign houses and the dasha timeline.
- `birth_timezone_test.ts` — India's clock history (+6:30 in 1943, Madras time before 1906) and
  DST gaps and overlaps.
- `kundali_test.ts` — **the reveal lock** (no chart or report before unlock, unentitled or
  unwritten), request parsing, stages, backoff, and the report normaliser (invented evidence
  dropped, years and ages stripped, thin reports retried).
- `place_search_test.ts` — Google Places and Time Zone parsing and error classification.
- `fcm_test.ts` — the service-account JWT (a real RS256 signature against a generated key), the
  message shape, and FCM error classification.
- `notify_test.ts` — IST quiet hours and the daily cap, insert ids inside Mixpanel's 36
  characters, the mid-cancel and billing trigger decisions, and that the route allowlist matches
  the app's `push_payload.dart` (run with `--allow-read` for that check).
- `notification_copy_test.ts` — every campaign in all seven languages: present, in the right
  script, placeholders filled or removed cleanly, within lock-screen lengths.
- `cancellation_feedback_test.ts` — the why-are-you-leaving parser.

## Notes

- Run from the `supabase/` directory:

  ```
  deno test functions/tests/
  ```

  The root README quotes `deno test functions/tests/payments_test.ts` for the payments file
  alone. 575 tests in total.
- Everything under test is deliberately pure, which is why the normalisers in `_shared/` take
  and return plain data rather than touching the DB themselves.
- `mixpanel_test.ts` guards a specific past failure: the server `$insert_id` must key on the
  **occurrence**, not the delivery attempt, or a webhook retry loop floods the project and
  starves every other event. `migrations/20260909000003_payment_events_reported.sql` is the
  schema half of that fix.
- Several files carry no header comment; the group and test names are the documentation.
