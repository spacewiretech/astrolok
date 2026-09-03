import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entitlement.dart';
import '../../data/providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../splash/splash_viewmodel.dart';

/// Day, month and year as three independent picks.
///
/// Held as nullable ints rather than a [DateTime] because the three wheels are filled in any
/// order, and 31 + February is a perfectly ordinary intermediate state that must not be
/// silently rolled forward into 3 March.
@immutable
class BirthState {
  const BirthState({
    this.day,
    this.month,
    this.year,
    this.busy = false,
    this.error,
  });

  final int? day;
  final int? month;
  final int? year;
  final bool busy;
  final String? error;

  /// Nobody alive was born before this, and it bounds the year wheel.
  static const minYear = 1900;

  static int get maxYear => DateTime.now().year;

  static const monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// Days in the currently selected month, accounting for leap years.
  ///
  /// Day 0 of the *next* month is the last day of this one — the standard trick, and the only
  /// one that gets February right without a leap-year rule of its own.
  int get daysInMonth {
    final m = month;
    final y = year;
    if (m == null) return 31;
    // With no year chosen, February has to allow 29 or a leap-year birthday could not be
    // entered at all before picking the year.
    if (y == null) return m == 2 ? 29 : DateTime(2024, m + 1, 0).day;
    return DateTime(y, m + 1, 0).day;
  }

  /// The chosen date, or null while the three parts do not yet make a real one.
  DateTime? get date {
    final d = day;
    final m = month;
    final y = year;
    if (d == null || m == null || y == null) return null;
    if (d > DateTime(y, m + 1, 0).day) return null;

    final parsed = DateTime(y, m, d);
    // A birth date in the future is a typo, not a birthday.
    if (parsed.isAfter(DateTime.now())) return null;
    return parsed;
  }

  bool get canSave => date != null && !busy;

  BirthState copyWith({
    int? day,
    int? month,
    int? year,
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    return BirthState(
      day: day ?? this.day,
      month: month ?? this.month,
      year: year ?? this.year,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class BirthViewModel extends Notifier<BirthState> {
  /// Where the wheels rest before the user touches them.
  ///
  /// A wheel always shows *something* under its selection band, so leaving the state null while
  /// the UI centres 1 January would mean the screen displayed a date it did not consider
  /// chosen — and a Continue button disabled for no visible reason. Seeding the state to match
  /// what is on screen keeps the two honest.
  static const _defaultYear = 2000;

  @override
  BirthState build() {
    // Prefilled when the user already has a date — reaching this screen again after a back
    // navigation should not reset their answer.
    final existing = ref.read(entitlementProvider)?.birthDate;
    if (existing == null) {
      return const BirthState(day: 1, month: 1, year: _defaultYear);
    }
    return BirthState(day: existing.day, month: existing.month, year: existing.year);
  }

  void setDay(int value) => state = state.copyWith(day: value, clearError: true);

  /// Clamps the day when the new month is shorter — picking 31 January then switching to
  /// February must not leave an impossible date on screen.
  void setMonth(int value) {
    var next = state.copyWith(month: value, clearError: true);
    final day = next.day;
    if (day != null && day > next.daysInMonth) {
      next = next.copyWith(day: next.daysInMonth);
    }
    state = next;
  }

  void setYear(int value) {
    var next = state.copyWith(year: value, clearError: true);
    // Same clamp as [setMonth]: 29 February is only a date in some years.
    final day = next.day;
    if (day != null && day > next.daysInMonth) {
      next = next.copyWith(day: next.daysInMonth);
    }
    state = next;
  }

  /// Saves the date and reports where the flow resumes, or null if it stays put.
  Future<SplashDestination?> save() async {
    final date = state.date;
    if (date == null || state.busy) return null;

    state = state.copyWith(busy: true, clearError: true);
    try {
      final user = await ref.read(authRepositoryProvider).saveBirthDate(date);
      ref.read(entitlementProvider.notifier).set(user);
      state = state.copyWith(busy: false);
      return destinationForUser(user);
    } on OtpSendException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      return null;
    } catch (error) {
      debugPrint('[birth] could not save the date of birth: $error');
      state = state.copyWith(
        busy: false,
        error: 'Could not save your date of birth. Please try again.',
      );
      return null;
    }
  }
}

final birthViewModelProvider =
    NotifierProvider<BirthViewModel, BirthState>(BirthViewModel.new);
