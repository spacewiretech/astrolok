import 'package:astrolok/app/theme/app_theme.dart';
import 'package:astrolok/data/models/birth_place.dart';
import 'package:astrolok/widgets/place_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Birth-place search bills per session, not per keystroke — but only if the session token is
/// reused across one search and the pick that ends it, and only if typing is debounced.
void main() {
  test('session tokens are version-4 UUIDs', () {
    final token = newPlaceSessionToken();
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(token), isTrue);
    expect(newPlaceSessionToken(), isNot(token));
  });

  testWidgets('typing is debounced, one token covers the search and the pick, and a pick starts a new one', (tester) async {
    final searches = <(String, String)>[];
    final picks = <(String, String)>[];
    var tokens = 0;
    String? selected;

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => PlaceSearchField(
            selectedLabel: selected,
            tokenFactory: () => 'token-${++tokens}',
            search: (query, token) async {
              searches.add((query, token));
              return const [PlaceSuggestion(placeId: 'p1', primary: 'Tirupati', secondary: 'Andhra Pradesh, India')];
            },
            onChosen: (suggestion, token, rank, count) async {
              picks.add((suggestion.placeId, token));
              setState(() => selected = suggestion.label);
            },
            onCleared: () => setState(() => selected = null),
          ),
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'T');
    await tester.pump(const Duration(milliseconds: 400));
    expect(searches, isEmpty, reason: 'one letter is not a search');

    await tester.enterText(find.byType(TextField), 'Ti');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'Tir');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'Tiru');
    await tester.pump(const Duration(milliseconds: 400));

    expect(searches, [('Tiru', 'token-1')], reason: 'only the settled query goes out');
    expect(find.text('Powered by Google'), findsOneWidget);

    await tester.tap(find.text('Tirupati'));
    await tester.pump();
    expect(picks, [('p1', 'token-1')]);
    expect(find.text('Tirupati, Andhra Pradesh, India'), findsOneWidget);

    // Changing the place starts a fresh billed session.
    await tester.tap(find.byTooltip('Change birth place'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Mad');
    await tester.pump(const Duration(milliseconds: 400));
    expect(searches.last, ('Mad', 'token-2'));
  });

  testWidgets('a search that fails says so, and can be tried again', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: PlaceSearchField(
          search: (query, token) async => throw const _Unavailable('Place search is unavailable right now.'),
          onChosen: (_, _, _, _) async {},
          onCleared: () {},
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Tiru');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Place search is unavailable right now.'), findsOneWidget);
  });
}

class _Unavailable implements Exception {
  const _Unavailable(this.message);
  final String message;
}
