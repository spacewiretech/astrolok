import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/providers.dart';

/// One entry in the Downloads list: a reading held on this device.
///
/// Palm and face readings are two unrelated types with no shared base, so this flattens the
/// handful of fields the list actually renders rather than making the widget switch on which
/// kind it got. The originals are not kept: everything the row needs is here, and the export
/// re-reads the reading from its own store by id.
@immutable
class SavedReading {
  const SavedReading({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.title,
    required this.focusLabel,
  });

  final String id;
  final SavedReadingKind kind;
  final DateTime createdAt;

  /// The reading's headline, or a stand-in when it has none.
  final String title;

  final String focusLabel;
}

enum SavedReadingKind { palm, face }

/// The device's reading history, newest first.
///
/// Reads the two local caches rather than the server: there is no history endpoint, and the
/// caches are what the results screens already restore from after a cold start. Each keeps ten,
/// so this list is at most twenty rows and needs no paging.
class DownloadsViewModel extends AutoDisposeAsyncNotifier<List<SavedReading>> {
  @override
  Future<List<SavedReading>> build() async {
    final palm = await ref.read(palmReadingStoreProvider).all();
    final face = await ref.read(faceReadingStoreProvider).all();

    final entries = <SavedReading>[
      for (final reading in palm)
        SavedReading(
          id: reading.id,
          kind: SavedReadingKind.palm,
          createdAt: reading.createdAt,
          title: reading.headline.isNotEmpty
              ? reading.headline
              : reading.strongestTrait.title,
          focusLabel: reading.focus.label,
        ),
      for (final reading in face)
        SavedReading(
          id: reading.id,
          kind: SavedReadingKind.face,
          createdAt: reading.createdAt,
          title: reading.headline.isNotEmpty
              ? reading.headline
              : reading.coreTrait.title,
          focusLabel: reading.focus.label,
        ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Split by feature rather than one total: whether a user keeps coming back for palm or for
    // face says which of the two is actually carrying the product.
    analytics.track(Ev.downloadsViewed, {
      P.palmCount: entries.where((e) => e.kind == SavedReadingKind.palm).length,
      P.faceCount: entries.where((e) => e.kind == SavedReadingKind.face).length,
    });

    return entries;
  }
}

final downloadsViewModelProvider =
    AutoDisposeAsyncNotifierProvider<DownloadsViewModel, List<SavedReading>>(
  DownloadsViewModel.new,
);
