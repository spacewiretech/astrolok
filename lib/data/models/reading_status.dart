import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// The coloured chip beside a section's title.
///
/// One vocabulary for both readings — the server sends the same six words for a palm line and a
/// face feature — so a chip means the same thing wherever it appears, and one [StatusChip]
/// renders it everywhere.
enum ReadingStatus {
  strong('Strong'),
  balanced('Balanced'),
  deep('Deep'),
  developing('Developing'),
  clear('Clear'),
  faint('Faint');

  const ReadingStatus(this.label);

  final String label;

  Color get color => switch (this) {
        ReadingStatus.strong => AppColors.love,
        ReadingStatus.balanced => AppColors.insight,
        ReadingStatus.deep => AppColors.money,
        ReadingStatus.developing => AppColors.career,
        ReadingStatus.clear => AppColors.gold,
        ReadingStatus.faint => AppColors.muted,
      };

  /// The chip's fill: the same hue, dropped back far enough to read as a wash.
  Color get wash => color.withValues(alpha: 0.12);

  /// Unlike the kind enums this defaults rather than returning null. Losing a whole section — a
  /// paragraph the user waited for — over an unfamiliar chip label would be absurd.
  static ReadingStatus parse(Object? raw) {
    for (final status in ReadingStatus.values) {
      if (status.label == raw) return status;
    }
    return ReadingStatus.balanced;
  }
}
