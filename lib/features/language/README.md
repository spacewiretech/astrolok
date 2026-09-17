# lib/features/language

## Purpose

Which language Astro answers in — the one question between OTP and the paywall. It decides the
language of chat replies and palm and face readings (`users.language`, read server-side).

## Files

- `language_view.dart` — Declares: `LanguageView` (with the `options` card list) and
  `LanguageOption`.
- `language_viewmodel.dart` — Declares: `LanguageState`, `LanguageViewModel`,
  `languageViewModelProvider` (autoDispose).

## Notes

- **Tap to advance.** There is no Continue button and nothing is preselected: a tap shows the
  check, saves via `saveChatLanguage`, and routes on `destinationForUser` after a 250ms dwell.
- **Seven cards**: the design's English, Hindi, Telugu, Tamil, Kannada and Malayalam, plus
  Hinglish (the configured default), which has no artwork of its own and borrows Hindi's.
- **Only cards `chat_languages` offers are drawn**, so the save can never be refused by
  `update-profile`. An empty list is the feature's off switch; the screen then goes straight to
  `/subscribe`.
- **Shown only to an unentitled account with no saved language** — see the gate in
  [../splash/](../splash/). Because it is reachable only while the language is null, it fires
  `Signup Completed` exactly once per account; that event moved here from the name step so the ad
  platforms still see registration before purchase.
- Hosts `InviteCodeRow` when `referral_enabled` is on. It has to stay before the paywall:
  `referral-claim` refuses any account that has had a trial.
- **Card art is not exported yet.** `Img.lang*` falls back to a gradient in each card's tint. The
  exports needed are the backgrounds alone, 343x244, with no text or check.
- The titles are set in their own scripts. Poppins covers Latin and Devanagari; Telugu, Tamil,
  Kannada and Malayalam fall back to the device's fonts.
- Tests: `test/language_viewmodel_test.dart`, and the small-phone case in `test/layout_test.dart`.
