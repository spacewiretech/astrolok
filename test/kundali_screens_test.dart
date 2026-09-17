import 'package:astrolok/app/theme/app_theme.dart';
import 'package:astrolok/data/entitlement.dart';
import 'package:astrolok/data/fake/fake_kundali_repository.dart';
import 'package:astrolok/data/kundali_summary.dart';
import 'package:astrolok/data/models/app_user.dart';
import 'package:astrolok/data/models/birth_place.dart';
import 'package:astrolok/data/providers.dart';
import 'package:astrolok/data/repositories/cancellation_feedback_repository.dart';
import 'package:astrolok/features/cancellation/cancellation_reason_view.dart';
import 'package:astrolok/features/cancellation/cancellation_reason_viewmodel.dart';
import 'package:astrolok/features/home/kundali_card.dart';
import 'package:astrolok/features/kundali/kundali_form_view.dart';
import 'package:astrolok/features/kundali/kundali_form_viewmodel.dart';
import 'package:astrolok/features/kundali/kundali_report_view.dart';
import 'package:astrolok/features/kundali/kundali_waiting_view.dart';
import 'package:astrolok/widgets/safe_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The kundali screens and the cancellation screen: that each lays out on a small phone and a tall
/// one without overflowing, and that each shows what its state says it should.
///
/// Reduced motion is on throughout, which stills the zodiac wheel and the stage spinner, and every
/// test ends by replacing the screen so the waiting screen's one-second countdown timer is disposed.

const _place = BirthPlace(placeId: 'fake-tirupati', label: 'Tirupati, Andhra Pradesh, India', latitude: 13.6288, longitude: 79.4192, timeZoneId: 'Asia/Kolkata');

final _user = AppUser(
  id: 'u1',
  phone: '9931145610',
  name: 'Asha',
  birthDate: DateTime(1995, 3, 21),
  birthTime: '10:30',
  paymentType: PaymentType.trial,
  entitled: true,
  chatLanguage: 'English',
  birthPlace: _place,
);

class _SignedIn extends EntitlementNotifier {
  _SignedIn(this.user);

  final AppUser user;

  @override
  AppUser? build() => user;

  // The real one also identifies the analytics profile, claims a referral and registers for push —
  // none of which a widget test should reach.
  @override
  void set(AppUser? user) => state = user;
}

/// The screen's own vertical list, not the horizontal strips inside it.
final page = find.byType(Scrollable).first;

