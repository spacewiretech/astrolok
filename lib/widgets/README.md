# lib/widgets

## Purpose

The shared design-system widgets: everything more than one screen draws. Presentational only —
**nothing here imports a feature folder**, and nothing here talks to a repository.

## Files

**Asset safety**
- `safe_asset.dart` — loaders that render something sensible when the file is not there yet.
  Declares: `SafeImage` (an `errorBuilder` fallback), `SafeSvg` (bundle probe, plus
  `resetProbeCache()` for tests).

**Brand and surfaces**
- `brand_logo.dart` — Declares: `BrandLogo`, `BrandMark`, `Wordmark`, `AccentHeading`.
- `astral_background.dart` — Declares: `AstralSurface` (which exported ground a screen sits on),
  `AstralBackground`, `ZodiacRing`.
- `sheet_surface.dart` — Declares: `SheetSurface`, `DraggableSheetSurface`.

**Controls**
- `primary_button.dart` — Declares: `ButtonTone` (the design's three treatments),
  `PrimaryButton`, `GoldPillButton`.
- `circle_icon_button.dart` — the round white top-corner button. Declares: `CircleIconButton`.
- `app_snackbar.dart` — Declares: `showAppSnackBar()` (a function, not a widget).

**Input**
- `phone_field.dart` — Declares: `PhoneField`, `TextFieldBox`.
- `otp_field.dart` — Declares: `OtpField`, `OtpFieldController`.
- `date_wheel.dart` — the date-of-birth picker. Declares: `DatePickerCard`, `DateWheelColumn<T>`,
  `DateWheel<T>`.

**Capture** (shared by the palm and face flows)
- `capture_frame.dart` — Declares: `CameraCopy`, `CaptureViewfinder`, `CornerBrackets`,
  `CameraFallback`, `FocusPicker`, `ReadingNotice`, `PrivacyNote`.

**Reading screens**
- `speak_button.dart` — Declares: `SpeakButton`. `audio_bars.dart` — Declares: `AudioBars`.
- `status_chip.dart` — Declares: `StatusChip` ("Strong", "Balanced"), `DetectionPill`.
- `info_card.dart` — Declares: `InfoCard`. `guide_card.dart` — Declares: `GuideCard`.
- `ask_astro_row.dart` — the "Want to know more?" row at the foot of a reading. Declares:
  `AskAstroRow`.

**Home and paywall**
- `promo_carousel.dart` — Declares: `PromoSlide`, `PromoCarousel`.
- `promo_video.dart` — Declares: `PromoVideo`. Takes a **borrowed** `VideoPlayerController` —
  `promoVideoProvider` owns it and warms it during onboarding — so this plays and stops it but
  never disposes it.
- `reading_card.dart` — one "Explore Readings" row. Declares: `ReadingCard`.
- `feature_pills.dart` — Declares: `Feature`, `FeaturePills`.
- `step_indicator.dart` — the 1—2—3 strip. Declares: `StepIndicator`.
- `terms_footer.dart` — Declares: `TermsFooter`; links to `astrolok.app/privacy` and `/terms`.

## Notes

- **`safe_asset.dart` is why `app.dart`'s asset constants are safe to reference before the
  artwork exists.** A renamed or missing file costs its own box and nothing else, rather than
  taking a screen down. `test/asset_fallback_test.dart` guards the mechanism.
- `CaptureViewfinder` converts the camera's **sensor** aspect ratio (landscape on every phone)
  into the upright box it draws — the source of the stretched-preview bug that
  `test/capture_viewfinder_test.dart` covers.
- `capture_frame.dart` is the whole reason palm and face capture stay in sync: both screens are
  assembled from these pieces, with `CameraCopy` supplying the per-flow wording.
- The screens carry **placeholder styling** — several files are marked `UNSKINNED`. Structure
  and behaviour are final; visuals land when the Figma exports do.
- These are the phone app's widgets. The marketing site has its own set in
  [../website/widgets.dart](../website/widgets.dart) and shares none of them.
