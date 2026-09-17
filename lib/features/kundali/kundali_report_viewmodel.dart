import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/entitlement.dart';
import '../../data/kundali_summary.dart';
import '../../data/models/kundali.dart';
import '../../data/pdf/kundali_pdf.dart';
import '../../data/pdf/kundali_pdf_requests.dart';
import '../../data/pdf/pdf_text_raster.dart';
import '../../data/pdf/reading_pdf_requests.dart';
import '../../data/providers.dart';
import '../../data/repositories/kundali_repository.dart';
import 'kundali_copy.dart';

@immutable
class KundaliReportState {
  const KundaliReportState({
    this.reading,
    this.loading = true,
    this.exporting = false,
    this.notReady = false,
    this.loadError,
    this.error,
  });

  final KundaliReading? reading;
  final bool loading;
  final bool exporting;

  /// The server refused: not revealed yet. The view goes back to the wait.
  final bool notReady;

  /// The reading could not be loaded at all. Shown in place of it, with a retry.
  final String? loadError;

  /// A transient failure — a PDF that would not build. Shown as a snackbar.
  final String? error;

  KundaliReportState copyWith({
    KundaliReading? reading,
    bool? loading,
    bool? exporting,
    bool? notReady,
    String? loadError,
    String? error,
    bool clearLoadError = false,
    bool clearError = false,
  }) {
    return KundaliReportState(
      reading: reading ?? this.reading,
      loading: loading ?? this.loading,
      exporting: exporting ?? this.exporting,
      notReady: notReady ?? this.notReady,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// The revealed kundali: loaded from the device when it has been seen before, from the server the
/// first time — which is also the moment the server records it as viewed.
class KundaliReportViewModel extends AutoDisposeNotifier<KundaliReportState> {
  bool _disposed = false;

  @override
  KundaliReportState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    Future.microtask(load);
    return const KundaliReportState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearLoadError: true);
    final userId = ref.read(entitlementProvider)?.id;
    final summary = ref.read(kundaliSummaryProvider).valueOrNull;

    if (userId != null && summary != null) {
      final cached = await ref.read(kundaliStoreProvider).readReading(userId, summary.id);
      if (_disposed) return;
      if (cached != null) {
        state = state.copyWith(reading: cached, loading: false);
        _reportViewed(cached, firstView: false);
        return;
      }
    }

    try {
      final reading = await ref.read(kundaliRepositoryProvider).report();
      if (_disposed) return;
      final firstView = !(summary?.viewed ?? reading.summary.viewed);

      if (userId != null) await ref.read(kundaliStoreProvider).saveReading(userId, reading);
      await ref.read(kundaliSummaryProvider.notifier).set(reading.summary.copyWith(viewed: true));
      if (_disposed) return;

      state = state.copyWith(reading: reading, loading: false);
      _reportViewed(reading, firstView: firstView);
    } on KundaliNotReadyException {
      if (_disposed) return;
      state = state.copyWith(loading: false, notReady: true);
    } on KundaliException catch (error) {
      if (_disposed) return;
      state = state.copyWith(loading: false, loadError: error.message);
    } catch (error) {
      debugPrint('[kundali] report load failed: $error');
      if (_disposed) return;
      state = state.copyWith(loading: false, loadError: KundaliCopy.loadFailed);
    }
  }

  void _reportViewed(KundaliReading reading, {required bool firstView}) {
    final sinceUnlock = reading.summary.serverTime().difference(reading.summary.unlockAt);
    analytics.track(Ev.kundaliViewed, {
      P.kundaliId: reading.id,
      P.firstView: firstView,
      P.hoursSinceUnlock: double.parse((sinceUnlock.inMinutes / 60).toStringAsFixed(1)),
      P.language: reading.language,
    });
  }

  void insightOpened(String key) {
    analytics.track(Ev.kundaliInsightOpened, {P.kundaliId: state.reading?.id, P.insight: key});
  }

  /// Builds the report and hands it to the share sheet, like the palm and face exports.
  Future<void> exportPdf() async {
    final reading = state.reading;
    if (reading == null || state.exporting) return;
    state = state.copyWith(exporting: true, clearError: true);
    final started = DateTime.now();

    try {
      final assets = await ReadingPdfAssets.load();
      if (_disposed) return;

      final request = reading.toPdfRequest(
        regular: assets.regular,
        bold: assets.bold,
        mark: assets.mark,
        name: ref.read(entitlementProvider)?.name,
      );

      final rasters = await rasteriseRuns(request.runs);
      if (_disposed) return;

      final bytes = await compute(buildKundaliPdf, request.rasterised(rasters));
      if (_disposed) return;

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${request.fileName}';
      await File(path).writeAsBytes(bytes, flush: true);
      if (_disposed) return;

      await SharePlus.instance.share(
        ShareParams(files: [XFile(path, mimeType: 'application/pdf')], subject: 'My Astrolok Kundali'),
      );
      if (_disposed) return;

      state = state.copyWith(exporting: false);
      analytics.track(Ev.kundaliPdfExported, {
        P.kundaliId: reading.id,
        P.language: reading.language,
        P.rasterised: rasters.isNotEmpty,
        P.bytes: bytes.length,
        P.ms: DateTime.now().difference(started).inMilliseconds,
      });
    } catch (error) {
      debugPrint('[kundali] pdf export failed: $error');
      analytics.track(Ev.kundaliPdfFailed, {P.error: '$error'});
      if (_disposed) return;
      state = state.copyWith(exporting: false, error: KundaliCopy.pdfFailed);
    }
  }
}

final kundaliReportViewModelProvider =
    AutoDisposeNotifierProvider<KundaliReportViewModel, KundaliReportState>(KundaliReportViewModel.new);
