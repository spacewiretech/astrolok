import 'package:astrolok/data/models/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppUser user({
    required PaymentType type,
    DateTime? trialEndsAt,
    DateTime? currentPeriodEnd,
    bool entitled = false,
  }) {
    return AppUser(
      id: 'u1',
      phone: '9876543210',
      paymentType: type,
      trialEndsAt: trialEndsAt,
      currentPeriodEnd: currentPeriodEnd,
      entitled: entitled,
    );
  }

  final now = DateTime(2026, 9, 3, 12);

  group('recomputeOffline', () {
    test('a trial that ended more than the grace ago is not entitled', () {
      final lapsed = user(
        type: PaymentType.trial,
        trialEndsAt: now.subtract(const Duration(hours: 3)),
        entitled: true,
      );
      expect(lapsed.recomputeOffline(now).entitled, isFalse);
    });

    test('a trial inside the two-hour offline grace is still entitled', () {
      final justOver = user(
        type: PaymentType.trial,
        trialEndsAt: now.subtract(const Duration(minutes: 90)),
        entitled: true,
      );
      expect(justOver.recomputeOffline(now).entitled, isTrue);
    });

    test('a new account with no trial date is never entitled', () {
      // This is the state every signup is in before the mandate is authorised, and it is what
      // puts them on the paywall.
      expect(user(type: PaymentType.trial, entitled: true).recomputeOffline(now).entitled,
          isFalse);
    });

    test('an active mandate that has not billed yet is entitled', () {
      // The window between authorisation and the first debit leaves current_period_end null.
      expect(user(type: PaymentType.active, entitled: true).recomputeOffline(now).entitled,
          isTrue);
    });

    test('a cancelled mandate gets no grace past its paid period', () {
      final cancelled = user(
        type: PaymentType.cancelled,
        currentPeriodEnd: now.subtract(const Duration(minutes: 1)),
        entitled: true,
      );
      expect(cancelled.recomputeOffline(now).entitled, isFalse);
    });

    test('a cancelled mandate inside its paid period is still entitled', () {
      final cancelled = user(
        type: PaymentType.cancelled,
        currentPeriodEnd: now.add(const Duration(days: 10)),
      );
      expect(cancelled.recomputeOffline(now).entitled, isTrue);
    });

    test('expired is never entitled, whatever the dates say', () {
      final expired = user(
        type: PaymentType.expired,
        currentPeriodEnd: now.add(const Duration(days: 30)),
        entitled: true,
      );
      expect(expired.recomputeOffline(now).entitled, isFalse);
    });
  });

  group('fromServer', () {
    test('parses the entitlement payload', () {
      final parsed = AppUser.fromServer({
        'user_id': 'abc',
        'mobile_no': '9876543210',
        'name': 'Asha',
        'dob': '1994-02-28',
        'payment_type': 'active',
        'current_period_end': '2026-10-03T00:00:00Z',
        'entitled': true,
        'billing_state': 'on_hold',
      });

      expect(parsed, isNotNull);
      expect(parsed!.name, 'Asha');
      expect(parsed.birthDate, DateTime(1994, 2, 28));
      expect(parsed.paymentType, PaymentType.active);
      expect(parsed.entitled, isTrue);
      // A warning, not a gate — an on-hold mandate must not revoke access.
      expect(parsed.billingState, BillingState.onHold);
    });

    test('returns null rather than throwing on a payload it does not recognise', () {
      expect(AppUser.fromServer({'oops': true}), isNull);
      expect(AppUser.fromServer('not a map'), isNull);
      expect(AppUser.fromServer(null), isNull);
    });

    test('an unknown payment_type falls back to trial, which grants nothing', () {
      final parsed = AppUser.fromServer({
        'user_id': 'abc',
        'payment_type': 'something_new',
      });
      expect(parsed!.paymentType, PaymentType.trial);
      expect(parsed.recomputeOffline(now).entitled, isFalse);
    });
  });

  group('birth date', () {
    test('round-trips through the wire format', () {
      final date = DateTime(2001, 7, 4);
      expect(AppUser.formatBirthDate(date), '2001-07-04');
      expect(AppUser.parseBirthDate('2001-07-04'), date);
    });

    test('rejects a date that does not exist instead of rolling it forward', () {
      // DateTime(2023, 2, 31) silently becomes 3 March, which would store the wrong birthday.
      expect(AppUser.parseBirthDate('2023-02-31'), isNull);
      expect(AppUser.parseBirthDate('2023-13-01'), isNull);
    });

    test('accepts 29 February in a leap year', () {
      expect(AppUser.parseBirthDate('2024-02-29'), DateTime(2024, 2, 29));
    });

    test('rejects malformed input', () {
      expect(AppUser.parseBirthDate(''), isNull);
      expect(AppUser.parseBirthDate('yesterday'), isNull);
      expect(AppUser.parseBirthDate('2001-07'), isNull);
      expect(AppUser.parseBirthDate(42), isNull);
    });

    test('hasBirthDate drives the onboarding gate', () {
      expect(user(type: PaymentType.trial).hasBirthDate, isFalse);
      expect(
        AppUser(id: 'u1', phone: '9876543210', birthDate: DateTime(1990, 1, 1)).hasBirthDate,
        isTrue,
      );
    });
  });
}
