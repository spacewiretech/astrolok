import 'package:flutter/foundation.dart';

/// The chart the server computed from the date and hour of birth, as Profile shows it.
///
/// Arithmetic rather than language — `jyotish.ts` works it out and the app only displays it — so
/// there is nothing to normalise beyond reading it defensively. Two things about the shape are
/// worth knowing:
///
///  * **A sign can be unknown while the chart is not.** With no birth hour, a day on which the
///    Moon changed sign has no honest answer, so [moonRashi] is null and [moonRashiCandidates]
///    holds the two it moved between. "Dhanu or Makara" beats a guess the chat later contradicts.
///  * **The dasha carries no dates.** Only which periods are running — the server withholds the
///    years for the same reason the sage never says them.
@immutable
class BirthChart {
  const BirthChart({
    this.moonRashi,
    this.moonRashiCandidates = const [],
    this.nakshatra,
    this.pada,
    this.sunRashi,
    this.sunRashiCandidates = const [],
    this.precise = false,
    this.mahadasha,
    this.antardasha,
  });

  final String? moonRashi;

  /// One sign when the Moon's rashi is settled, the two it moved between when it is not.
  final List<String> moonRashiCandidates;

  /// Null until the hour of birth is known.
  final String? nakshatra;
  final int? pada;

  final String? sunRashi;
  final List<String> sunRashiCandidates;

  /// True when an hour of birth went into it.
  final bool precise;

  /// The Vimshottari periods running now. Null until the hour of birth is known.
  final String? mahadasha;
  final String? antardasha;

  /// The Moon's rashi as a person should read it: the sign, or the two it could be.
  String? get moonLabel => _label(moonRashi, moonRashiCandidates);

  String? get sunLabel => _label(sunRashi, sunRashiCandidates);

  /// True when only the hour of birth can say which of two signs the Moon was in.
  bool get moonUncertain => moonRashi == null && moonRashiCandidates.length > 1;

  static String? _label(String? sign, List<String> candidates) {
    if (sign != null) return sign;
    if (candidates.isEmpty) return null;
    return candidates.join(' or ');
  }

  /// Null for anything that is not a chart with at least one sign in it — a card with no sign on
  /// it is not worth a place on Profile.
  static BirthChart? fromServer(Object? raw) {
    if (raw is! Map) return null;

    final chart = BirthChart(
      moonRashi: _text(raw['moon_rashi']),
      moonRashiCandidates: _list(raw['moon_rashi_candidates']),
      nakshatra: _text(raw['nakshatra']),
      pada: raw['pada'] is int ? raw['pada'] as int : null,
      sunRashi: _text(raw['sun_rashi']),
      sunRashiCandidates: _list(raw['sun_rashi_candidates']),
      precise: raw['precise'] == true,
      mahadasha: _text(raw['mahadasha']),
      antardasha: _text(raw['antardasha']),
    );

    return chart.moonLabel == null && chart.sunLabel == null ? null : chart;
  }

  /// The wire shape, so a cached user parses back through [fromServer] like a fresh one.
  Map<String, dynamic> toJson() => {
        'moon_rashi': moonRashi,
        'moon_rashi_candidates': moonRashiCandidates,
        'nakshatra': nakshatra,
        'pada': pada,
        'sun_rashi': sunRashi,
        'sun_rashi_candidates': sunRashiCandidates,
        'precise': precise,
        'mahadasha': mahadasha,
        'antardasha': antardasha,
      };

  static String? _text(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _list(Object? raw) => raw is List
      ? [
          for (final entry in raw)
            if (entry is String && entry.trim().isNotEmpty) entry.trim(),
        ]
      : const [];
}
