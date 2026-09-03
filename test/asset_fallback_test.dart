import 'package:astrolok/app/assets.dart';
import 'package:astrolok/widgets/brand_logo.dart';
import 'package:astrolok/widgets/reading_card.dart';
import 'package:astrolok/widgets/safe_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The artwork is still being exported, so every screen has to lay out correctly without it.
/// These cover the mechanism that makes that true — and keep it true the day an asset is
/// renamed out from under a screen.
void main() {
  setUp(SafeSvg.resetProbeCache);

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('a missing image draws its fallback instead of throwing', (tester) async {
    await tester.pumpWidget(wrap(
      const SafeImage(
        'assets/images/definitely_not_here.png',
        width: 40,
        height: 40,
        fallback: Icon(Icons.star),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('a missing image with no fallback occupies its box and nothing more',
      (tester) async {
    await tester.pumpWidget(wrap(
      const SafeImage('assets/images/definitely_not_here.png', width: 40, height: 40),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The reserved space is what stops the layout shifting when the real file lands.
    expect(tester.getSize(find.byType(SafeImage)), const Size(40, 40));
  });

  testWidgets('a missing svg draws its fallback instead of throwing', (tester) async {
    await tester.pumpWidget(wrap(
      const SafeSvg(
        'assets/icons/definitely_not_here.svg',
        width: 24,
        height: 24,
        fallback: Icon(Icons.bolt),
      ),
    ));
    // Two pumps: the existence probe is a Future, so the fallback appears on the second frame.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.bolt), findsOneWidget);
  });

  testWidgets('the wordmark renders without the om artwork', (tester) async {
    await tester.pumpWidget(wrap(const BrandLogo(size: 40)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Drawn as text, so it is present and legible whether or not the disc art exists.
    expect(find.bySemanticsLabel('Astrolok'), findsWidgets);
  });

  testWidgets('a reading card is fully readable with no thumbnail', (tester) async {
    await tester.pumpWidget(wrap(
      ReadingCard(
        image: Img.readingPalm,
        title: 'Palm Reading',
        subtitle: 'Discover what your palm reveals about your life.',
        fallbackIcon: Icons.back_hand_outlined,
        onTap: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Palm Reading'), findsOneWidget);
    expect(find.text('Discover what your palm reveals about your life.'), findsOneWidget);
    expect(find.byIcon(Icons.back_hand_outlined), findsOneWidget);
    // The affordance has to survive too, or the row reads as inert.
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('AccentHeading reads as one phrase to a screen reader', (tester) async {
    await tester.pumpWidget(wrap(
      const AccentHeading(lead: 'Read Your', accent: 'Palm'),
    ));
    await tester.pump();

    expect(find.bySemanticsLabel('Read Your Palm'), findsOneWidget);
  });
}
