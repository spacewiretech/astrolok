import 'dart:typed_data';

import '../models/kundali.dart';
import 'kundali_pdf.dart';

/// Turns a revealed kundali into the primitive-only request [buildKundaliPdf] takes.
///
/// On the app side of the isolate line, like `reading_pdf_requests.dart`. The planet colours are
/// repeated from `north_indian_chart.dart` as ARGB ints rather than imported, so the data layer does
/// not reach into the widgets folder.

const _disclaimer = 'Astrolok · For guidance and reflection. Not medical, legal or financial advice.';

const _planetColours = <String, int>{
  'sun': 0xFFE8A317,
  'moon': 0xFF2F6FDB,
  'mars': 0xFFD7263D,
  'mercury': 0xFF1E8E3E,
  'jupiter': 0xFFE38B00,
  'venus': 0xFFD6336C,
  'saturn': 0xFF3355A5,
  'rahu': 0xFF7A3E12,
  'ketu': 0xFF8C6D1F,
};

const _insightTitles = {
  'love': 'Love & Relationships',
  'career': 'Career & Profession',
  'finance': 'Finance & Wealth',
  'year_ahead': 'Year Ahead',
};

String _title(String planetKey) => planetKey.isEmpty ? '' : '${planetKey[0].toUpperCase()}${planetKey.substring(1)}';

extension KundaliReadingPdf on KundaliReading {
  KundaliPdfRequest toPdfRequest({
    required Uint8List regular,
    required Uint8List bold,
    Uint8List? mark,
    String? name,
  }) {
    final birth = summary.birth;
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final parts = birth.birthTime.split(':');
    final hour = parts.length == 2 ? int.tryParse(parts[0]) ?? 0 : 0;
    final clock = parts.length == 2
        ? '${hour % 12 == 0 ? 12 : hour % 12}:${parts[1]} ${hour < 12 ? 'AM' : 'PM'}'
        : birth.birthTime;
    final moon = chart.planet('moon');

    final planetByKey = {for (final p in chart.planets) p.key: p};
    final dasha = chart.dasha;

    return KundaliPdfRequest(
      regular: regular,
      bold: bold,
      mark: mark,
      kundaliId: id,
      title: name == null || name.trim().isEmpty ? 'Your Kundali' : 'Kundali for ${name.trim()}',
      birthLine:
          'Born ${birth.birthDate.day} ${months[birth.birthDate.month - 1]} ${birth.birthDate.year}, $clock · ${birth.placeLabel}',
      lagnaLine: 'Lagna: ${chart.lagna.rashi} (${chart.lagna.sign}) ${chart.lagna.degree.toStringAsFixed(1)}°',
      moonLine: moon == null ? '' : 'Moon: ${moon.placement.rashi}, ${moon.placement.nakshatra} ${moon.placement.pada}',
      invocation: report.invocation,
      headline: report.headline,
      planets: [
        for (final p in chart.planets)
          KundaliPdfPlanet(
            abbr: p.abbr,
            english: p.english,
            name: p.name,
            sign: p.placement.sign,
            rashi: p.placement.rashi,
            degree: p.placement.degree,
            nakshatra: p.placement.nakshatra,
            pada: p.placement.pada,
            house: p.house,
            retrograde: p.showRetrograde,
            dignity: switch (p.dignity) {
              'exalted' => 'Exalted',
              'debilitated' => 'Debilitated',
              'own' => 'Own sign',
              _ => '',
            },
            colour: _planetColours[p.key] ?? 0xFF000C2B,
            line: report.highlights[p.key] ?? '',
          ),
      ],
      houses: [
        for (final h in chart.houses)
          KundaliPdfHouse(
            house: h.house,
            rashiNumber: h.rashiIndex + 1,
            sign: '${h.rashi} · ${h.sign}',
            lord: planetByKey[h.lord]?.english ?? _title(h.lord),
            occupants: [
              for (final key in h.occupants)
                if (planetByKey[key] != null)
                  (
                    planetByKey[key]!.showRetrograde ? '${planetByKey[key]!.abbr}(R)' : planetByKey[key]!.abbr,
                    _planetColours[key] ?? 0xFF000C2B,
                  ),
            ],
            theme: report.houseThemes[h.house] ?? '',
          ),
      ],
      insights: [
        for (final key in KundaliInsightKey.all)
          if (report.insights[key] != null)
            KundaliPdfInsight(
              title: _insightTitles[key] ?? key,
              summary: report.insights[key]!.summary,
              detail: report.insights[key]!.detail,
              tip: report.insights[key]!.tip,
            ),
      ],
      dasha: [
        for (final span in dasha?.sequence ?? const <DashaSpan>[])
          KundaliPdfDasha(
            label: '${planetByKey[span.planet]?.english ?? span.lord} (${span.lord})',
            years: '${span.startYear} – ${span.endYear}',
            current: span.current,
          ),
      ],
      dashaNow: dasha == null
          ? ''
          : 'Running now: ${dasha.mahadasha} Mahadasha (${dasha.mahaPhase}), ${dasha.antardasha} Antardasha (${dasha.antarPhase})',
      dashaSummary: report.dashaSummary,
      blessing: report.blessing,
      disclaimer: _disclaimer,
    );
  }
}
