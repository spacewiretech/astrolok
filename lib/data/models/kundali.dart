import 'package:flutter/foundation.dart';

/// Where a kundali is, as the server tells it — derived there from the row and the clock.
enum KundaliState {
  /// Asked for, and not yet revealed. The waiting screen.
  waiting,

  /// Past the reveal time, but the reading is not written yet. Rare; the waiting screen says
  /// "almost ready" and checks again.
  delayed,

  /// Revealed. The report screen.
  ready,

  /// Generation gave up. Asking again with the same details costs nothing.
  failed;

  static KundaliState parse(Object? raw) => switch (raw) {
        'ready' => KundaliState.ready,
        'delayed' => KundaliState.delayed,
        'failed' => KundaliState.failed,
        _ => KundaliState.waiting,
      };
}

/// When one of the waiting screen's four stages ticks off.
@immutable
class KundaliStage {
  const KundaliStage({required this.key, required this.completesAt});

  /// `positions`, `lagna`, `dasha` or `insights`.
  final String key;
  final DateTime completesAt;
}

/// The part of the chart shown straight away: arithmetic, not the reading.
@immutable
class KundaliTeaser {
  const KundaliTeaser({this.moonRashi, this.moonSign, this.nakshatra, this.pada});

  final String? moonRashi;
  final String? moonSign;
  final String? nakshatra;
  final int? pada;

  bool get isEmpty => moonRashi == null && nakshatra == null;
}

/// What a kundali was cast from.
@immutable
class KundaliBirth {
  const KundaliBirth({
    required this.birthDate,
    required this.birthTime,
    required this.placeLabel,
    required this.timeZoneId,
    this.placeId,
  });

  final DateTime birthDate;

  /// `HH:MM`, on the birth place's own clock.
  final String birthTime;
  final String placeLabel;
  final String? placeId;
  final String timeZoneId;
}

/// A kundali without its chart or reading — what the Home card and the waiting screen need, and
/// all the server will send before the reveal.
@immutable
class KundaliSummary {
  const KundaliSummary({
    required this.id,
    required this.state,
    required this.requestedAt,
    required this.unlockAt,
    required this.serverNow,
    required this.receivedAt,
    required this.birth,
    required this.teaser,
    required this.stages,
    required this.viewed,
    required this.regenerationsLeft,
    this.unlockHours = 24,
    this.raw = const {},
  });

  final String id;
  final KundaliState state;
  final DateTime requestedAt;
  final DateTime unlockAt;

  /// The server's clock when it answered, and the device's when the answer arrived. Their
  /// difference corrects the countdown on a phone whose clock is wrong — which, for a reveal the
  /// server enforces, is the difference between "ready" on screen and a refusal behind it.
  final DateTime serverNow;
  final DateTime receivedAt;

  final KundaliBirth birth;
  final KundaliTeaser teaser;
  final List<KundaliStage> stages;
  final bool viewed;
  final int regenerationsLeft;
  final num unlockHours;

  /// The server's own payload, kept so the cache round-trips through [fromServer].
  final Map<String, Object?> raw;

  Duration get clockOffset => serverNow.difference(receivedAt);

  /// "Now", on the server's clock.
  DateTime serverTime([DateTime? deviceNow]) => (deviceNow ?? DateTime.now()).add(clockOffset);

  Duration remaining([DateTime? deviceNow]) {
    final left = unlockAt.difference(serverTime(deviceNow));
    return left.isNegative ? Duration.zero : left;
  }

  /// True once the reveal time has passed. The server still has to say [KundaliState.ready].
  bool isPastUnlock([DateTime? deviceNow]) => !serverTime(deviceNow).isBefore(unlockAt);

  /// Revealed the moment it is written, with no wait: asked for by a paying account. Only a trial
  /// waits the day. Derived from the two times rather than sent, so a cached summary reads too.
  bool get isInstant => unlockAt.difference(requestedAt) < const Duration(minutes: 1);

  /// How long past the reveal a reading still being written is expected any second, rather than
  /// late. Long enough for a model call; after it the screen says it is taking longer.
  static const writingWindow = Duration(minutes: 3);

  /// The reveal has passed and the reading is being written right now.
  bool isWritingNow([DateTime? deviceNow]) =>
      state == KundaliState.delayed && serverTime(deviceNow).difference(unlockAt) < writingWindow;

  /// The stage in progress, 0-3, or 4 when every stage is done.
  ///
  /// The last stage — the reading itself — only completes when the server says the reading is
  /// ready. The first three are timed to the wait; this one is not, so the screen never claims
  /// something is finished that is not.
  int currentStage([DateTime? deviceNow]) {
    final now = serverTime(deviceNow);
    for (var i = 0; i < stages.length; i++) {
      final last = i == stages.length - 1;
      final done = last ? state == KundaliState.ready : !now.isBefore(stages[i].completesAt);
      if (!done) return i;
    }
    return stages.length;
  }

