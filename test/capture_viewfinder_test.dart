import 'package:astrolok/widgets/capture_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The viewfinder's geometry, which is the one thing on the capture screens that cannot be
/// checked by looking at a widget test — and which was wrong on device for both readings: the
/// live picture came out flattened, roughly three times too wide.
///
/// The cause is worth stating, because it is invisible in the code. `CameraPreview` is itself
/// an `AspectRatio`, and under tight constraints an `AspectRatio` does not letterbox — it takes
/// the size it is given and stretches. So the sized box around it decides the shape, and the
/// shape it has to be given is the *drawn* one: upright, a 16:9 sensor fills a 9:16 box.
void main() {
  /// Lays the viewfinder out at a known size and reports the shape the preview was given.
  Future<Size> previewBox(
    WidgetTester tester, {
    required double sensorAspectRatio,
    required Size screen,
  }) async {
    const previewKey = Key('preview');

    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // A fixed width so the square frame is the same size in both orientations and only
          // the screen's shape — which is all `MediaQuery.orientationOf` reads — varies.
          body: SizedBox(
            width: 300,
            child: CaptureViewfinder(
              cameraReady: true,
              cameraFailure: null,
              previewAspectRatio: sensorAspectRatio,
              // Stands in for CameraPreview's inner AspectRatio: it fills whatever it is
              // handed, so its final size is exactly the shape the real texture would be
              // stretched into.
              previewBuilder: () => const SizedBox.expand(key: previewKey),
              framePrompt: 'frame it',
              copy: const CameraCopy(
                denied: '',
                deniedForever: '',
                unavailable: '',
                allow: '',
                openSettings: '',
              ),
              onRetryPermission: _noop,
            ),
          ),
        ),
      ),
    );

    return tester.getSize(find.byKey(previewKey));
  }

  testWidgets('upright, the preview is drawn in the sensor ratio turned on its side', (
    tester,
  ) async {
    final size = await previewBox(
      tester,
      sensorAspectRatio: 16 / 9,
      screen: const Size(400, 800),
    );

    // 9:16, not 16:9. Getting this backwards is the whole bug.
    expect(size.width / size.height, closeTo(9 / 16, 0.001));
  });

  testWidgets('the preview covers the square frame rather than fitting inside it', (
    tester,
  ) async {
    final size = await previewBox(
      tester,
      sensorAspectRatio: 4 / 3,
      screen: const Size(400, 800),
    );

    // A tall preview in a square frame: full width, cropped top and bottom. Anything less
    // would leave gold-bordered bars beside the picture, and — more quietly — would break the
    // centre-square crop in `prepareReadingImage`, which assumes cover into a square.
    expect(size.height, greaterThan(size.width));
    expect(size.width / size.height, closeTo(3 / 4, 0.001));
  });

  testWidgets('sideways, the preview keeps the sensor ratio', (tester) async {
    final size = await previewBox(
      tester,
      sensorAspectRatio: 16 / 9,
      screen: const Size(800, 400),
    );

    expect(size.width / size.height, closeTo(16 / 9, 0.001));
  });
}

void _noop() {}
