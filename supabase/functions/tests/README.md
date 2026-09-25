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
- `chat_timing_test.ts` (17) — the windows v4 answers "when" with: karakas and house lords from
  Chandra, the soonest favoured period and never a past one, back-to-back periods merged, a
  closing period not offered as "now", a favoured Mahadasha bridging a long wait, no marriage
  timing under 18 or before 21, and the same answer every time.
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
  alone. 368 tests in total.
- Everything under test is deliberately pure, which is why the normalisers in `_shared/` take
  and return plain data rather than touching the DB themselves.
- `mixpanel_test.ts` guards a specific past failure: the server `$insert_id` must key on the
  **occurrence**, not the delivery attempt, or a webhook retry loop floods the project and
  starves every other event. `migrations/20260909000003_payment_events_reported.sql` is the
  schema half of that fix.
- Several files carry no header comment; the group and test names are the documentation.
