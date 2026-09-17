import 'package:astrolok/app/theme/app_theme.dart';
import 'package:astrolok/data/providers.dart';
import 'package:astrolok/data/repositories/app_config_repository.dart';
import 'package:astrolok/features/profile/profile_view.dart';
import 'package:astrolok/widgets/safe_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The language picker overflowed, and could not show every language, once `chat_languages` grew
/// from three to seven: a plain bottom sheet is capped at nine-sixteenths of the screen, and seven
/// rows under a heading and a paragraph are taller than that on most phones.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SafeSvg.resetProbeCache();
  });

  Future<void> openPicker(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appConfigProvider.overrideWith((ref) async => shippedAppConfig)],
        child: MaterialApp(theme: buildAppTheme(), home: const ProfileView()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final row = find.text('Astro language');
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  final languages = shippedAppConfig[chatLanguagesKey]!.split(',');

  for (final (label, size) in [
    ('a small phone', const Size(360, 640)),
    ('an ordinary phone', const Size(393, 852)),
  ]) {
    testWidgets('opens without overflowing on $label, and every language can be reached',
        (tester) async {
      await openPicker(tester, size);
      expect(tester.takeException(), isNull);
      expect(languages, hasLength(7));

      final sheet = find.byType(BottomSheet);
      for (final language in languages) {
        final option = find.descendant(of: sheet, matching: find.text(language));
        await tester.scrollUntilVisible(
          option,
          60,
          scrollable: find.descendant(of: sheet, matching: find.byType(Scrollable)),
        );
        expect(tester.takeException(), isNull, reason: language);

        // On screen and tappable, not merely built below the fold.
        final centre = tester.getCenter(option);
        expect(centre.dy, lessThan(size.height), reason: language);
        expect(tester.hitTestOnBinding(centre).path.any((e) => e.target == tester.renderObject(option)),
            isTrue,
            reason: language);
      }
    });
  }
}