  KundaliSummary copyWith({KundaliState? state, bool? viewed}) => KundaliSummary(
        id: id,
        state: state ?? this.state,
        requestedAt: requestedAt,
        unlockAt: unlockAt,
        serverNow: serverNow,
        receivedAt: receivedAt,
        birth: birth,
        teaser: teaser,
        stages: stages,
        viewed: viewed ?? this.viewed,
        regenerationsLeft: regenerationsLeft,
        unlockHours: unlockHours,
        raw: {...raw, if (state != null) 'state': state.name, 'viewed': ?viewed},
      );

  /// Null rather than a half-built summary: a payload this build cannot read shows the form, not a
  /// countdown to nothing.
  static KundaliSummary? fromServer(Object? raw, {DateTime? receivedAt}) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final requestedAt = _date(raw['requested_at']);
    final unlockAt = _date(raw['unlock_at']);
    if (id is! String || id.isEmpty || requestedAt == null || unlockAt == null) return null;

    final birthRaw = raw['birth'];
    final birthDate = birthRaw is Map ? _calendarDate(birthRaw['dob']) : null;
    if (birthRaw is! Map || birthDate == null) return null;

    final teaser = raw['teaser'];
    final received = receivedAt ?? _date(raw['received_at']) ?? DateTime.now();

    return KundaliSummary(
      id: id,
      state: KundaliState.parse(raw['state']),
      requestedAt: requestedAt,
      unlockAt: unlockAt,
      serverNow: _date(raw['server_now']) ?? received,
      receivedAt: received,
      unlockHours: raw['unlock_hours'] is num ? raw['unlock_hours'] as num : 24,
      birth: KundaliBirth(
        birthDate: birthDate,
        birthTime: (birthRaw['birth_time'] as String? ?? '').trim(),
        placeLabel: (birthRaw['place_label'] as String? ?? '').trim(),
        placeId: birthRaw['place_id'] as String?,
        timeZoneId: (birthRaw['time_zone_id'] as String? ?? '').trim(),
      ),
      teaser: teaser is Map
          ? KundaliTeaser(
              moonRashi: teaser['moon_rashi'] as String?,
              moonSign: teaser['moon_sign'] as String?,
              nakshatra: teaser['nakshatra'] as String?,
              pada: teaser['pada'] is num ? (teaser['pada'] as num).toInt() : null,
            )
          : const KundaliTeaser(),
      stages: [
        for (final stage in raw['stages'] is List ? raw['stages'] as List : const [])
          if (stage is Map && stage['key'] is String && _date(stage['completes_at']) != null)
            KundaliStage(key: stage['key'] as String, completesAt: _date(stage['completes_at'])!),
      ],
      viewed: raw['viewed'] == true,
      regenerationsLeft: raw['regenerations_left'] is num ? (raw['regenerations_left'] as num).toInt() : 0,
      raw: {
        for (final entry in raw.entries)
          if (entry.key is String && entry.key != 'chart' && entry.key != 'report') entry.key as String: entry.value,
        'received_at': received.toUtc().toIso8601String(),
      },
    );
  }

  Map<String, Object?> toJson() => raw;
}

// ---------------------------------------------------------------- the chart

/// Where a lagna or a graha sits: a sidereal longitude, its rashi and nakshatra.
@immutable
class ChartPlacement {
  const ChartPlacement({
    required this.longitude,
    required this.rashiIndex,
    required this.rashi,
    required this.sign,
    required this.degree,
    required this.nakshatra,
    required this.pada,
  });

  final double longitude;

  /// 0 for Mesha, 11 for Meena.
  final int rashiIndex;
  final String rashi;

  /// The Western name the app shows beside it — "Aries".
  final String sign;

  /// Degrees into the rashi, 0 to 30.
  final double degree;
  final String nakshatra;
  final int pada;

  static ChartPlacement? parse(Object? raw) {
    if (raw is! Map) return null;
    final index = raw['rashi_index'];
    if (index is! num || index < 0 || index > 11) return null;
    return ChartPlacement(
      longitude: (raw['longitude'] as num? ?? 0).toDouble(),
      rashiIndex: index.toInt(),
      rashi: raw['rashi'] as String? ?? '',
      sign: raw['sign'] as String? ?? '',
      degree: (raw['degree'] as num? ?? 0).toDouble(),
      nakshatra: raw['nakshatra'] as String? ?? '',
      pada: (raw['pada'] as num? ?? 0).toInt(),
    );
  }
}

