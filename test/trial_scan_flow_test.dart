import 'dart:convert';
import 'dart:typed_data';

import 'package:astrolok/app/router.dart';
import 'package:astrolok/app/theme/app_theme.dart';
import 'package:astrolok/data/camera/reading_camera.dart';
import 'package:astrolok/data/entitlement.dart';
import 'package:astrolok/data/fake/fake_astro_chat.dart';
import 'package:astrolok/data/fake/fake_face_reading.dart';
import 'package:astrolok/data/fake/fake_palm_reading.dart';
import 'package:astrolok/data/local/reading_image_store.dart';
import 'package:astrolok/data/local/trial_scan_tracker.dart';
import 'package:astrolok/data/models/app_user.dart';
import 'package:astrolok/data/models/face_reading.dart';
import 'package:astrolok/data/models/palm_reading.dart';
import 'package:astrolok/data/providers.dart';
import 'package:astrolok/data/repositories/face_repository.dart';
import 'package:astrolok/data/repositories/palm_repository.dart';
import 'package:astrolok/features/face/face_capture_view.dart';
import 'package:astrolok/features/face/face_capture_viewmodel.dart';
import 'package:astrolok/features/face/face_scan_view.dart';
import 'package:astrolok/features/home/home_view.dart';
import 'package:astrolok/features/palm/palm_capture_view.dart';
import 'package:astrolok/features/palm/palm_capture_viewmodel.dart';
import 'package:astrolok/features/palm/palm_scan_view.dart';
import 'package:astrolok/widgets/primary_button.dart';
import 'package:astrolok/widgets/safe_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The trial allowance, walked through the real screens: Home, the capture screen, the scan
/// screen and back.
///
/// A trial account gets one palm reading and one face reading. The second tap on either shows the
/// "Trial scan used" popup instead of opening the camera, and a refusal the device did not see
/// coming — a reinstall wiped its count — shows the same popup on the capture screen.
///
/// The server is stood in by a repository that refuses past the allowance with the exception the
/// real repository maps `trial_limit_reached` to (see `palm_error_test.dart`). The rule on the
/// server itself is tested against a local database, not here.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SafeSvg.resetProbeCache();
  });

  for (final flow in [_palm, _face]) {
    group('${flow.feature} reading', () {
      testWidgets('a trial user gets one, and the second tap shows the popup', (tester) async {
        final palm = _TrialPalmServer();
        final face = _TrialFaceServer();
        final router = await _pumpApp(tester, user: _trialUser(), palm: palm, face: face);
        int calls() => flow.feature == 'palm' ? palm.calls : face.calls;

        // First tap: straight to the camera.
        await _tapCard(tester, flow.card);
        expect(find.byType(flow.captureView), findsOneWidget);
        expect(_button(tester, flow.scanLabel).onPressed, isNotNull);

        // The photo goes off and the reading comes back.
        router.push(flow.scanRoute, extra: flow.request());
        await _waitForScan(tester);
        expect(find.text('${flow.feature} reading ready'), findsOneWidget);
        expect(calls(), 1);
        expect(await const TrialScanTracker().used('trial-user', flow.feature), 1);

        // Second tap: the popup, and no camera.
        router.go(Routes.home);
        await _settle(tester);
        await _tapCard(tester, flow.card);

        expect(find.text('Trial scan used'), findsOneWidget);
        expect(
          find.text(
            'Trial users can scan their palm and face only once each. '
            'Please wait for your trial period to finish to scan again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Your trial ends on'), findsOneWidget);
        expect(find.byType(flow.captureView), findsNothing);
        // Stopped on the device: the server was never asked a second time.
        expect(calls(), 1);

        await tester.tap(find.text('OK'));
        await _settle(tester);
        expect(find.text('Trial scan used'), findsNothing);
        expect(find.byType(HomeView), findsOneWidget);

        // The other reading is its own allowance, still unspent.
        await _tapCard(tester, flow.otherCard);
        expect(find.text('Trial scan used'), findsNothing);
        expect(find.byType(flow.otherCaptureView), findsOneWidget);
      });

      testWidgets('a refusal the device did not expect shows the popup on the capture screen',
          (tester) async {
        // The server already holds this trial's reading; the device's count is empty, as after a
        // reinstall.
        final palm = _TrialPalmServer(allowance: flow.feature == 'palm' ? 0 : 1);
        final face = _TrialFaceServer(allowance: flow.feature == 'face' ? 0 : 1);
        final router = await _pumpApp(tester, user: _trialUser(), palm: palm, face: face);

        // The device does not know, so the camera opens.
        await _tapCard(tester, flow.card);
        expect(find.byType(flow.captureView), findsOneWidget);

        router.push(flow.scanRoute, extra: flow.request());
        await _waitForScan(tester);

        // Back on the capture screen, with the popup over it.
        expect(find.byType(flow.captureView), findsOneWidget);
        expect(find.text('Trial scan used'), findsOneWidget);

        await tester.tap(find.text('OK'));
        await _settle(tester);

        // The server's message stays as a notice, and the button that cannot work is closed.
        expect(find.text(flow.serverMessage), findsOneWidget);
        expect(_button(tester, flow.scanLabel).onPressed, isNull);
        expect(await const TrialScanTracker().used('trial-user', flow.feature), 1);

        // And now the device knows: the next tap on Home is stopped before the camera.
        router.go(Routes.home);
        await _settle(tester);
        await _tapCard(tester, flow.card);
        expect(find.text('Trial scan used'), findsOneWidget);
        expect(find.byType(flow.captureView), findsNothing);
      });

      testWidgets('a paying user is not limited', (tester) async {
        final router = await _pumpApp(
          tester,
          user: _paidUser(),
          palm: _TrialPalmServer(allowance: 99),
          face: _TrialFaceServer(allowance: 99),
        );

        await _tapCard(tester, flow.card);
        router.push(flow.scanRoute, extra: flow.request());
        await _waitForScan(tester);
        expect(find.text('${flow.feature} reading ready'), findsOneWidget);

        router.go(Routes.home);
        await _settle(tester);
        await _tapCard(tester, flow.card);

        expect(find.text('Trial scan used'), findsNothing);
        expect(find.byType(flow.captureView), findsOneWidget);
        expect(await const TrialScanTracker().used('paid-user', flow.feature), 0);
      });
    });
  }
}

