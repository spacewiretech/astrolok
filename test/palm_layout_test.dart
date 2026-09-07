import 'package:astrolok/app/theme/app_theme.dart';
import 'package:astrolok/data/camera/reading_camera.dart';
import 'package:astrolok/data/fake/fake_palm_reading.dart';
import 'package:astrolok/data/local/reading_store.dart';
import 'package:astrolok/data/models/palm_reading.dart';
import 'package:astrolok/data/providers.dart';
import 'package:astrolok/features/palm/palm_capture_view.dart';
import 'package:astrolok/features/palm/palm_line_view.dart';
import 'package:astrolok/features/palm/palm_reading_view.dart';
import 'package:astrolok/widgets/safe_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The palm screens all stack a lot vertically — a stepper, a heading, a square viewfinder, a
/// tip row and two buttons on one; a hero card, eight rows and a footer on another — and both
/// are exactly the kind of screen that overflows on a small phone without anyone noticing
/// until a user reports it.
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
  Future<PalmReading> seedReading() async {
    final reading = fakePalmReading(PalmFocus.love);
    await const PalmReadingStore().save(reading);
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
          palmCameraProvider.overrideWithValue(FakeReadingCamera()),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: child),
      ),
    );

    // Fixed pumps rather than pumpAndSettle: the scan screen's ring and pulse repeat forever,
    // so pumpAndSettle would never return.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('capture', () {
    testWidgets('lays out on a small phone', (tester) async {
      await pumpAt(tester, small, const PalmCaptureView());

      expect(tester.takeException(), isNull);
      // The parts that must survive the squeeze.
      expect(find.text('Scan Palm'), findsOneWidget);
      expect(find.textContaining('private and secure'), findsOneWidget);
    });

    testWidgets('lays out on a tall phone', (tester) async {
      await pumpAt(tester, tall, const PalmCaptureView());
      expect(tester.takeException(), isNull);
    });

    testWidgets('says so, and offers no gallery, when there is no camera', (tester) async {
      // The simulator path, and the one a developer sees every day. It has to read as a
      // designed state rather than a broken screen.
      await pumpAt(tester, small, const PalmCaptureView());

      expect(tester.takeException(), isNull);
      expect(find.textContaining("camera isn't available"), findsOneWidget);
      // Camera only on this screen, unlike the face flow. The copy above must not offer an
      // upload there is no button for — the two have to be removed together or not at all.
      expect(find.text('Upload from gallery'), findsNothing);
      expect(find.textContaining('upload'), findsNothing);
    });

    testWidgets('the focus picker offers no health option', (tester) async {
      // Health is deliberately absent: offering it would steer the model at exactly the
      // claims the server prompt forbids, and put a health claim in a store listing.
      await pumpAt(tester, tall, const PalmCaptureView());

      await tester.tap(find.text('Love & Relationships'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Career & Purpose'), findsOneWidget);
      expect(find.textContaining('Health'), findsNothing);
    });
  });

  group('reading', () {
    testWidgets('lays out on a small phone with all eight lines', (tester) async {
      final reading = await seedReading();
      await pumpAt(tester, small, PalmReadingView(readingId: reading.id));

      expect(tester.takeException(), isNull);

      // Almost everything on this screen is below the fold at 360x640 — a hero card and eight
      // rows do not fit on one phone screen — so each assertion scrolls to its target. The
      // overflow check still applies the whole way down, which is the point of the walk.
      final list = find.byType(Scrollable).first;

      await tester.scrollUntilVisible(find.text('Your Palm lines'), 120, scrollable: list);
      expect(find.text('Your Palm lines'), findsOneWidget);

      for (final line in reading.lines) {
        await tester.scrollUntilVisible(find.text(line.title), 120, scrollable: list);
        expect(find.text(line.title), findsOneWidget, reason: line.title);
      }

      await tester.scrollUntilVisible(
        find.text('Ask Astro about your palm'),
        120,
        scrollable: list,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out on a tall phone', (tester) async {
      final reading = await seedReading();
      await pumpAt(tester, tall, PalmReadingView(readingId: reading.id));
      expect(tester.takeException(), isNull);
    });

    testWidgets('says so when the reading is gone', (tester) async {
      // A cold start on a link to a reading the cache no longer holds.
      await pumpAt(tester, small, const PalmReadingView(readingId: 'missing'));

      expect(tester.takeException(), isNull);
      expect(find.textContaining("couldn't find that reading"), findsOneWidget);
    });
  });

  group('line detail', () {
    testWidgets('lays out on a small phone', (tester) async {
      final reading = await seedReading();
      await pumpAt(
        tester,
        small,
        PalmLineView(readingId: reading.id, line: PalmLineKind.heart),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Heart Line'), findsOneWidget);
      // Pinned below the list, so it is on screen whatever the reading's length.
      expect(find.text('Ask Astro about your heart line'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('What it means for you'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('What it means for you'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the longest line still lays out', (tester) async {
      final reading = await seedReading();
      await pumpAt(
        tester,
        small,
        PalmLineView(readingId: reading.id, line: PalmLineKind.marriage),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Relationship Line'), findsOneWidget);
    });

    testWidgets('handles a line name it does not know', (tester) async {
      // Reachable from a stale deep link once a line is renamed server-side.
      final reading = await seedReading();
      await pumpAt(tester, small, PalmLineView(readingId: reading.id, line: null));

      expect(tester.takeException(), isNull);
      expect(find.text('Go back'), findsOneWidget);
    });
  });
}
