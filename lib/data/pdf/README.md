# lib/data/pdf

## Purpose

Composing a reading into a shareable PDF. Shared by the palm and face flows.

## Files

- `reading_pdf.dart` — the composer. Declares: `ReadingPdfSection`, `ReadingPdfRequest`,
  `buildReadingPdf()`. Takes **primitives only** — no models, no `Color`.
- `reading_pdf_requests.dart` — maps a reading onto that request and pre-loads the bundled font
  bytes. Declares: `ReadingPdfAssets`, `PalmReadingPdf` (extension on `PalmReading`),
  `FaceReadingPdf` (extension on `FaceReading`).

## Notes

- **The isolate boundary is the reason these are two files.** `buildReadingPdf` is run under
  `compute()` by the callers — `palm_reading_viewmodel.dart:140` and
  `face_reading_viewmodel.dart:137` — so everything it touches must survive being sent to a
  background isolate. The model-to-request mapping stays here, on the app side of that line.
- `rootBundle` is not available on a background isolate, which is why `ReadingPdfAssets` reads
  the fonts on the UI isolate first and `ReadingPdfRequest` carries **bytes**, not asset paths.
- Fonts come from `assets/fonts/*.ttf`, declared as assets rather than under pubspec's `fonts:`.
  The `pdf` package's built-in Helvetica covers Latin-1 and nothing else, so a reading with a
  curly quote or an em dash would render blank boxes without them.
- The section headings here ("Your Palm lines", "Your Strongest Trait") are **duplicated** from
  `PalmCopy`/`FaceCopy` rather than imported, so the data layer does not reach up into a feature
  folder. Four strings; they change with the export, not with the screen.
- `printing` is deliberately not a dependency — sharing goes through `share_plus`.
- Covered by `test/reading_pdf_test.dart`, which also asserts the fonts are actually bundled.
