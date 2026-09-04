import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/entitlement.dart';
import '../../data/pdf/reading_pdf.dart';
import '../../data/pdf/reading_pdf_requests.dart';
import '../../data/providers.dart';
import 'face_copy.dart';
import 'face_reading_state.dart';

/// Backs both the results screen and the per-feature detail screen.
///
/// Keyed by reading id, so opening a feature and coming back does not reload, and two readings
/// never share a state.
class FaceReadingViewModel
    extends AutoDisposeFamilyNotifier<FaceReadingState, String> {
  bool _disposed = false;

  @override
  FaceReadingState build(String readingId) {
    _disposed = false;

    // Resolved here, not inside onDispose: reading a provider from a container that is already
    // tearing down throws, and the dispose callback runs after this one is gone.
    final speech = ref.read(readingSpeechProvider);
    ref.onDispose(() {
      _disposed = true;
      // A reading that keeps talking after the user has left the screen is a one-star review.
      speech.stop();
    });

    _load(readingId);
    return const FaceReadingState();
  }

  Future<void> _load(String readingId) async {
    final reading = await ref.read(faceReadingStoreProvider).byId(readingId);
    if (_disposed) return;

    if (reading == null) {
      // No `error` here. A missing reading is a state of the screen, which renders its own
      // explanation and a way out; putting it in `error` as well would pop a snackbar saying
      // exactly what the screen behind it already says. `error` is for the transient failures
      // — a PDF that would not build — that have nowhere else to appear.
      state = state.copyWith(loading: false);
      return;
    }

    final file = await ref.read(faceImageStoreProvider).file(reading.imageFileName);
    final bytes = await file?.readAsBytes();
    if (_disposed) return;

    state = state.copyWith(reading: reading, image: bytes, loading: false);

    // Asked after the reading is on screen, so a slow engine check never delays it. The button
    // appears once the answer is yes, and simply never appears when it is no.
    final canSpeak = await ref.read(readingSpeechProvider).prepare();
    if (_disposed) return;
    state = state.copyWith(canSpeak: canSpeak);
  }

  /// Starts or stops narration of [text].
  Future<void> toggleSpeech(String text) async {
    final speech = ref.read(readingSpeechProvider);

    if (state.speaking) {
      await speech.stop();
      if (_disposed) return;
      state = state.copyWith(speaking: false);
      return;
    }

    state = state.copyWith(speaking: true);
    await speech.speak(text);
    // Returns when the last chunk finishes, or as soon as something else cancels it — either
    // way the button should stop showing "Stop".
    if (_disposed) return;
    state = state.copyWith(speaking: false);
  }

  /// Stops narration without toggling it on. For leaving the screen.
  Future<void> stopSpeech() async {
    if (!state.speaking) return;
    await ref.read(readingSpeechProvider).stop();
    if (_disposed) return;
    state = state.copyWith(speaking: false);
  }

  /// Builds the PDF and hands it to the system share sheet.
  ///
  /// Sharing rather than a silent save: a file written into the app's sandbox is a file the
  /// user cannot find, and the share sheet is also how "Save to Files" is reached on iOS.
  Future<void> exportPdf() async {
    final reading = state.reading;
    if (reading == null || state.exporting) return;

    state = state.copyWith(exporting: true, clearError: true);

    try {
      // rootBundle is not available on a background isolate, so the assets are read here and
      // the composition itself is what moves off the UI thread.
      final assets = await ReadingPdfAssets.load();
      if (_disposed) return;

      final request = reading.toPdfRequest(
        regular: assets.regular,
        bold: assets.bold,
        image: state.image,
        mark: assets.mark,
        name: ref.read(entitlementProvider)?.name,
      );

      final bytes = await compute(buildReadingPdf, request);
      if (_disposed) return;

      // Written to a real file rather than shared as raw bytes: the share sheet uses the
      // filename as the suggested name. Named per reading, so two exports cannot collide.
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${request.fileName(reading.id)}';
      await File(path).writeAsBytes(bytes, flush: true);
      if (_disposed) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'application/pdf')],
          subject: 'My Astrolok face reading',
        ),
      );
      if (_disposed) return;

      state = state.copyWith(exporting: false);
    } catch (error) {
      debugPrint('[face] pdf export failed: $error');
      if (_disposed) return;
      state = state.copyWith(exporting: false, error: FaceCopy.pdfFailed);
    }
  }
}

final faceReadingViewModelProvider = AutoDisposeNotifierProviderFamily<
    FaceReadingViewModel, FaceReadingState, String>(FaceReadingViewModel.new);
