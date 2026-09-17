import 'package:flutter/foundation.dart';

import '../../data/models/birth_place.dart';
import '../../data/models/kundali.dart';

@immutable
class KundaliFormState {
  const KundaliFormState({
    this.birthDate,
    this.birthTime,
    this.place,
    this.existing,
    this.isEdit = false,
    this.busy = false,
    this.error,
    this.placeSearchEnabled = true,
  });

  final DateTime? birthDate;

  /// `HH:MM`, 24-hour, on the birth place's own clock.
  final String? birthTime;
  final BirthPlace? place;

  /// The kundali already cast, when there is one. Changing its details spends a regeneration.
  final KundaliSummary? existing;
  final bool isEdit;
  final bool busy;
  final String? error;
  final bool placeSearchEnabled;

  bool get canSubmit => birthDate != null && birthTime != null && place != null && !busy;

  /// True when submitting would re-cast an existing kundali rather than return it unchanged.
  bool get changesExisting {
    final current = existing;
    if (current == null) return false;
    final birth = current.birth;
    final sameDate = birthDate != null &&
        birthDate!.year == birth.birthDate.year &&
        birthDate!.month == birth.birthDate.month &&
        birthDate!.day == birth.birthDate.day;
    final samePlace = place != null &&
        ((place!.placeId != null && place!.placeId == birth.placeId) || place!.label == birth.placeLabel);
    return !(sameDate && birthTime == birth.birthTime && samePlace);
  }

  KundaliFormState copyWith({
    DateTime? birthDate,
    String? birthTime,
    BirthPlace? place,
    bool? busy,
    String? error,
    bool clearPlace = false,
    bool clearError = false,
  }) {
    return KundaliFormState(
      birthDate: birthDate ?? this.birthDate,
      birthTime: birthTime ?? this.birthTime,
      place: clearPlace ? null : (place ?? this.place),
      existing: existing,
      isEdit: isEdit,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      placeSearchEnabled: placeSearchEnabled,
    );
  }
}