// ------------------------------------------------------------------ the two flows

class _Flow {
  const _Flow({
    required this.feature,
    required this.card,
    required this.otherCard,
    required this.captureView,
    required this.otherCaptureView,
    required this.scanLabel,
    required this.scanRoute,
    required this.request,
    required this.serverMessage,
  });

  final String feature;
  final String card;
  final String otherCard;
  final Type captureView;
  final Type otherCaptureView;
  final String scanLabel;
  final String scanRoute;
  final Object Function() request;
  final String serverMessage;
}

const _palmRefusal =
    'Trial users can scan their palm only once. Please wait for your trial period to finish to scan again.';
const _faceRefusal =
    'Trial users can scan their face only once. Please wait for your trial period to finish to scan again.';

final _palm = _Flow(
  feature: 'palm',
  card: 'Palm Reading',
  otherCard: 'Face Reading',
  captureView: PalmCaptureView,
  otherCaptureView: FaceCaptureView,
  scanLabel: 'Scan Palm',
  scanRoute: Routes.palmScan,
  request: () => PalmScanRequest(image: _photo, focus: PalmFocus.love),
  serverMessage: _palmRefusal,
);

final _face = _Flow(
  feature: 'face',
  card: 'Face Reading',
  otherCard: 'Palm Reading',
  captureView: FaceCaptureView,
  otherCaptureView: PalmCaptureView,
  scanLabel: 'Take a photo',
  scanRoute: Routes.faceScan,
  request: () => FaceScanRequest(image: _photo, focus: PalmFocus.love),
  serverMessage: _faceRefusal,
);

/// A real 1×1 PNG, so the scan screen's preview has something decodable to show.
final _photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

// ------------------------------------------------------------------ stand-in servers

/// `palm-reading` as a trial account sees it: [allowance] readings, then the refusal.
class _TrialPalmServer implements PalmRepository {
  _TrialPalmServer({this.allowance = 1});

  final int allowance;
  int calls = 0;

  @override
  Future<PalmReading> read({required Uint8List image, required PalmFocus focus}) async {
    calls++;
    if (calls > allowance) throw const PalmTrialLimitException(_palmRefusal);
    return fakePalmReading(focus);
  }
}

class _TrialFaceServer implements FaceRepository {
  _TrialFaceServer({this.allowance = 1});