@immutable
class ChartPlanet {
  const ChartPlanet({
    required this.key,
    required this.abbr,
    required this.name,
    required this.english,
    required this.placement,
    required this.house,
    required this.retrograde,
    this.dignity,
  });

  /// `sun` … `ketu`.
  final String key;

  /// What the chart diagram prints — `Su`.
  final String abbr;

  /// The tradition's name — `Surya`.
  final String name;

  /// `Sun`.
  final String english;
  final ChartPlacement placement;
  final int house;

  /// Always true for Rahu and Ketu, which always move backwards; the chart does not mark those.
  final bool retrograde;

  /// `exalted`, `debilitated`, `own`, or null.
  final String? dignity;

  bool get isNode => key == 'rahu' || key == 'ketu';

  /// Retrograde worth marking on a chart.
  bool get showRetrograde => retrograde && !isNode;
}

@immutable
class ChartHouse {
  const ChartHouse({
    required this.house,
    required this.rashiIndex,
    required this.rashi,
    required this.sign,
    required this.lord,
    required this.occupants,
  });

  final int house;
  final int rashiIndex;
  final String rashi;
  final String sign;
  final String lord;
  final List<String> occupants;
}

@immutable
class DashaSpan {
  const DashaSpan({
    required this.lord,
    required this.planet,
    required this.startYear,
    required this.endYear,
    required this.current,
  });

  final String lord;
  final String planet;
  final int startYear;
  final int endYear;
  final bool current;
}

@immutable
class ChartDasha {
  const ChartDasha({
    required this.mahadasha,
    required this.mahadashaPlanet,
    required this.mahaPhase,
    required this.antardasha,
    required this.antardashaPlanet,
    required this.antarPhase,
    required this.sequence,
  });

  final String mahadasha;
  final String mahadashaPlanet;
  final String mahaPhase;
  final String antardasha;
  final String antardashaPlanet;
  final String antarPhase;
  final List<DashaSpan> sequence;
}

/// The whole birth chart. Arithmetic, cast by the server from the moment and place of birth.
@immutable
class KundaliChart {
  const KundaliChart({
    required this.lagna,
    required this.lagnaLord,
    required this.planets,
    required this.houses,
    this.dasha,
  });

  final ChartPlacement lagna;
  final String lagnaLord;

  /// In the tradition's order: Sun, Moon, Mars, Mercury, Jupiter, Venus, Saturn, Rahu, Ketu.
  final List<ChartPlanet> planets;

  /// Twelve, the first being the lagna's rashi.
  final List<ChartHouse> houses;
  final ChartDasha? dasha;

  ChartPlanet? planet(String key) {
    for (final p in planets) {
      if (p.key == key) return p;
    }
    return null;
  }

