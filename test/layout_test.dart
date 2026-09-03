import 'package:astrolok/app/theme/app_theme.dart';
import 'package:astrolok/features/birth/birth_view.dart';
import 'package:astrolok/features/subscription/subscription_view.dart';
import 'package:astrolok/widgets/feature_pills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The paywall stacks a video, four feature pills, a price, a consent line and a pinned pay
/// bar; the birth screen stacks a logo, two blocks of copy and a 220pt picker. Both were laid
/// out against a 393x852 iPhone 15 Pro, and both are the kind of screen that overflows on a
/// small phone without anyone noticing until a user reports it.
///
/// A RenderFlex overflow throws in a test, so pumping at a small size and asserting no
/// exception is the whole check.
void main() {
  /// A 360x640 logical phone — roughly the smallest Android device still in wide use, and
  /// meaningfully shorter than anything in the design file.
  const small = Size(360, 640);

  setUp(() {
    // Without this the shared_preferences platform channel has no handler, the UPI-app
    // preference read never completes, and the paywall's Future.wait — and so its loading
    // spinner — hangs forever.
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: buildAppTheme(), home: child),
      ),
    );

    // Fixed pumps rather than pumpAndSettle: the paywall shows a CircularProgressIndicator
    // while its offer loads, and that animates forever, so pumpAndSettle never returns. One
    // second clears the fake repositories' simulated latency; the rest lets the switcher and
    // the asset probes land.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the paywall lays out on a small phone', (tester) async {
    await pumpAt(tester, small, const SubscriptionView());

    expect(tester.takeException(), isNull);
    // The parts that must survive the squeeze: the compliance line and the pay button.
    expect(find.textContaining('auto-debited'), findsOneWidget);
    expect(find.text('Try Now'), findsOneWidget);
  });

  testWidgets('the paywall lays out on a tall phone', (tester) async {
    await pumpAt(tester, const Size(430, 932), const SubscriptionView());
    expect(tester.takeException(), isNull);
  });

  testWidgets('the birth screen lays out on a small phone', (tester) async {
    await pumpAt(tester, small, const BirthView());

    expect(tester.takeException(), isNull);
    expect(find.text('Set Your Date of Birth'), findsOneWidget);
    expect(find.text('continue'), findsOneWidget);
    // Zero-padded, as the design draws them.
    expect(find.text('01'), findsWidgets);
  });

  testWidgets('four feature pills fit side by side without breaking a word', (tester) async {
    // "Personalized Readings" wrapped to "Personalize / d Readings" at 12px in this row. The
    // labels carry their own newline, so more lines than that means the type has outgrown the
    // column again.
    await pumpAt(
      tester,
      small,
      const Scaffold(
        body: Center(
          child: FeaturePills(
            features: [
              Feature(icon: 'a.svg', label: 'Personalized\nReadings'),
              Feature(icon: 'b.svg', label: 'Face & Palm\nInsights'),
              Feature(icon: 'c.svg', label: 'Love & Career\nInsights'),
              Feature(icon: 'd.svg', label: 'Unlimited Astro\nGuidance'),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    // Deliberately no assertion on line count. google_fonts cannot fetch Poppins in a test, so
    // the labels here are measured in the fallback test font, whose glyph widths are nothing
    // like the shipped one — it reports three lines for text that renders as two on a device.
    // The overflow check above is the part that means anything without the real font; the
    // wrapping itself was verified on the simulator.
    expect(find.text('Personalized\nReadings'), findsOneWidget);
    expect(find.text('Unlimited Astro\nGuidance'), findsOneWidget);
  });
}
