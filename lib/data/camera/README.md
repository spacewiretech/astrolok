# lib/data/camera

## Purpose

The camera abstraction behind the palm and face capture screens, and the downscale/crop step
that turns a capture into something worth sending to the model.

## Files

- `reading_camera.dart` — the camera port and its two implementations. Declares:
  `CameraFailure` (enum: `denied`, `deniedForever`, `unavailable`), `ReadingCamera`
  (`failure`, `isReady`, `aspectRatio`, `initialize`, `preview`, `capture`, `dispose`),
  `DeviceCamera`, `FakeReadingCamera`, and the top-level `pickPhotoFromGallery()`.
- `reading_image.dart` — capture post-processing. Declares: `ReadingImage`,
  `prepareReadingImage()`.

## Notes

- `camera` rather than `image_picker`'s camera because the capture screens draw their own square
  viewfinder with corner brackets over the live preview, which the OS camera UI cannot do.
  `image_picker` is the gallery path beside it — and the only way to work on a simulator, which
  has no camera at all.
- Downscaling goes through `flutter_image_compress` (native, off the platform thread — a 12MP
  decode in pure Dart is over a second of jank on a mid-range Android), falling back to the Dart
  `image` package, which only centre-crops the already-small result.
- Shared by both reading flows; the camera instances are provided per-feature as
  `palmCameraProvider` / `faceCameraProvider` in [../providers.dart](../providers.dart).
  `DeviceCamera.lens` is the whole difference between the two capture screens — a palm is shot
  with the back camera, a face with the front.
- `aspectRatio` is the **sensor** ratio (landscape on every phone), not the shape the preview is
  drawn in; `CaptureViewfinder` converts one to the other. Getting this wrong is the stretched-
  preview bug that `test/capture_viewfinder_test.dart` guards.
- Captured photographs never leave the device — the server sends the image to the model and
  drops it. Local retention is [../local/reading_image_store.dart](../local/reading_image_store.dart).
