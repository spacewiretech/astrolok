import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:astrolok/widgets/promo_carousel.dart';

/// The promo strip moves on its own, which is the one thing on Home that can keep scheduling
/// work after the user has stopped touching it. These pin down when it may do that — and, just
/// as importantly, when it may not.
///
/// Every wait here is an explicit `pump`, never `pumpAndSettle`: a running carousel schedules a
/// new animation every few seconds, so "settle" is a state it never reaches.
void main() {
  List<PromoSlide> slides(int n) => [
        for (var i = 0; i < n; i++)
          PromoSlide(
            // Deliberately unresolvable. The strip's behaviour is what is under test, and the
            // fallback path keeps these from depending on the real exports.
            image: 'assets/images/not_exported_yet_$i.png',
            label: 'Slide $i',
            onTap: () {},
          ),
      ];

  Widget wrap(Widget child, {bool disableAnimations = false}) {
    return MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );
  }

  double? page(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller?.page;

  /// A second of real frames. `pumpAndSettle` is not an option — a running strip schedules the
  /// next advance forever — and one big `pump` is not enough for a fling to hand off to the
  /// snap that follows it.
  Future<void> pumpASecond(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('the strip advances on its own and wraps back to the first card',
      (tester) async {
    await tester.pumpWidget(wrap(PromoCarousel(slides: slides(3))));
    expect(page(tester), 0);

    // One interval, then long enough for the slide to land.
    for (final expected in [1.0, 2.0]) {
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 600));
      expect(page(tester), expected);
    }

    // The last card wraps rather than dead-ending, which is the whole point of a promo strip.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 900));
    expect(page(tester), 0);
  });

  testWidgets('a swipe gets a full interval before the strip moves again', (tester) async {
    await tester.pumpWidget(wrap(PromoCarousel(slides: slides(3))));

    // Swipe at the three-second mark: the pending advance was one second away.
    await tester.pump(const Duration(seconds: 3));
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await pumpASecond(tester);
    expect(page(tester), 1);

    // That second must not still be counting down, or the card the user chose slides away
    // almost as soon as they land on it.
    await tester.pump(const Duration(seconds: 2));
    expect(page(tester), 1);
  });

  testWidgets('reduce motion stops the strip moving by itself', (tester) async {
    await tester.pumpWidget(
      wrap(PromoCarousel(slides: slides(3)), disableAnimations: true),
    );

    await tester.pump(const Duration(seconds: 20));
    expect(page(tester), 0);

    // Still a carousel, though — the user can drive it themselves.
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await pumpASecond(tester);
    expect(page(tester), 1);
  });

  testWidgets('a single slide neither animates nor draws a dot row', (tester) async {
    await tester.pumpWidget(wrap(PromoCarousel(slides: slides(1))));

    // A lone dot is not an indicator, it is a dot.
    expect(find.byType(AnimatedContainer), findsNothing);

    await tester.pump(const Duration(seconds: 20));
    expect(page(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card at rest is exactly as wide as the strip, gap and all', (tester) async {
    // The gap comes out of the page, not the card: half of it bleeds into the gutter on each
    // side so the promo lines up with the reading rows underneath it.
    await tester.pumpWidget(wrap(
      SizedBox(width: 300, child: PromoCarousel(slides: slides(3))),
    ));

    expect(tester.getSize(find.byType(Material).last).width, 300);
  });
}
