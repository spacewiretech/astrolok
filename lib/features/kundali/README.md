# lib/features/kundali

## Purpose

The birth chart, the fourth reading on Home: date, time and place of birth → a 24-hour wait → the
Detailed Kundali and its PDF. The wait is deliberate — it gives the user a reason to come back, and
the `kundali_ready` push tells them when.

## Files

- `kundali_gate_view.dart` — `/kundali`. Asks the server where the kundali stands and replaces
  itself with the form, the wait or the report. What a push opens. Declares: `KundaliGateView`.
- `kundali_form_state.dart`, `kundali_form_viewmodel.dart`, `kundali_form_view.dart` — "Your
  Kundali": the three fields, Google place search, Generate. Keyed on `edit`; changing an existing
  kundali's details asks first, because it spends a re-cast and restarts the wait.
- `kundali_waiting_view.dart` — the wait: countdown, zodiac wheel, the Moon's rashi and nakshatra
  as a first glimpse, the stage checklist, "Notify me when ready", and the other readings.
- `kundali_report_viewmodel.dart`, `kundali_report_view.dart` — "Detailed Kundali": the North
  Indian chart, planetary highlights, the four life insights (tap for evidence and a tip), the
  dasha timeline, the twelve houses, Ask Astro, and the PDF.
- `kundali_stages.dart` — pure: the checklist items and the countdown and reveal wording.
- `kundali_copy.dart` — every string.

## Notes

- **The server enforces the reveal.** `kundali` refuses `report` with `not_ready` until
  `unlock_at`; the countdown here is a courtesy corrected by the server's clock
  (`KundaliSummary.clockOffset`).
- **Copy says "revealed at", never that the calculation takes a day.** The chart is cast in
  milliseconds and the reading written minutes after the request.
- The last stage — "Your life insights written" — only ticks off when the server says `ready`.
  The first three are timed to the wait.
- The summary is shared through `kundaliSummaryProvider` (`lib/data/kundali_summary.dart`) so the
  Home card, the gate and the waiting screen agree. A revealed reading is cached on the device
  (`KundaliStore`) and opens offline after the first view.
- **Not behind `guardTrialScan`.** A trial account can ask for a kundali; the reveal a day later
  lands after the trial converts, which is the point.
- The card on Home is dark until `kundali_enabled` is switched on in `app_config`.
- Place, coordinates, date and time of birth are never sent to Mixpanel — see
  `MIXPANEL_TRACKING_PLAN.md` §8.5.
