import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Why the viewfinder is not showing a picture.
enum CameraFailure {
  /// The user said no, but can be asked again.
  denied,

  /// The user said never. Only Settings can undo it, so the button changes accordingly.
  deniedForever,

  /// No camera on this device — which includes every simulator, so this path has to look
  /// deliberate rather than broken.
  unavailable,
}

/// The live camera behind the capture screen.
///
/// An interface, not the plugin used directly, for two reasons: the capture screen is
/// otherwise untestable — there is no camera in a widget test — and the same screen has to
/// render sensibly on a simulator, where [DeviceCamera] always fails and [FakePalmCamera]
/// stands in during development.
abstract interface class PalmCamera {
  /// Null once ready; a reason when the preview cannot be shown.
  CameraFailure? get failure;

  bool get isReady;

  /// The preview's aspect ratio (width / height), needed to crop what the user actually framed.
  double get aspectRatio;

  Future<void> initialize();

  /// The live preview, or a blank box before [initialize] completes.
  Widget preview();

  /// JPEG bytes, full sensor resolution. The caller downscales and crops.
  Future<Uint8List?> capture();

  Future<void> dispose();
}

class DeviceCamera implements PalmCamera {
  DeviceCamera();

  CameraController? _controller;
  CameraFailure? _failure;

  @override
  CameraFailure? get failure => _failure;

  @override
  bool get isReady => _controller?.value.isInitialized ?? false;

  @override
  double get aspectRatio {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return 1;
    return controller.value.aspectRatio;
  }

  /// Nothing here should take this long on real hardware.
  ///
  /// It is a deadline, not a performance target: on the iOS Simulator `availableCameras()`
  /// never completes at all, and without this the viewfinder spins forever with no way out —
  /// no error, no fallback card, no gallery button. A hung camera has to degrade into the
  /// same "unavailable" state as a missing one.
  static const _startupTimeout = Duration(seconds: 5);

  @override
  Future<void> initialize() async {
    try {
      final cameras = await availableCameras().timeout(_startupTimeout);
      if (cameras.isEmpty) {
        _failure = CameraFailure.unavailable;
        return;
      }

      final back = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        // `high` is 720p-ish on most devices, which is already well above the 1024px the
        // model is sent. `max` would spend a second on a 12MP capture and then throw most of
        // it away in the downscale.
        ResolutionPreset.high,
        // No audio: the app never records any, and asking for it would add a microphone
        // permission to a palm reader.
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize().timeout(_startupTimeout);
      // Locked so the preview does not swim while someone lines up their hand.
      await controller.setFlashMode(FlashMode.off);

      _controller = controller;
      _failure = null;
    } on TimeoutException {
      _failure = CameraFailure.unavailable;
      debugPrint('[palm] camera did not start within $_startupTimeout');
    } on CameraException catch (error) {
      _failure = switch (error.code) {
        'CameraAccessDeniedWithoutPrompt' ||
        'CameraAccessRestricted' =>
          CameraFailure.deniedForever,
        'CameraAccessDenied' => CameraFailure.denied,
        _ => CameraFailure.unavailable,
      };
      debugPrint('[palm] camera unavailable: ${error.code} ${error.description}');
    } catch (error) {
      _failure = CameraFailure.unavailable;
      debugPrint('[palm] camera failed to start: $error');
    }
  }

  @override
  Widget preview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.expand();
    }
    return CameraPreview(controller);
  }

  @override
  Future<Uint8List?> capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;

    try {
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();

      // takePicture leaves the frame in a temporary file that nothing else reads. The bytes
      // are in memory now and PalmImageStore writes the copy that matters, so this one is
      // tidied away rather than left in the cache directory. A failure here is not worth
      // failing a capture over.
      try {
        await File(shot.path).delete();
      } catch (_) {}

      return bytes;
    } catch (error) {
      debugPrint('[palm] capture failed: $error');
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}

/// Opens the system gallery. Also the only way to get a photo on a simulator.
Future<Uint8List?> pickPalmFromGallery() async {
  try {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Cheap first pass. The real downscale and crop happen afterwards, but this keeps a
      // 48MP phone photo from being loaded whole.
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    return await picked?.readAsBytes();
  } catch (error) {
    debugPrint('[palm] gallery pick failed: $error');
    return null;
  }
}

/// A stand-in with no plugin behind it.
///
/// Reports [CameraFailure.unavailable] by default, which is the honest answer in a widget test
/// and on a simulator, and exercises the screen's fallback card — the state most likely to be
/// wrong precisely because it is the one nobody looks at.
class FakePalmCamera implements PalmCamera {
  FakePalmCamera({this.failure = CameraFailure.unavailable, this.bytes});

  @override
  CameraFailure? failure;

  /// What [capture] hands back when this fake is set up as working.
  final Uint8List? bytes;

  @override
  bool get isReady => failure == null;

  @override
  double get aspectRatio => 3 / 4;

  @override
  Future<void> initialize() async {}

  @override
  Widget preview() => const ColoredBox(color: Color(0xFF1A1A1A));

  @override
  Future<Uint8List?> capture() async => bytes;

  @override
  Future<void> dispose() async {}
}
