import 'package:astrolok/features/onboarding/onboarding_state.dart';
import 'package:astrolok/widgets/otp_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OnboardingState', () {
    test('accepts a valid Indian mobile number and rejects the rest', () {
      expect(OnboardingState.isValidIndianMobile('9876543210'), isTrue);
      expect(OnboardingState.isValidIndianMobile('6123456789'), isTrue);
      // Indian mobile numbers start 6–9.
      expect(OnboardingState.isValidIndianMobile('5123456789'), isFalse);
      expect(OnboardingState.isValidIndianMobile('98765432'), isFalse);
      expect(OnboardingState.isValidIndianMobile('98765432101'), isFalse);
      expect(OnboardingState.isValidIndianMobile('98765abcde'), isFalse);
    });

    test('changing the number drops the outstanding code and its budgets', () {
      const state = OnboardingState(
        phone: '9876543210',
        code: '123456',
        attemptsLeft: 2,
        resendsUsed: 3,
      );

      final cleared = state.clearingOtpSession();
      expect(cleared.code, isEmpty);
      expect(cleared.attemptsLeft, OnboardingState.maxAttempts);
      expect(cleared.resendsUsed, 0);
      // The number survives — it is what the next code will be sent to.
      expect(cleared.phone, '9876543210');
    });

    test('the resend countdown is derived from wall-clock, not from ticks', () {
      // Backgrounding the app stops the ticker; the countdown still has to be right on resume.
      final state = OnboardingState(
        resendAvailableAt: DateTime(2026, 9, 3, 12, 0, 30),
        now: DateTime(2026, 9, 3, 12, 0, 5),
      );
      expect(state.resendIn, const Duration(seconds: 25));
      expect(state.resendCountdownLabel, '0:25');
      expect(state.canResend, isFalse);
    });

    test('a countdown in the past unlocks resend rather than going negative', () {
      final state = OnboardingState(
        resendAvailableAt: DateTime(2026, 9, 3, 12, 0, 0),
        now: DateTime(2026, 9, 3, 12, 5, 0),
      );
      expect(state.resendIn, Duration.zero);
      expect(state.canResend, isTrue);
    });

    test('running out of attempts blocks verify', () {
      const state = OnboardingState(code: '123456', attemptsLeft: 0);
      expect(state.outOfAttempts, isTrue);
      expect(state.canVerify, isFalse);
    });

    test('an exhausted resend budget cannot resend', () {
      const state = OnboardingState(resendsUsed: OnboardingState.maxResends);
      expect(state.resendExhausted, isTrue);
      expect(state.canResend, isFalse);
    });
  });

  group('OnboardingStep', () {
    test('parses the step query parameter', () {
      expect(OnboardingStep.parse('otp'), OnboardingStep.otp);
      expect(OnboardingStep.parse('phone'), OnboardingStep.phone);
    });

    test('falls back to phone, the only always-reachable step', () {
      // The OTP step needs a number already entered, so an unrecognised value must not land on a
      // sheet that cannot function.
      expect(OnboardingStep.parse(null), OnboardingStep.phone);
      expect(OnboardingStep.parse('nonsense'), OnboardingStep.phone);
      // The name was a step here until it moved after payment.
      expect(OnboardingStep.parse('name'), OnboardingStep.phone);
    });
  });

  group('OtpField', () {
    testWidgets('a pasted code fills every box at once', (tester) async {
      // The reason this is one TextField and not six: a per-box maxLength truncates a pasted
      // or SMS-autofilled code to a single character before any handler sees it.
      var latest = '';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OtpField(length: 6, onChanged: (v) => latest = v),
        ),
      ));

      await tester.enterText(find.byType(TextField), '482915');
      await tester.pump();

      expect(latest, '482915');
      for (final digit in ['4', '8', '2', '9', '1', '5']) {
        expect(find.text(digit), findsOneWidget);
      }
    });

    testWidgets('fires onCompleted once when the last digit lands', (tester) async {
      var completions = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OtpField(
            length: 6,
            onChanged: (_) {},
            onCompleted: (_) => completions++,
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField), '48291');
      await tester.pump();
      expect(completions, 0);

      await tester.enterText(find.byType(TextField), '482915');
      await tester.pump();
      expect(completions, 1);

      // A rebuild while the code is still complete must not re-submit it.
      await tester.pump();
      expect(completions, 1);
    });

    testWidgets('non-digits are filtered out', (tester) async {
      var latest = '';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OtpField(length: 6, onChanged: (v) => latest = v),
        ),
      ));

      await tester.enterText(find.byType(TextField), '4a8b2c');
      await tester.pump();
      expect(latest, '482');
    });

    testWidgets('a code filled from the SMS completes like a typed one', (tester) async {
      // The whole point of reading the SMS: the boxes fill and the code submits itself, with no
      // keyboard suggestion to tap.
      final controller = OtpFieldController();
      var latest = '';
      var completions = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OtpField(
            length: 6,
            controller: controller,
            onChanged: (v) => latest = v,
            onCompleted: (_) => completions++,
          ),
        ),
      ));

      controller.fill('482915');
      await tester.pump();

      expect(latest, '482915');
      expect(completions, 1);
      for (final digit in ['4', '8', '2', '9', '1', '5']) {
        expect(find.text(digit), findsOneWidget);
      }
    });

    testWidgets('a filled code is cleaned the way typed input is', (tester) async {
      final controller = OtpFieldController();
      var latest = '';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OtpField(length: 6, controller: controller, onChanged: (v) => latest = v),
        ),
      ));

      controller.fill('48-29 15 77');
      await tester.pump();

      expect(latest, '482915');
    });
  });
}
