# supabase/functions/tests

## Purpose

Unit tests for the backend's pure logic — the normalisers, the entitlement rules and the webhook
signature check. No network, no database.

## Files

- `payments_test.ts` (62 tests) — entitlement boundaries (trial / grace / active / none) and
  webhook signature verification. **The silent-and-expensive logic**, and the largest file here.
- `chat_test.ts` (35) — `normaliseChatReply`: malformed and partial model replies, `ask_for`
  fallback, verdict clamping.
- `face_test.ts` (27) — `normaliseFaceReading`: display ordering, unknown and duplicate part
  keys, server focus winning over the model's echo.
- `jyotish_test.ts` (21) — the astronomy in `jyotish.ts` against **Meeus worked examples**:
  Julian day, Sun/Moon longitude, equinoxes, new and full moon.
- `palm_test.ts` (20) — `normalisePalmReading`: ordering, `is_palm` rejection paths, unknown and
  duplicate lines, incompleteness.
- `mixpanel_test.ts` (11) — server-side Mixpanel: token gating, `$ip` suppression, insert-id
  hashing and dedupe, profile writes.
- `review_account_test.ts` (6) — the store-review sign-in gate, focused on when it must stay
  **off**: half-filled config, placeholder values, malformed input.

## Notes

- Run from the `supabase/` directory:

  ```
  deno test functions/tests/
  ```

  The root README quotes `deno test functions/tests/payments_test.ts` for the payments file
  alone. 182 tests in total.
- Everything under test is deliberately pure, which is why the normalisers in `_shared/` take
  and return plain data rather than touching the DB themselves.
- `mixpanel_test.ts` guards a specific past failure: the server `$insert_id` must key on the
  **occurrence**, not the delivery attempt, or a webhook retry loop floods the project and
  starves every other event. `migrations/20260909000003_payment_events_reported.sql` is the
  schema half of that fix.
- Several files carry no header comment; the group and test names are the documentation.