void main() {
  const small = Size(360, 640);
  const tall = Size(430, 932);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SafeSvg.resetProbeCache();
  });

  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    Widget child, {
    required FakeKundaliRepository kundali,
    CancellationFeedbackRepository feedback = const FakeCancellationFeedbackRepository(),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          entitlementProvider.overrideWith(() => _SignedIn(_user)),
          kundaliRepositoryProvider.overrideWithValue(kundali),
          placeRepositoryProvider.overrideWithValue(const FakePlaceRepository()),
          cancellationFeedbackRepositoryProvider.overrideWithValue(feedback),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: child,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Replaces the screen, so its timers are cancelled before the test's pending-timer check.
  Future<void> teardownScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<FakeKundaliRepository> requested({Duration unlockAfter = const Duration(hours: 20)}) async {
    final fake = FakeKundaliRepository(unlockAfter: unlockAfter, latency: false);
    await fake.request(birthDate: DateTime(1995, 3, 21), birthTime: '10:30', place: _place);
    return fake;
  }

  group('form', () {
    for (final size in [small, tall]) {
      testWidgets('lays out prefilled at $size', (tester) async {
        await pumpAt(tester, size, const KundaliFormView(), kundali: FakeKundaliRepository(latency: false));

        expect(tester.takeException(), isNull);
        expect(find.text('Date of Birth'), findsOneWidget);
        // Prefilled from the account.
        expect(find.text('21/03/1995'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Tirupati, Andhra Pradesh, India'), 200, scrollable: page);
        expect(find.text('Time of Birth'), findsOneWidget);
        expect(find.text('10:30 AM'), findsOneWidget);
        expect(find.text('Birth Place'), findsOneWidget);
        expect(find.text('Generate'), findsOneWidget);
        await teardownScreen(tester);
      });
    }
  });

  group('waiting', () {
    for (final size in [small, tall]) {
      testWidgets('lays out with the countdown, the glimpse and the stages at $size', (tester) async {
        final fake = await requested();
        await pumpAt(tester, size, const KundaliWaitingView(), kundali: fake);

        expect(tester.takeException(), isNull);
        expect(find.text('Revealed in'), findsOneWidget);
        await tester.scrollUntilVisible(find.textContaining('Vrischika'), 200, scrollable: page);
        expect(find.textContaining('Vrischika'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Your life insights written'), 200, scrollable: page);
        expect(find.text('Planetary positions cast'), findsOneWidget);
        expect(find.text('Your life insights written'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Chat with Astro'), 300, scrollable: page);
        expect(find.text('Chat with Astro'), findsOneWidget);
        await teardownScreen(tester);
      });
    }
  });

  group('report', () {
    for (final size in [small, tall]) {
      testWidgets('lays out the chart, highlights and insights at $size', (tester) async {
        final fake = await requested(unlockAfter: Duration.zero);
        await pumpAt(tester, size, const KundaliReportView(), kundali: fake);

        expect(tester.takeException(), isNull);
        expect(find.text('Kundali Chart'), findsOneWidget);
        expect(find.text('Asc'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Key Life Insights'), 300, scrollable: page);
        expect(find.text('Love & Relationships'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Download Full Kundali Report'), 400, scrollable: page);
        expect(find.text('Download Full Kundali Report'), findsWidgets);
        await teardownScreen(tester);
      });
    }

    testWidgets('an insight opens with what it was read from', (tester) async {
      final fake = await requested(unlockAfter: Duration.zero);
      await pumpAt(tester, tall, const KundaliReportView(), kundali: fake);

      await tester.scrollUntilVisible(find.text('Love & Relationships'), 300, scrollable: page);
      await tester.tap(find.text('Love & Relationships'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Read from'), findsOneWidget);
      expect(find.text('Moon · 7th house'), findsOneWidget);
      await teardownScreen(tester);
    });
  });

  group('home card', () {
    testWidgets('invites a kundali when there is none', (tester) async {
      await pumpAt(tester, tall, const KundaliCard(), kundali: FakeKundaliRepository(latency: false));
      expect(find.text('Kundali Chart'), findsOneWidget);
      expect(find.text('Discover your life path through your birth chart.'), findsOneWidget);
      await teardownScreen(tester);
    });

    testWidgets('counts down while waiting', (tester) async {
      final fake = await requested();
      await pumpAt(tester, tall, const KundaliCard(), kundali: fake);
      expect(find.textContaining('Ready in '), findsOneWidget);
      await teardownScreen(tester);
    });

    testWidgets('says Ready once revealed and not yet seen', (tester) async {
      final fake = await requested(unlockAfter: Duration.zero);
      await pumpAt(tester, tall, const KundaliCard(), kundali: fake);
      expect(find.text('Ready ✨'), findsOneWidget);
      await teardownScreen(tester);
    });
  });

  group('form view model', () {
    test('prefills, casts, and hands back the waiting screen', () async {
      final fake = FakeKundaliRepository(unlockAfter: const Duration(hours: 24), latency: false);
      final container = ProviderContainer(overrides: [
        entitlementProvider.overrideWith(() => _SignedIn(_user)),
        kundaliRepositoryProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);

      // Auto-disposed providers need a listener to outlive a single read.
      container.listen(kundaliFormViewModelProvider(false), (_, _) {});
      container.listen(kundaliSummaryProvider, (_, _) {});
      final model = container.read(kundaliFormViewModelProvider(false).notifier);
      expect(container.read(kundaliFormViewModelProvider(false)).canSubmit, isTrue);

      final next = await model.submit();
      expect(next, '/kundali/waiting');
      expect(container.read(kundaliSummaryProvider).valueOrNull?.state.name, 'waiting');
    });

    test('refuses without a place, saying what is missing', () async {
      final container = ProviderContainer(overrides: [
        entitlementProvider.overrideWith(() => _SignedIn(AppUser(id: 'u2', phone: '9', birthDate: DateTime(1990), birthTime: '06:00'))),
        kundaliRepositoryProvider.overrideWithValue(FakeKundaliRepository(latency: false)),
      ]);
      addTearDown(container.dispose);

      container.listen(kundaliFormViewModelProvider(false), (_, _) {});
      final model = container.read(kundaliFormViewModelProvider(false).notifier);
      expect(await model.submit(), isNull);
      expect(container.read(kundaliFormViewModelProvider(false)).error, 'Please choose your birth place from the list.');
    });
  });

  group('cancellation reason', () {
    for (final size in [small, tall]) {
      testWidgets('lays out every reason at $size', (tester) async {
        await pumpAt(tester, size, const CancellationReasonView(notificationId: 'n-1'), kundali: FakeKundaliRepository(latency: false));
        expect(tester.takeException(), isNull);
        expect(find.text('Send'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Something else'), 200, scrollable: page);
        expect(find.text('Something else'), findsOneWidget);
        await teardownScreen(tester);
      });
    }

    test('an answer is sent from the push it came from, then thanked', () async {
      final feedback = _RecordingFeedback();
      final container = ProviderContainer(overrides: [
        entitlementProvider.overrideWith(() => _SignedIn(_user)),
        cancellationFeedbackRepositoryProvider.overrideWithValue(feedback),
      ]);
      addTearDown(container.dispose);

      final provider = cancellationReasonViewModelProvider('n-1');
      container.listen(provider, (_, _) {});
      final model = container.read(provider.notifier);
      expect(container.read(provider).canSubmit, isFalse);

      model.choose('too_expensive');
      model.setComment('  Costly for a student  ');
      await model.submit();

      expect(feedback.sent.single, ('too_expensive', 'Costly for a student', 'push', 'n-1'));
      expect(container.read(provider).done, isTrue);
    });

    test('skipping records a dismissal, not a reason', () async {
      final feedback = _RecordingFeedback();
      final container = ProviderContainer(overrides: [
        entitlementProvider.overrideWith(() => _SignedIn(_user)),
        cancellationFeedbackRepositoryProvider.overrideWithValue(feedback),
      ]);
      addTearDown(container.dispose);

      container.listen(cancellationReasonViewModelProvider(null), (_, _) {});
      await container.read(cancellationReasonViewModelProvider(null).notifier).dismiss();
      expect(feedback.sent.single, ('dismissed', null, 'in_app', null));
    });
  });
}

class _RecordingFeedback implements CancellationFeedbackRepository {
  final sent = <(String, String?, String, String?)>[];

  @override
  Future<bool> submit({required String reason, String? comment, String source = 'push', String? notificationId}) async {
    sent.add((reason, comment, source, notificationId));
    return true;
  }
}
