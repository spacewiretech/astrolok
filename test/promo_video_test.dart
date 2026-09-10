import 'package:astrolok/data/providers.dart';
import 'package:astrolok/data/repositories/app_config_repository.dart';
import 'package:astrolok/data/supabase/supabase_app_config_repository.dart';
import 'package:astrolok/widgets/promo_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The paywall's promo clip is opened by `promoVideoProvider` and warmed from the onboarding
/// phone sheet, four routes before the screen that shows it.
///
/// Everything asserted here returns *before* a `VideoPlayerController` is constructed, which is
/// what keeps it out of the `video_player` platform channel — a real controller would throw
/// `MissingPluginException` in a unit test, so "the await completed with null" is itself proof
/// that no player was built. The controller-present render branch stays uncovered: the plugin
/// exposes a concrete class rather than an interface, so there is nothing to fake.
void main() {
  ProviderContainer containerFor(String url) {
    final container = ProviderContainer(
      overrides: [
        appConfigRepositoryProvider.overrideWithValue(
          FakeAppConfigRepository({'paywall_video_url': url}),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('promoVideoProvider', () {
    test('serves null when no video is configured', () async {
      // The shipped default, and the normal state before any footage exists.
      expect(defaultAppConfig.configString('paywall_video_url'), isEmpty);
      expect(await containerFor('').read(promoVideoProvider.future), isNull);
    });

    test('serves null for a URL with no scheme', () async {
      // A cell in the dashboard filled in by hand. It must land on the poster, not on an
      // exception thrown behind the paywall's video card.
      expect(await containerFor('not a url').read(promoVideoProvider.future), isNull);
    });

    test('the warm outlives the screen that started it', () async {
      // The regression guard for anyone who later adds `.autoDispose`: onboarding warms this
      // with a single `ref.read` and is then torn down, so a provider that did not survive
      // losing its last listener would hand the paywall a spinner and re-open the player.
      var loads = 0;
      final container = ProviderContainer(
        overrides: [
          appConfigRepositoryProvider.overrideWithValue(_CountingAppConfig(() => loads++)),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(promoVideoProvider, (previous, next) {});
      await container.read(promoVideoProvider.future);
      subscription.close();

      expect(container.read(promoVideoProvider), isA<AsyncData<void>>());
      expect(loads, 1);
    });

    test('releasing it once the paywall is behind us does not re-open it', () async {
      // What Home's invalidate relies on: with nothing listening, Riverpod disposes rather than
      // rebuilds, so freeing the decoder does not quietly start a fresh download.
      var loads = 0;
      final container = ProviderContainer(
        overrides: [
          appConfigRepositoryProvider.overrideWithValue(_CountingAppConfig(() => loads++)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(promoVideoProvider.future);
      container.invalidate(promoVideoProvider);
      await pumpEventQueue();

      expect(loads, 1);
    });
  });

  group('PromoVideo', () {
    Future<void> pump(WidgetTester tester, {required bool loading}) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PromoVideo(controller: null, loading: loading, muted: false),
            ),
          ),
        );

    testWidgets('spins while the player is still on its way', (tester) async {
      await pump(tester, loading: true);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets('falls back to the poster when there is no player', (tester) async {
      // The contract that must never regress: an empty URL, a malformed one, a dead network and
      // an unplayable codec all arrive here, and a paywall that cannot show its video must still
      // take money.
      await pump(tester, loading: false);

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}

/// Counts how many times the config — and so the player behind it — was resolved.
class _CountingAppConfig implements AppConfigRepository {
  _CountingAppConfig(this.onLoad);

  final VoidCallback onLoad;

  @override
  Future<Map<String, String>> load({bool force = false}) async {
    onLoad();
    // Empty, so the provider answers null without reaching for the platform channel. What is
    // being counted is the resolve, not what it resolved to.
    return {...defaultAppConfig, 'paywall_video_url': ''};
  }
}