  static KundaliChart? fromServer(Object? raw) {
    if (raw is! Map) return null;
    final lagna = ChartPlacement.parse(raw['lagna']);
    if (lagna == null) return null;

    final planets = <ChartPlanet>[
      for (final p in raw['planets'] is List ? raw['planets'] as List : const [])
        if (p is Map && p['key'] is String && ChartPlacement.parse(p) != null && p['house'] is num)
          ChartPlanet(
            key: p['key'] as String,
            abbr: p['abbr'] as String? ?? '',
            name: p['name'] as String? ?? '',
            english: p['english'] as String? ?? '',
            placement: ChartPlacement.parse(p)!,
            house: (p['house'] as num).toInt(),
            retrograde: p['retrograde'] == true,
            dignity: p['dignity'] as String?,
          ),
    ];

    final houses = <ChartHouse>[
      for (final h in raw['houses'] is List ? raw['houses'] as List : const [])
        if (h is Map && h['house'] is num && h['rashi_index'] is num)
          ChartHouse(
            house: (h['house'] as num).toInt(),
            rashiIndex: (h['rashi_index'] as num).toInt(),
            rashi: h['rashi'] as String? ?? '',
            sign: h['sign'] as String? ?? '',
            lord: h['lord'] as String? ?? '',
            occupants: [for (final o in h['occupants'] is List ? h['occupants'] as List : const []) '$o'],
          ),
    ]..sort((a, b) => a.house.compareTo(b.house));

    // A chart with a graha or a house missing is not a chart anyone should be shown.
    if (planets.length != 9 || houses.length != 12) return null;

    final d = raw['dasha'];
    return KundaliChart(
      lagna: lagna,
      lagnaLord: (raw['lagna'] as Map)['lord'] as String? ?? '',
      planets: planets,
      houses: houses,
      dasha: d is Map
          ? ChartDasha(
              mahadasha: d['mahadasha'] as String? ?? '',
              mahadashaPlanet: d['mahadasha_planet'] as String? ?? '',
              mahaPhase: d['maha_phase'] as String? ?? '',
              antardasha: d['antardasha'] as String? ?? '',
              antardashaPlanet: d['antardasha_planet'] as String? ?? '',
              antarPhase: d['antar_phase'] as String? ?? '',
              sequence: [
                for (final s in d['sequence'] is List ? d['sequence'] as List : const [])
                  if (s is Map && s['start_year'] is num && s['end_year'] is num)
                    DashaSpan(
                      lord: s['lord'] as String? ?? '',
                      planet: s['planet'] as String? ?? '',
                      startYear: (s['start_year'] as num).toInt(),
                      endYear: (s['end_year'] as num).toInt(),
                      current: s['current'] == true,
                    ),
              ],
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------- the reading

/// The four insight tiles, in the order the design lays them out.
abstract final class KundaliInsightKey {
  static const love = 'love';
  static const career = 'career';
  static const finance = 'finance';
  static const yearAhead = 'year_ahead';

  static const all = [love, career, finance, yearAhead];
}

@immutable
class KundaliInsight {
  const KundaliInsight({required this.evidence, required this.summary, required this.detail, required this.tip});

  /// Codes for the placements it was read from — `venus_h7`, `lord10_h4`.
  final List<String> evidence;
  final String summary;
  final String detail;
  final String tip;
}

@immutable
class KundaliReport {
  const KundaliReport({
    required this.headline,
    required this.highlights,
    required this.insights,
    required this.houseThemes,
    this.invocation = '',
    this.dashaSummary = '',
    this.blessing = '',
  });

  final String invocation;
  final String headline;

  /// Planet key to its one line.
  final Map<String, String> highlights;
  final Map<String, KundaliInsight> insights;

  /// House number to its theme.
  final Map<int, String> houseThemes;
  final String dashaSummary;
  final String blessing;

  static KundaliReport? fromServer(Object? raw) {
    if (raw is! Map) return null;
    final headline = raw['headline'];
    if (headline is! String || headline.trim().isEmpty) return null;

    String text(Object? v) => v is String ? v.trim() : '';

    final insights = <String, KundaliInsight>{};
    final rawInsights = raw['insights'];
    if (rawInsights is Map) {
      for (final key in KundaliInsightKey.all) {
        final i = rawInsights[key];
        if (i is! Map || text(i['detail']).isEmpty) continue;
        insights[key] = KundaliInsight(
          evidence: [for (final e in i['evidence'] is List ? i['evidence'] as List : const []) '$e'],
          summary: text(i['summary']),
          detail: text(i['detail']),
          tip: text(i['tip']),
        );
      }
    }

    return KundaliReport(
      invocation: text(raw['invocation']),
      headline: headline.trim(),
      highlights: {
        for (final h in raw['highlights'] is List ? raw['highlights'] as List : const [])
          if (h is Map && h['planet'] is String && text(h['line']).isNotEmpty) h['planet'] as String: text(h['line']),
      },
      insights: insights,
      houseThemes: {
        for (final h in raw['houses'] is List ? raw['houses'] as List : const [])
          if (h is Map && h['house'] is num && text(h['theme']).isNotEmpty) (h['house'] as num).toInt(): text(h['theme']),
      },
      dashaSummary: text(raw['dasha_summary']),
      blessing: text(raw['blessing']),
    );
  }
}

/// A revealed kundali: the summary, the chart and the reading together.
@immutable
class KundaliReading {
  const KundaliReading({
    required this.summary,
    required this.chart,
    required this.report,
    this.language,
    this.raw = const {},
  });

  final KundaliSummary summary;
  final KundaliChart chart;
  final KundaliReport report;
  final String? language;
  final Map<String, Object?> raw;

  String get id => summary.id;

  static KundaliReading? fromServer(Object? raw, {DateTime? receivedAt}) {
    if (raw is! Map) return null;
    final summary = KundaliSummary.fromServer(raw, receivedAt: receivedAt);
    final chart = KundaliChart.fromServer(raw['chart']);
    final report = KundaliReport.fromServer(raw['report']);
    if (summary == null || chart == null || report == null) return null;
    return KundaliReading(
      summary: summary,
      chart: chart,
      report: report,
      language: raw['language'] as String?,
      raw: {
        for (final entry in raw.entries)
          if (entry.key is String) entry.key as String: entry.value,
        'received_at': summary.receivedAt.toUtc().toIso8601String(),
      },
    );
  }

  Map<String, Object?> toJson() => raw;
}

DateTime? _date(Object? raw) => raw is String && raw.isNotEmpty ? DateTime.tryParse(raw) : null;

/// `YYYY-MM-DD` as a calendar date, never shifted by a zone.
DateTime? _calendarDate(Object? raw) {
  if (raw is! String) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
  if (match == null) return null;
  final date = DateTime(int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
  return date.month == int.parse(match[2]!) ? date : null;
}
