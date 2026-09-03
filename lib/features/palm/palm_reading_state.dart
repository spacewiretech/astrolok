import 'package:flutter/foundation.dart';

import '../../data/models/palm_reading.dart';

/// Shared by the results screen and the per-line detail screen, which show the same reading at
/// two depths and offer the same two actions on it.
@immutable
class PalmReadingState {
  const PalmReadingState({
    this.reading,
    this.image,
    this.loading = true,
    this.speaking = false,
    this.canSpeak = false,
    this.exporting = false,
    this.error,
  });

  final PalmReading? reading;

  /// The captured photo, if it is still on the device. Null after a reinstall or on a second
  /// device — the reading text outlives its picture, and both screens fall back.
  final Uint8List? image;

  final bool loading;
  final bool speaking;

  /// False when the device has no speech engine. The button is left out entirely rather than
  /// shown inert: a control that does nothing reads as a bug, an absent one reads as a design.
  final bool canSpeak;

  final bool exporting;
  final String? error;

  PalmReadingState copyWith({
    PalmReading? reading,
    Uint8List? image,
    bool? loading,
    bool? speaking,
    bool? canSpeak,
    bool? exporting,
    String? error,
    bool clearError = false,
  }) {
    return PalmReadingState(
      reading: reading ?? this.reading,
      image: image ?? this.image,
      loading: loading ?? this.loading,
      speaking: speaking ?? this.speaking,
      canSpeak: canSpeak ?? this.canSpeak,
      exporting: exporting ?? this.exporting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
