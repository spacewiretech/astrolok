import 'package:astrolok/data/camera/palm_camera.dart';
import 'package:astrolok/data/providers.dart';
import 'package:astrolok/features/palm/palm_capture_viewmodel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a started camera reports itself ready', () async {
    // Note on what this does and does not cover. On a device this screen once spun forever:
    // `palmCameraProvider` is autoDispose, and an autoDispose provider with no listener is
    // torn down and rebuilt on the next read, so resolving it per call handed out a different
    // camera each time — one was initialised, and the next `isReady` asked a fresh one that
    // had never been started. The fix is the `ref.watch` in the ViewModel's build.
    //
    // A ProviderContainer does not reproduce that: its disposal timing differs, and this test
    // passes either way — verified by reintroducing the bug. So this asserts the happy path
    // only, and the guard against that specific regression is the comment on `_camera`, not
    // this test.
    var built = 0;

    final container = ProviderContainer(
      overrides: [
        palmCameraProvider.overrideWith((ref) {
          built++;
          return FakePalmCamera(failure: null);
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(palmCaptureViewModelProvider.notifier).startCamera();

    expect(built, 1);
    expect(container.read(palmCaptureViewModelProvider).cameraReady, isTrue);
  });

  test('a camera that never starts settles as unavailable', () async {
    // The simulator path, and any device where the plugin hangs. A viewfinder that spins with
    // no error, no fallback and no gallery button is worse than one that says so.
    final container = ProviderContainer(
      overrides: [
        palmCameraProvider.overrideWith(
          (ref) => FakePalmCamera(failure: CameraFailure.unavailable),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(palmCaptureViewModelProvider.notifier).startCamera();
    final state = container.read(palmCaptureViewModelProvider);

    expect(state.cameraReady, isFalse);
    expect(state.cameraFailure, CameraFailure.unavailable);
    // The screen keys its fallback card off this, so it must report settled rather than
    // leaving the spinner up.
    expect(state.cameraSettled, isTrue);
    expect(state.canCapture, isFalse);
  });

  test('a working camera can capture', () async {
    final container = ProviderContainer(
      overrides: [
        palmCameraProvider.overrideWith(
          (ref) => FakePalmCamera(failure: null, bytes: Uint8List(0)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final model = container.read(palmCaptureViewModelProvider.notifier);
    await model.startCamera();

    expect(container.read(palmCaptureViewModelProvider).canCapture, isTrue);
    expect(container.read(palmCaptureViewModelProvider).cameraSettled, isTrue);
  });
}
