import 'package:astrolok/app/theme/app_theme.dart';
import 'package:astrolok/data/camera/reading_camera.dart';
import 'package:astrolok/data/fake/fake_face_reading.dart';
import 'package:astrolok/data/local/reading_store.dart';
import 'package:astrolok/data/models/face_reading.dart';
import 'package:astrolok/data/fake/fake_palm_reading.dart';
import 'package:astrolok/data/models/palm_reading.dart' show PalmFocus, PalmReading;
import 'package:astrolok/data/providers.dart';
import 'package:astrolok/features/face/face_capture_view.dart';
import 'package:astrolok/features/face/face_part_view.dart';
import 'package:astrolok/features/face/face_reading_view.dart';
import 'package:astrolok/features/profile/downloads_view.dart';
import 'package:astrolok/features/profile/profile_view.dart';
import 'package:astrolok/widgets/safe_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The face screens stack a lot vertically — a stepper, a heading, a focus pill, a square
/// viewfinder, a tip row and two buttons on one; a portrait, a trait card, four chips and six
/// rows on another — and both are exactly the kind of screen that overflows on a small phone
/// without anyone noticing until a user reports it.
///
/// A RenderFlex overflow throws in a test, so pumping at a small size and asserting no
/// exception is the whole check.
void main() {
  /// Roughly the smallest Android still in wide use, and meaningfully shorter than anything in
  /// the design file.
  const small = Size(360, 640);
  const tall = Size(430, 932);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Otherwise a probe result from an earlier case leaks into the next, whose bundle differs.
    SafeSvg.resetProbeCache();
  });

  /// Seeds the cache the reading screens read from, since they are routed to by id.
  Future<FaceReading> seedReading() async {
    final reading = fakeFaceReading(PalmFocus.love);
    await const FaceReadingStore().save(reading);
    return reading;
  }

  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // No camera in a widget test. The unavailable path is also what every simulator
          // shows, so this is the state most worth proving lays out.
          faceCameraProvider.overrideWithValue(FakeReadingCamera()),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: child),
      ),
    );

    // Fixed pumps rather than pumpAndSettle: the scan sweep and the speak button's bars repeat
    // forever, so pumpAndSettle would never return.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('capture', () {
    testWidgets('lays out on a small phone', (tester) async {
      await pumpAt(tester, small, const FaceCaptureView());

      expect(tester.takeException(), isNull);
      // The parts that must survive the squeeze.
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Upload from gallery'), findsOneWidget);
      expect(find.textContaining('private and secure'), findsOneWidget);
    });

    testWidgets('lays out on a tall phone', (tester) async {
      await pumpAt(tester, tall, const FaceCaptureView());
      expect(tester.takeException(), isNull);
    });

    testWidgets('offers the gallery when there is no camera', (tester) async {
      // The simulator path, and the one a developer sees every day. It has to read as a
      // designed state rather than a broken screen — and on this screen it is also the only
      // way to reach the rest of the flow at all.
      await pumpAt(tester, small, const FaceCaptureView());

      expect(tester.takeException(), isNull);
      expect(find.textContaining("camera isn't available"), findsOneWidget);
      expect(find.text('Upload from gallery'), findsOneWidget);
    });

    testWidgets('the focus picker offers no health option', (tester) async {
      // Health is deliberately absent: offering it would steer the model at exactly the
      // claims the server prompt forbids, and put a health claim in a store listing.
      await pumpAt(tester, tall, const FaceCaptureView());

      await tester.tap(find.text('Love & Relationships'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Career & Purpose'), findsOneWidget);
      expect(find.textContaining('Health'), findsNothing);
    });
  });

  group('reading', () {
    testWidgets('lays out on a small phone with all six features', (tester) async {
      final reading = await seedReading();
      await pumpAt(tester, small, FaceReadingView(readingId: reading.id));

      expect(tester.takeException(), isNull);

      // Almost everything on this screen is below the fold at 360x640, so each assertion
      // scrolls to its target. The overflow check still applies the whole way down, which is
      // the point of the walk.
      final list = find.byType(Scrollable).first;

      await tester.scrollUntilVisible(find.text('Your Face Reveals'), 120, scrollable: list);
      expect(find.text('Your Face Reveals'), findsOneWidget);

      for (final part in reading.parts) {
        await tester.scrollUntilVisible(find.text(part.title), 120, scrollable: list);
        expect(find.text(part.title), findsOneWidget, reason: part.title);
      }

      await tester.scrollUntilVisible(
        find.text('Ask Astro about your face'),
        120,
        scrollable: list,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the four trait chips fit side by side without overflowing', (tester) async {
      // Four chips share 360pt less the gutters, which is about 70pt each — narrow enough that
      // "Independent" and "Disciplined" decide the type size.
      final reading = await seedReading();
      await pumpAt(tester, small, FaceReadingView(readingId: reading.id));

      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('Observant'), 120, scrollable: list);

      expect(tester.takeException(), isNull);
      for (final trait in reading.traits) {
        expect(find.text(trait.label), findsOneWidget, reason: trait.label);
      }
    });

    testWidgets('lays out on a tall phone', (tester) async {
      final reading = await seedReading();
      await pumpAt(tester, tall, FaceReadingView(readingId: reading.id));
      expect(tester.takeException(), isNull);
    });

    testWidgets('says so when the reading is gone', (tester) async {
      // A cold start on a link to a reading the cache no longer holds.
      await pumpAt(tester, small, const FaceReadingView(readingId: 'missing'));

      expect(tester.takeException(), isNull);
      expect(find.textContaining("couldn't find that reading"), findsOneWidget);
    });
  });

  group('feature detail', () {
    testWidgets('lays out on a small phone', (tester) async {
      final reading = await seedReading();
      await pumpAt(
        tester,
        small,
        FacePartView(readingId: reading.id, part: FacePartKind.eyes),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Eye Reading'), findsOneWidget);
      // The traditional name sits on its own line under the title, so the title never wraps.
      expect(find.text('Netra'), findsOneWidget);
      expect(find.text('Ask Astro about your eyes'), findsOneWidget);
    });

    testWidgets('the longest feature still lays out', (tester) async {
      final reading = await seedReading();
      final longest = reading.parts.reduce(
        (a, b) => a.detail.length >= b.detail.length ? a : b,
      );

      await pumpAt(
        tester,
        small,
        FacePartView(readingId: reading.id, part: longest.kind),
      );

      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('What it means for you'),
        120,
        scrollable: list,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles a feature name it does not know', (tester) async {
      // A route can outlive the build that understood it.
      final reading = await seedReading();
      await pumpAt(tester, small, FacePartView(readingId: reading.id, part: null));

      expect(tester.takeException(), isNull);
      expect(find.textContaining("couldn't find that reading"), findsOneWidget);
    });
  });

  group('profile', () {
    testWidgets('lays out with no user signed in', (tester) async {
      // `entitlementProvider` is null until the splash resolves a session. The screen has to
      // render rather than assume one.
      await pumpAt(tester, small, const ProfileView());

      expect(tester.takeException(), isNull);
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('Downloads'), findsOneWidget);

      // Below the fold at 360x640, so the walk down is also the overflow check.
      await tester.scrollUntilVisible(
        find.text('Logout'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Logout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows nothing it has no data for', (tester) async {
      // The mock carried these four; none of them is a fact this app holds. See the class
      // comment on ProfileView.
      await pumpAt(tester, tall, const ProfileView());

      expect(find.textContaining('Member ID'), findsNothing);
      expect(find.textContaining('Amount Paid'), findsNothing);
      expect(find.textContaining('App Language'), findsNothing);
    });

    testWidgets('downloads says so when there is nothing saved', (tester) async {
      await pumpAt(tester, small, const DownloadsView());

      expect(tester.takeException(), isNull);
      expect(find.textContaining('No readings saved'), findsOneWidget);
    });

    testWidgets('downloads lists both kinds of reading, newest first', (tester) async {
      await const FaceReadingStore().save(fakeFaceReading(PalmFocus.love));
      // Dated a week back, so the ordering is actually under test rather than incidental.
      await const PalmReadingStore().save(_agedPalmReading());

      await pumpAt(tester, tall, const DownloadsView());

      expect(tester.takeException(), isNull);
      expect(find.text('Face Reading'), findsOneWidget);
      expect(find.text('Palm Reading'), findsOneWidget);

      final face = tester.getTopLeft(find.text('Face Reading')).dy;
      final palm = tester.getTopLeft(find.text('Palm Reading')).dy;
      expect(face, lessThan(palm), reason: 'newest first');
    });
  });
}

/// The canned palm reading, dated a week back.
///
/// Round-tripped through JSON because `createdAt` has no setter and `copyWith` deliberately
/// only carries the image name — the date is a fact about the reading, not a field to edit.
PalmReading _agedPalmReading() {
  final json = fakePalmReading(PalmFocus.career).toJson();
  json['created_at'] =
      DateTime.now().subtract(const Duration(days: 7)).toUtc().toIso8601String();
  return PalmReading.fromServer(json)!;
}
