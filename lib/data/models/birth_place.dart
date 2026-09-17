import 'package:flutter/foundation.dart';

/// One row of the birth-place search, as `place-search` returns it.
@immutable
class PlaceSuggestion {
  const PlaceSuggestion({required this.placeId, required this.primary, this.secondary = ''});

  final String placeId;

  /// The town or city — "Tirupati".
  final String primary;

  /// Where it is — "Andhra Pradesh, India". Empty for a country-level result.
  final String secondary;

  /// What the field shows once this row is chosen.
  String get label => secondary.isEmpty ? primary : '$primary, $secondary';

  static PlaceSuggestion? fromServer(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['place_id'];
    final primary = raw['primary'];
    if (id is! String || id.isEmpty || primary is! String || primary.trim().isEmpty) return null;
    return PlaceSuggestion(
      placeId: id,
      primary: primary.trim(),
      secondary: (raw['secondary'] as String? ?? '').trim(),
    );
  }
}

/// A resolved birth place: enough to cast a chart from.
///
/// The coordinates and the zone come from Google through `place-search` and are sent straight on
/// to `kundali`. The zone is what decides the clock the birth time was read on — India has not
/// always been +5:30 — so it travels as an IANA id, never as an offset.
@immutable
class BirthPlace {
  const BirthPlace({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.timeZoneId,
    this.placeId,
  });

  final String? placeId;
  final String label;
  final double latitude;
  final double longitude;
  final String timeZoneId;

  static BirthPlace? fromServer(Object? raw, {String? label}) {
    if (raw is! Map) return null;
    final lat = raw['lat'];
    final lng = raw['lng'];
    final zone = raw['time_zone_id'];
    final name = label ?? raw['label'];
    if (lat is! num || lng is! num || zone is! String || zone.isEmpty) return null;
    if (name is! String || name.trim().isEmpty) return null;
    return BirthPlace(
      placeId: raw['place_id'] as String?,
      label: name.trim(),
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      timeZoneId: zone,
    );
  }

  /// The `place` object `kundali` expects in a request.
  Map<String, Object?> toRequest() => {
        'place_id': placeId,
        'label': label,
        'lat': latitude,
        'lng': longitude,
        'time_zone_id': timeZoneId,
      };

  /// In the server's user-payload shape, for the session cache.
  Map<String, Object?> toUserJson() => {
        'birth_place': label,
        'birth_place_id': placeId,
        'birth_lat': latitude,
        'birth_lng': longitude,
        'birth_tz': timeZoneId,
      };

  /// The place saved on the account, when it is complete enough to cast from.
  ///
  /// Null once the coordinates have aged out of Google's 30-day caching window: the form then asks
  /// for the place again rather than guessing where it was.
  static BirthPlace? fromUserJson(Map raw) {
    final label = raw['birth_place'];
    final lat = raw['birth_lat'];
    final lng = raw['birth_lng'];
    final zone = raw['birth_tz'];
    if (label is! String || label.trim().isEmpty) return null;
    if (lat is! num || lng is! num || zone is! String || zone.isEmpty) return null;
    return BirthPlace(
      placeId: raw['birth_place_id'] as String?,
      label: label.trim(),
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      timeZoneId: zone,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BirthPlace &&
      other.placeId == placeId &&
      other.label == label &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.timeZoneId == timeZoneId;

  @override
  int get hashCode => Object.hash(placeId, label, latitude, longitude, timeZoneId);
}
