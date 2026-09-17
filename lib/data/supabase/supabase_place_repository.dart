import '../models/app_user.dart';
import '../models/birth_place.dart';
import '../repositories/place_repository.dart';
import 'edge_functions.dart';
import 'session_store.dart';

/// Talks to the `place-search` Edge Function. The Google key never reaches the device.
class SupabasePlaceRepository implements PlaceRepository {
  SupabasePlaceRepository(this._functions, this._sessions);

  final EdgeFunctions _functions;
  final SessionStore _sessions;

  /// Searching is typing: a slow answer is a stale answer, so this gives up well before the
  /// default twenty seconds.
  static const _timeout = Duration(seconds: 10);

  @override
  Future<List<PlaceSuggestion>> autocomplete(String input, {required String sessionToken}) async {
    final data = await _call({'action': 'autocomplete', 'input': input, 'session_token': sessionToken});
    return [
      for (final row in data['suggestions'] is List ? data['suggestions'] as List : const [])
        ?PlaceSuggestion.fromServer(row),
    ];
  }

  @override
  Future<BirthPlace> details(
    PlaceSuggestion suggestion, {
    required String sessionToken,
    DateTime? birthDate,
    String? birthTime,
  }) async {
    final data = await _call({
      'action': 'details',
      'place_id': suggestion.placeId,
      'session_token': sessionToken,
      if (birthDate != null) 'dob': AppUser.formatBirthDate(birthDate),
      'birth_time': ?birthTime,
    });
    // The label the user chose from the list, not Google's formatted address: it is what they
    // recognised, and what they will expect to see on their kundali.
    final place = BirthPlace.fromServer(data['place'], label: suggestion.label);
    if (place == null) {
      throw const PlaceUnavailableException('We could not load that place. Please try again.');
    }
    return place;
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final token = await _sessions.readToken();
    if (token == null) throw const PlaceSignedOutException('Please sign in again.');

    try {
      return await _functions.call('place-search', bearerToken: token, body: body, timeout: _timeout);
    } on EdgeError catch (e) {
      throw switch (e.code) {
        'throttled' => PlaceThrottledException(e.message),
        'not_found' => PlaceNotFoundException(e.message),
        'unauthorized' => const PlaceSignedOutException('Please sign in again.'),
        _ => PlaceUnavailableException(e.message),
      };
    }
  }
}
