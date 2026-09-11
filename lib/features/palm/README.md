# lib/features/palm

## Purpose

The palm reading flow, in three steps plus a detail screen: capture → scan → reading → one
line in full. This folder and [../face/](../face/) are deliberate mirrors of each other.

## Files

- `palm_capture_view.dart` — step one, frame a palm. Declares: `PalmCaptureView`, and the two
  cross-screen `StateProvider`s `palmRejectionProvider`, `palmLimitProvider`.
- `palm_capture_viewmodel.dart` — runs the back camera and turns a shutter press into a
  request. Declares: `PalmScanRequest`, `PalmCaptureViewModel`, `palmCaptureViewModelProvider`.
- `palm_capture_state.dart` — Declares: `PalmCaptureState`.
- `palm_scan_view.dart` — step two, the wait. Declares: `PalmScanView`.
- `palm_scan_viewmodel.dart` — requests the reading and paces the screen while it is in flight.
  Declares: `PalmScanViewModel`, `palmScanViewModelProvider`.
- `palm_scan_state.dart` — Declares: `PalmPrepStage` (`captured`/`compressed`/`sent`),
  `PalmScanOutcome`, `PalmScanState`.
- `palm_reading_view.dart` — step three, the reading. Declares: `PalmReadingView`.
- `palm_line_view.dart` — one line, in full. Declares: `PalmLineView`.
- `palm_reading_viewmodel.dart` — backs **both** the results and the detail screen. Declares:
  `PalmReadingViewModel`, `palmReadingViewModelProvider` (an
  `AutoDisposeNotifierProviderFamily` keyed by reading id).
- `palm_reading_state.dart` — shared by both of those screens. Declares: `PalmReadingState`.
- `palm_copy.dart` — every word the flow says. Declares: `PalmCopy`.

## Notes

- **The hand-off between capture and scan goes through the route.** The capture VM returns a
  `PalmScanRequest` carrying the *prepared bytes* (not a file path — they are already in memory,
  and re-reading from disk is a second way to fail); `PalmScanView` takes it as a constructor
  argument and `PalmScanViewModel.start()` runs it. The scan VM holds onto the request so a
  retry re-sends the same bytes rather than making the user photograph their hand again.
- `palmRejectionProvider` / `palmLimitProvider` are declared in the **capture view**, not the
  viewmodel — the scan screen writes the failure and pops, and the capture screen reads it on
  the way back.
- This is one of only two features that follow the full `_view`/`_viewmodel`/`_state`/`_copy`
  convention (the other is `face`).
- Everything here sits behind `EntitlementGate`. Repository access is via `palmRepositoryProvider`
  in [../../data/providers.dart](../../data/providers.dart); the five failure cases come from
  `PalmException` and its subclasses.
- Tests: `palm_layout_test.dart`, `palm_camera_test.dart`, `palm_error_test.dart`,
  `palm_progress_test.dart`, `palm_reading_parse_test.dart`.