  final int allowance;
  int calls = 0;

  @override
  Future<FaceReading> read({required Uint8List image, required PalmFocus focus}) async {
    calls++;
    if (calls > allowance) throw const FaceTrialLimitException(_faceRefusal);
    return fakeFaceReading(focus);
  }
}

// ------------------------------------------------------------------ harness

AppUser _trialUser() => AppUser(
      id: 'trial-user',
      phone: '9931145610',
      name: 'Asha',
      paymentType: PaymentType.trial,
      trialEndsAt: DateTime.now().add(const Duration(hours: 20)),
      entitled: true,
    );

AppUser _paidUser() => AppUser(
      id: 'paid-user',
      phone: '9931145611',
      name: 'Ravi',
      paymentType: PaymentType.active,
      currentPeriodEnd: DateTime.now().add(const Duration(days: 20)),
      entitled: true,
    );

/// Keeps the photo nowhere. The real store touches the documents directory, and real file and
/// platform-channel work never completes inside a widget test's fake clock — so a scan waiting on
/// it would never finish.
class _NoImageStore extends ReadingImageStore {
  _NoImageStore(super.folder);

  @override
  Future<String?> commitPending(String readingId) async => null;

  @override
  Future<void> discardPending() async {}
}

/// Signed in as [user] without `EntitlementNotifier.set`, whose analytics, referral and push
/// hooks have no place in a widget test.
class _SignedIn extends EntitlementNotifier {
  _SignedIn(this.user);

  final AppUser user;

  @override
  AppUser? build() => user;
}

Future<GoRouter> _pumpApp(
  WidgetTester tester, {
  required AppUser user,
  required PalmRepository palm,
  required FaceRepository face,
}) async {
  // Tall enough that every card on Home is on screen without scrolling.
  tester.view.physicalSize = const Size(430, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  Widget stub(String text) => Scaffold(body: Center(child: Text(text)));

  // The real screens for the flow under test, and a stub for every destination beyond it. No
  // `EntitlementGate`: its server round trip is not what is being tested.
  final router = GoRouter(
    initialLocation: Routes.home,
    routes: [
      GoRoute(path: Routes.home, builder: (_, _) => const HomeView()),
      GoRoute(path: Routes.palmCapture, builder: (_, _) => const PalmCaptureView()),
      GoRoute(
        path: Routes.palmScan,
        builder: (_, state) => PalmScanView(request: state.extra as PalmScanRequest?),
      ),
      GoRoute(path: Routes.palmReading, builder: (_, _) => stub('palm reading ready')),
      GoRoute(path: Routes.faceCapture, builder: (_, _) => const FaceCaptureView()),
      GoRoute(
        path: Routes.faceScan,
        builder: (_, state) => FaceScanView(request: state.extra as FaceScanRequest?),
      ),
      GoRoute(path: Routes.faceReading, builder: (_, _) => stub('face reading ready')),
      GoRoute(path: Routes.chat, builder: (_, _) => stub('chat')),
      GoRoute(path: Routes.subscribe, builder: (_, _) => stub('paywall')),
      GoRoute(path: Routes.onboarding, builder: (_, _) => stub('sign in')),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        entitlementProvider.overrideWith(() => _SignedIn(user)),
        palmRepositoryProvider.overrideWithValue(palm),
        faceRepositoryProvider.overrideWithValue(face),
        // Working cameras, so a closed scan button means the limit closed it.
        palmCameraProvider.overrideWithValue(FakeReadingCamera(failure: null)),
        faceCameraProvider.overrideWithValue(FakeReadingCamera(failure: null)),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository(latency: Duration.zero)),
        palmImageStoreProvider.overrideWithValue(_NoImageStore('palm')),
        faceImageStoreProvider.overrideWithValue(_NoImageStore('face')),
      ],
      child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
    ),
  );
  await _settle(tester);
  return router;
}

/// Fixed pumps rather than pumpAndSettle: the carousel and the scan animations repeat forever.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Past the scan screen's minimum dwell, then the navigation it ends with.
Future<void> _waitForScan(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await _settle(tester);
}

Future<void> _tapCard(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await _settle(tester);
}

PrimaryButton _button(WidgetTester tester, String label) =>
    tester.widget<PrimaryButton>(find.widgetWithText(PrimaryButton, label));
