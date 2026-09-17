import '../models/birth_place.dart';

/// Birth-place search, through the `place-search` Edge Function that holds the Google key.
///
/// [sessionToken] groups an autocomplete run and the details call that ends it into one billed
/// session. The caller mints it — a fresh UUID per search — and reuses it until a place is chosen.
abstract interface class PlaceRepository {
  Future<List<PlaceSuggestion>> autocomplete(String input, {required String sessionToken});

  /// Resolves a chosen row to coordinates and a time zone. [birthDate] and [birthTime], when
  /// known, let the server answer with the offset in force at the birth moment.
  Future<BirthPlace> details(
    PlaceSuggestion suggestion, {
    required String sessionToken,
    DateTime? birthDate,
    String? birthTime,
  });
}

class PlaceException implements Exception {
  const PlaceException(this.message);

  final String message;

  @override
  String toString() => 'PlaceException: $message';
}

/// Search is misconfigured, over quota, or unreachable. The field says so and lets the user retry.
class PlaceUnavailableException extends PlaceException {
  const PlaceUnavailableException(super.message);
}

/// This account has searched too much this hour.
class PlaceThrottledException extends PlaceException {
  const PlaceThrottledException(super.message);
}

/// The chosen row no longer resolves. Pick another.
class PlaceNotFoundException extends PlaceException {
  const PlaceNotFoundException(super.message);
}

class PlaceSignedOutException extends PlaceException {
  const PlaceSignedOutException(super.message);
}
