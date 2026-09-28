import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/models/birth_place.dart';
import '../../data/repositories/chat_repository.dart';
import '../../widgets/place_search_field.dart';
import 'chat_copy.dart';

/// Asks where they were born, and hands back the row they picked, as the chat sends it. Null when
/// the sheet is closed without one — typing the town in the composer is still open to them.
///
/// The kundali form's search, without the Details call the form makes after a pick: the chat
/// sends the row's id and its words, and the server resolves the id when it saves the place.
/// Resolving it here as well would be a second billed lookup for coordinates nothing on the
/// device uses. The search's session token goes with the row, so that lookup closes the session
/// the typing opened, as the form's own Details call does.
///
/// [hint] is the chat language's example town. [source] is where it was opened from — `reply` —
/// and only feeds analytics.
Future<ChatBirthPlace?> askBirthPlace(
  BuildContext context, {
  required Future<List<PlaceSuggestion>> Function(String query, String sessionToken) search,
  required String hint,
  required String source,
}) async {
  analytics.track(Ev.chatBirthPlaceOpened, {P.source: source});
  FocusScope.of(context).unfocus();

  final picked = await showModalBottomSheet<_Picked>(
    context: context,
    routeSettings: const RouteSettings(name: 'chat-birth-place'),
    // The keyboard comes up with the sheet and the suggestions list under the field, so it must
    // be free to grow past the default nine-sixteenths cap and sit above the keyboard.
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
    builder: (context) => _BirthPlaceSheet(search: search, hint: hint),
  );
  if (picked == null) return null;

  // The rank and the count, never the place: it stays out of Mixpanel, as the kundali form's does.
  analytics.track(Ev.chatBirthPlaceChosen, {
    P.source: source,
    P.resultRank: picked.rank,
    P.suggestionCount: picked.count,
  });
  return ChatBirthPlace(
    placeId: picked.suggestion.placeId,
    description: picked.suggestion.label,
    sessionToken: picked.sessionToken,
  );
}

/// The row picked, the search session it was found in, and where it sat in the list.
class _Picked {
  const _Picked(this.suggestion, this.sessionToken, this.rank, this.count);

  final PlaceSuggestion suggestion;
  final String sessionToken;
  final int rank;
  final int count;
}

class _BirthPlaceSheet extends StatelessWidget {
  const _BirthPlaceSheet({required this.search, required this.hint});

  final Future<List<PlaceSuggestion>> Function(String query, String sessionToken) search;
  final String hint;

  @override
  Widget build(BuildContext context) {
    // A bottom sheet is not lifted by the keyboard on its own; without this the field would open
    // underneath it.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppShape.gutter, 22, AppShape.gutter, 16 + keyboard),
        // All of it scrolls: on a small phone with the keyboard up, five suggestions and Google's
        // line under them are taller than what is left.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const ExcludeSemantics(child: Text('📍', style: TextStyle(fontSize: 20))),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      ChatCopy.placeSheetTitle,
                      style: AppText.section,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                ChatCopy.placeSheetWhy,
                style: AppText.meta.copyWith(height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              PlaceSearchField(
                hint: hint,
                // The sheet exists only to ask this, so the keyboard comes up with it.
                autofocus: true,
                search: search,
                // Picking is the answer: the sheet closes on it, and the view sends it.
                onChosen: (suggestion, sessionToken, rank, count) async =>
                    Navigator.pop(context, _Picked(suggestion, sessionToken, rank, count)),
                // Never shown chosen here, so there is nothing to clear.
                onCleared: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
