# lib/features/birth

## Purpose

Date-of-birth collection, the step between onboarding and the paywall.

## Files

- `birth_view.dart` — Declares: `BirthView`.
- `birth_viewmodel.dart` — Declares: `BirthState` and `BirthViewModel`,
  `birthViewModelProvider`. The state class lives in this file; there is no `_state.dart`.

## Notes

- Deliberately **not** wrapped in `EntitlementGate` — it runs before the paywall, and gating it
  would bounce the user to a screen they have not reached yet.
- The date is what makes a chart possible: it is sent via `saveBirthDate` and consumed
  server-side by `supabase/functions/_shared/jyotish.ts`.
- The picker is [../../widgets/date_wheel.dart](../../widgets/date_wheel.dart); the day column
  reacts to month and year, so leap years and 29 February before a year is chosen are real
  cases — `test/birth_test.dart` covers exactly that.
