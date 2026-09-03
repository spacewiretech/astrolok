import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/entitlement.dart';
import '../../data/providers.dart';
import 'palm_copy.dart';
import 'palm_pdf.dart';
import 'palm_reading_state.dart';

/// Backs both the results screen and the per-line detail screen.
///
/// Keyed by reading id, so opening a line and coming back does not reload, and two readings
/// never share a state.
class PalmReadingViewModel
    extends AutoDisposeFamilyNotifier<PalmReadingState, String> {
  bool _disposed = false;

  @override
  PalmReadingState build(String readingId) {
    _disposed = false;

    // Resolved here, not inside onDispose: reading a provider from a container that is already
    // tearing down throws, and the dispose callback runs after this one is gone.
    final speech = ref.read(palmSpeechProvider);
    ref.onDispose(() {
      _disposed = true;
      // A reading that keeps talking after the user has left the screen is a one-star review.
      speech.stop();
    });

    _load(readingId);
    return const PalmReadingState();
  }

  Future<void> _load(String readingId) async {
    final reading = await ref.read(palmReadingStoreProvider).byId(readingId);
    if (_disposed) return;

    if (reading == null) {
      // No `error` here. A missing reading is a state of the screen, which renders its own
      // explanation and a way out; putting it in `error` as well would pop a snackbar saying
      // exactly what the screen behind it already says. `error` is for the transient failures
      // — a PDF that would not build — that have nowhere else to appear.
      state = state.copyWith(loading: false);
      return;
    }

    final file = await ref.read(palmImageStoreProvider).file(reading.imageFileName);
    final bytes = await file?.readAsBytes();
    if (_disposed) return;

    state = state.copyWith(reading: reading, image: bytes, loading: false);

    // Asked after the reading is on screen, so a slow engine check never delays it. The button
    // appears once the answer is yes, and simply never appears when it is no.
    final canSpeak = await ref.read(palmSpeechProvider).prepare();
    if (_disposed) return;
    state = state.copyWith(canSpeak: canSpeak);
  }

  /// Starts or stops narration of [text].
  Future<void> toggleSpeech(String text) async {
    final speech = ref.read(palmSpeechProvider);

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
    await ref.read(palmSpeechProvider).stop();
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
      // rootBundle is not available on a background isolate, so the fonts are read here and
      // the composition itself is what moves off the UI thread.
      final regular = await rootBundle.load('assets/fonts/Poppins-Regular.ttf');
      final bold = await rootBundle.load('assets/fonts/Poppins-SemiBold.ttf');

      final bytes = await buildPalmPdf(
        PalmPdfRequest(
          reading: reading,
          regular: regular.buffer.asUint8List(),
          bold: bold.buffer.asUint8List(),
          handImage: state.image,
          name: ref.read(entitlementProvider)?.name,
        ),
      );
      if (_disposed) return;

      // Written to a real file rather than shared as raw bytes: the share sheet uses the
      // filename as the suggested name, and "astrolok-palm-reading.pdf" is what should land in
      // someone's Files app or WhatsApp.
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/astrolok-palm-reading.pdf';
      await File(path).writeAsBytes(bytes, flush: true);
      if (_disposed) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'application/pdf')],
          subject: 'My Astrolok palm reading',
        ),
      );
      if (_disposed) return;

      state = state.copyWith(exporting: false);
    } catch (error) {
      debugPrint('[palm] pdf export failed: $error');
      if (_disposed) return;
      state = state.copyWith(exporting: false, error: PalmCopy.pdfFailed);
    }
  }
}

final palmReadingViewModelProvider = AutoDisposeNotifierProviderFamily<
    PalmReadingViewModel, PalmReadingState, String>(PalmReadingViewModel.new);
