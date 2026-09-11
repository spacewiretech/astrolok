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

## Scripts the PDF engine cannot set

`pdf` maps codepoints straight to glyphs and ships a shaper for Arabic alone. That is all a Latin
script needs, and it is not enough for an Indic one: `कि` is stored as क then ि but drawn with the
matra first, and `क्ष` is three codepoints that become one glyph. Set that way, Hindi is legible
and visibly wrong.

Readings are written in the user's language now, so `pdf_text_raster.dart` lays the affected text
out with Flutter — which has a real shaper, since it draws the same reading on screen correctly —
and the composition pastes the picture in where the words would have gone. Notes:

- **Only what needs it.** `needsShaping` is about the *text*, not the user's current setting: a
  reading is exported long after it was written. Latin readings produce an empty raster map and
  take the original path, still selectable and a few kilobytes.
- **Not "anything non-ASCII".** Em dashes, curly quotes and `₹` are exactly what the bundled
  Poppins exists to set, and an earlier version of the rule would have turned every English
  export into pictures. The check enumerates the scripts that break instead.
- **Keys must agree across the isolate.** `rasterKey(text, size, width)` is computed by one
  function on both sides. A block described at the wrong size is simply not found, and falls back
  to real text rather than being drawn in the wrong place.
- **It runs on the UI isolate.** `ui.PictureRecorder` needs the engine, which `compute()` has no
  access to — the same constraint that already makes the fonts load before the handover.
- Anything unrenderable is skipped rather than fatal: a share sheet that never opens is worse
  than one block set imperfectly.
