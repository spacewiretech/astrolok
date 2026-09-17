# lib/features/birth

## Purpose

Name and date of birth on one screen, collected **after payment** — the step between the
payment-status screen and Home.

## Files

- `birth_view.dart` — Declares: `BirthView`.
- `birth_viewmodel.dart` — Declares: `BirthState` and `BirthViewModel`,
  `birthViewModelProvider`. The state class lives in this file; there is no `_state.dart`.

## Notes

- Deliberately **not** wrapped in `EntitlementGate`, even though it follows the paywall. The
  paywall does not refresh `entitlementProvider`, so the user held straight after checkout still
  reads as unentitled and a gate would bounce them back to pay again. `save()` routes from the user
  `update-profile` answers with instead, so an account whose payment did not land still ends up on
  `/subscribe`.
- Both fields go in one `update-profile` call through `AuthRepository.saveDetails`, so a failed
  save never leaves a name without a date. The date is consumed server-side by
  `supabase/functions/_shared/jyotish.ts`.
- Name and date prefill from the held user, so a relaunch onto this screen does not ask twice.
- The name field does not autofocus: the keyboard would cover the date wheels.
- The picker is [../../widgets/date_wheel.dart](../../widgets/date_wheel.dart); the day column
  reacts to month and year, so leap years and 29 February before a year is chosen are real
  cases — `test/birth_test.dart` covers exactly that.
