import 'package:astrolok/features/birth/birth_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BirthState.daysInMonth', () {
    test('knows the short months', () {
      expect(const BirthState(month: 4, year: 1990).daysInMonth, 30);
      expect(const BirthState(month: 1, year: 1990).daysInMonth, 31);
    });

    test('gets February right in leap and common years', () {
      expect(const BirthState(month: 2, year: 2024).daysInMonth, 29);
      expect(const BirthState(month: 2, year: 2023).daysInMonth, 28);
      // 1900 is divisible by 4 but not a leap year — the century rule.
      expect(const BirthState(month: 2, year: 1900).daysInMonth, 28);
      expect(const BirthState(month: 2, year: 2000).daysInMonth, 29);
    });

    test('allows 29 February before a year is chosen', () {
      // Otherwise a leap-year birthday could not be entered day-first.
      expect(const BirthState(month: 2).daysInMonth, 29);
    });
  });

  group('BirthState.date', () {
    test('is null until all three parts are chosen', () {
      expect(const BirthState(day: 1, month: 1).date, isNull);
      expect(const BirthState(month: 1, year: 1990).date, isNull);
      expect(const BirthState().date, isNull);
    });

    test('rejects a day the month does not have', () {
      // DateTime(2023, 2, 30) silently becomes 2 March; returning null instead is what stops a
      // wrong birthday being saved.
      expect(const BirthState(day: 30, month: 2, year: 2023).date, isNull);
      expect(const BirthState(day: 31, month: 4, year: 1990).date, isNull);
    });

    test('accepts a real date', () {
      expect(
        const BirthState(day: 29, month: 2, year: 2024).date,
        DateTime(2024, 2, 29),
      );
    });

    test('rejects a date in the future', () {
      final nextYear = DateTime.now().year + 1;
      expect(BirthState(day: 1, month: 1, year: nextYear).date, isNull);
    });

    test('canSave follows date, and is blocked while busy', () {
      expect(const BirthState(day: 4, month: 7, year: 2001).canSave, isTrue);
      expect(const BirthState(day: 31, month: 2, year: 2001).canSave, isFalse);
      expect(const BirthState(day: 4, month: 7, year: 2001, busy: true).canSave, isFalse);
    });
  });

  group('month names', () {
    test('there are twelve, indexed from one', () {
      expect(BirthState.monthNames, hasLength(12));
      expect(BirthState.monthNames[0], 'January');
      expect(BirthState.monthNames[11], 'December');
    });
  });
}
