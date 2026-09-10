# lib/features/face

## Purpose

The face reading flow: capture → scan → reading → one feature in full. A deliberate
file-for-file mirror of [../palm/](../palm/); read that folder's README for the shared shape.

## Files

- `face_capture_view.dart` — step one, frame a face. Declares: `FaceCaptureView`,
  `faceRejectionProvider`, `faceLimitProvider`.
- `face_capture_viewmodel.dart` — runs the **front** camera. Declares: `FaceScanRequest`,
  `FaceCaptureViewModel`, `faceCaptureViewModelProvider`.
- `face_capture_state.dart` — Declares: `FaceCaptureState`.
- `face_scan_view.dart` — step two, the wait. Declares: `FaceScanView`.
- `face_scan_viewmodel.dart` — Declares: `FaceScanViewModel`, `faceScanViewModelProvider`.
- `face_scan_state.dart` — Declares: `FacePrepStage`, `FaceScanOutcome`, `FaceScanState`.
- `face_reading_view.dart` — step three. Declares: `FaceReadingView`.
- `face_part_view.dart` — one feature of the face, in full. Declares: `FacePartView`.
- `face_reading_viewmodel.dart` — backs both screens. Declares: `FaceReadingViewModel`,
  `faceReadingViewModelProvider` (family, keyed by reading id).
- `face_reading_state.dart` — Declares: `FaceReadingState`.
- `face_copy.dart` — Declares: `FaceCopy`.

## Notes

- Differences from palm, and they are the only ones: the **front** camera
  (`DeviceCamera(lens: front)`), `FacePartKind` instead of `PalmLineKind`, and the detail route
  is `/face/reading/:id/part/:part`.
- Focus is still typed as `PalmFocus` — the enum is shared, not duplicated. See
  [../../data/models/](../../data/models/).
- `FacePartKind.asset` returns null for forehead and eyebrows: the design ships artwork for only
  four features, and the row draws a Material icon rather than pointing at a file that does not
  exist.
- Same hand-off, same cross-screen rejection/limit providers, same `EntitlementGate` as palm.
- Tests: `face_layout_test.dart`, `face_reading_parse_test.dart`.
