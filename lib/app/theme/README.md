# lib/app/theme

## Purpose

Design tokens read off the Figma renders, plus the `ThemeData` the app is built with. Screens
reference these names rather than raw hex or magic numbers, so a design correction is an edit
to one file.

## Files

- `app_colors.dart` — the palette: a warm cream ground with a navy/gold pair (navy for
  headings and the logo disc, gold for every call to action). Declares: `AppColors`.
- `app_theme.dart` — repeated geometry plus the theme builder. Declares: `AppShape` (gutter,
  `sheetRadius`/`cardRadius`/`controlRadius`/`pillRadius`, `buttonHeight`, `inputHeight`),
  `buildAppTheme()`.
- `app_typography.dart` — the type scale. Poppins carries headings, labels and buttons; Inter
  carries body copy. Declares: `AppText` (`display`, `sheetTitle`, `section`, `title`,
  `button`, `priceHero`, `body`, `meta`, `input`, `wheelIdle`/`wheelSelected`, `legal`).

## Notes

- `buildAppTheme()` is consumed once, by `AstrolokApp` in [../app.dart](../app.dart).
- Fonts come from `google_fonts` at runtime. The Poppins TTFs in `assets/fonts/` are a
  **separate** copy for the PDF export only — see [../../data/pdf/](../../data/pdf/).
- This theme is the phone app's. The marketing site has its own tokens in
  [../../website/site_theme.dart](../../website/site_theme.dart) and shares nothing but the brand.
