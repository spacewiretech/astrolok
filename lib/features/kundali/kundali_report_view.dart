import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/models/kundali.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/ask_astro_row.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/north_indian_chart.dart';
import '../../widgets/primary_button.dart';
import 'kundali_copy.dart';
import 'kundali_report_viewmodel.dart';

/// "Detailed Kundali": the chart, the planetary highlights, four life insights, the dasha and the
/// houses, and the full report as a PDF.
class KundaliReportView extends ConsumerWidget {
  const KundaliReportView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(kundaliReportViewModelProvider);
    final model = ref.read(kundaliReportViewModelProvider.notifier);

    ref.listen(kundaliReportViewModelProvider.select((s) => s.error), (_, error) {
      if (error != null) showAppSnackBar(context, error, error: true);
    });
    ref.listen(kundaliReportViewModelProvider.select((s) => s.notReady), (_, notReady) {
      if (notReady) context.replace(Routes.kundaliWaiting);
    });

    return Scaffold(
      backgroundColor: const Color(0xFFFFFCF6),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppShape.gutter, 8, AppShape.gutter, 0),
              child: Row(
                children: [
                  CircleIconButton(
                    image: PalmIcon.backCircle,
                    icon: Icons.chevron_left_rounded,
                    semanticLabel: 'Back',
                    onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                  ),
                  const Spacer(),
                  const BrandLogo(size: 34),
                  const Spacer(),
                  CircleIconButton(
                    icon: Icons.file_download_outlined,
                    semanticLabel: KundaliCopy.download,
                    busy: state.exporting,
                    onTap: state.reading == null ? null : model.exportPdf,
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                  : state.reading == null
                      ? _LoadError(message: state.loadError ?? KundaliCopy.loadFailed, onRetry: model.load)
                      : _Report(reading: state.reading!, exporting: state.exporting, model: model),
            ),
          ],
        ),
      ),
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.reading, required this.exporting, required this.model});

  final KundaliReading reading;
  final bool exporting;
  final KundaliReportViewModel model;

  @override
  Widget build(BuildContext context) {
    final report = reading.report;
    final chart = reading.chart;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppShape.gutter, 14, AppShape.gutter, 32),
      children: [
        const AccentHeading(lead: KundaliCopy.reportTitleLead, accent: KundaliCopy.reportTitleAccent),
        const SizedBox(height: 4),
        Text(KundaliCopy.reportSubtitle, style: AppText.body, textAlign: TextAlign.center),
        if (report.invocation.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            report.invocation,
            style: AppText.body.copyWith(color: AppColors.goldDeep, fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 18),

        _Section(
          icon: Icons.auto_awesome,
          title: KundaliCopy.chartTitle,
          child: Column(
            children: [
              Center(child: NorthIndianChart(chart: chart)),
              const SizedBox(height: 12),
              Text(report.headline, style: AppText.title, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                '${KundaliCopy.lagna}: ${chart.lagna.rashi} (${chart.lagna.sign}) · ${reading.summary.birth.placeLabel}',
                style: AppText.meta.copyWith(fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _Section(
          icon: Icons.public,
          title: KundaliCopy.highlightsTitle,
          padChild: false,
          child: SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              itemCount: chart.planets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _PlanetCard(planet: chart.planets[i], line: report.highlights[chart.planets[i].key] ?? ''),
            ),
          ),
        ),
        const SizedBox(height: 16),

        _Section(
          icon: Icons.stars_rounded,
          title: KundaliCopy.insightsTitle,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 300;
              final tiles = [
                for (final key in KundaliInsightKey.all)
                  if (report.insights[key] != null)
                    _InsightTile(
                      insightKey: key,
                      insight: report.insights[key]!,
                      onTap: () {
                        model.insightOpened(key);
                        _openInsight(context, key, report.insights[key]!, chart);
                      },
                    ),
              ];
              if (!wide) {
                return Column(children: [for (final t in tiles) Padding(padding: const EdgeInsets.only(bottom: 10), child: t)]);
              }
              return Column(
                children: [
                  for (var i = 0; i < tiles.length; i += 2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: tiles[i]),
                            const SizedBox(width: 10),
                            Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        if (chart.dasha != null) ...[
          _Section(icon: Icons.timeline_rounded, title: KundaliCopy.dashaTitle, child: _Dasha(chart: chart, summary: report.dashaSummary)),
          const SizedBox(height: 16),
        ],

        _Section(
          icon: Icons.grid_view_rounded,
          title: KundaliCopy.housesTitle,
          child: Column(
            children: [
              for (final house in chart.houses)
                _HouseRow(house: house, theme: report.houseThemes[house.house] ?? '', chart: chart),
            ],
          ),
        ),

        if (report.blessing.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            report.blessing,
            style: AppText.body.copyWith(color: AppColors.goldDeep, fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 20),
        AskAstroRow(
          title: KundaliCopy.askAstroTitle,
          subtitle: KundaliCopy.askAstroSubtitle,
          onTap: () {
            analytics.track(Ev.askAstroTapped, {P.source: 'kundali_report', P.kundaliId: reading.id});
            context.push(Routes.chat, extra: KundaliCopy.askAstroOpener(chart.lagna.rashi));
          },
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: KundaliCopy.download,
          analyticsId: 'kundali_download',
          icon: Icons.file_download_outlined,
          tone: ButtonTone.navy,
          pill: true,
          busy: exporting,
          onPressed: model.exportPdf,
        ),
      ],
    );
  }

  void _openInsight(BuildContext context, String key, KundaliInsight insight, KundaliChart chart) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      routeSettings: const RouteSettings(name: 'kundali-insight'),
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(AppShape.gutter, 20, AppShape.gutter, 32),
          children: [
            Row(
              children: [
                _InsightIcon(insightKey: key, size: 44),
                const SizedBox(width: 12),
                Expanded(child: Text(KundaliCopy.insightTitle(key), style: AppText.section)),
              ],
            ),
            const SizedBox(height: 14),
            if (insight.summary.isNotEmpty) Text(insight.summary, style: AppText.title),
            const SizedBox(height: 10),
            Text(insight.detail, style: AppText.body),
            if (insight.evidence.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(KundaliCopy.readFrom, style: AppText.meta.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final code in insight.evidence)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: AppColors.goldWash, borderRadius: AppShape.pill),
                      child: Text(evidenceLabel(code, chart), style: AppText.meta.copyWith(fontSize: 12, color: AppColors.navy)),
                    ),
                ],
              ),
            ],
            if (insight.tip.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.cardSoft, borderRadius: AppShape.card),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded, color: AppColors.gold),
                    const SizedBox(width: 10),
                    Expanded(child: Text(insight.tip, style: AppText.body)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A readable name for an evidence code: `venus_h7` → "Venus · 7th house".
String evidenceLabel(String code, KundaliChart chart) {
  String ordinal(int n) => switch (n) { 1 => '1st', 2 => '2nd', 3 => '3rd', _ => '${n}th' };
  String planetName(String key) => chart.planet(key)?.english ?? (key.isEmpty ? key : '${key[0].toUpperCase()}${key.substring(1)}');

  final lord = RegExp(r'^lord(\d+)_h(\d+)$').firstMatch(code);
  if (lord != null) return 'Lord of ${ordinal(int.parse(lord[1]!))} in ${ordinal(int.parse(lord[2]!))} house';

  final transit = RegExp(r'^transit_jupiter_h(\d+)$').firstMatch(code);
  if (transit != null) return 'Jupiter now, ${ordinal(int.parse(transit[1]!))} from Moon';

  final dasha = RegExp(r'^(mahadasha|antardasha)_(\w+)$').firstMatch(code);
  if (dasha != null) return '${planetName(dasha[2]!)} ${dasha[1] == 'mahadasha' ? 'Mahadasha' : 'Antardasha'}';

  if (code.startsWith('lagna_')) return 'Lagna in ${chart.lagna.rashi}';
  if (code.startsWith('moon_nakshatra_')) return 'Moon in ${chart.planet('moon')?.placement.nakshatra ?? 'its nakshatra'}';

  final house = RegExp(r'^([a-z]+)_h(\d+)$').firstMatch(code);
  if (house != null) return '${planetName(house[1]!)} · ${ordinal(int.parse(house[2]!))} house';

  final parts = code.split('_');
  if (parts.length == 2) {
    final planet = chart.planet(parts[0]);
    if (planet != null) {
      return switch (parts[1]) {
        'exalted' => '${planet.english} exalted',
        'debilitated' => '${planet.english} debilitated',
        'own' => '${planet.english} in own sign',
        'retrograde' => '${planet.english} retrograde',
        _ => '${planet.english} in ${planet.placement.rashi}',
      };
    }
  }
  return code.replaceAll('_', ' ');
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.child, this.padChild = true});

  final IconData icon;
  final String title;
  final Widget child;
  final bool padChild;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.border),
        boxShadow: const [AppColors.floatingShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: [
                Icon(icon, color: AppColors.gold, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: AppText.section)),
              ],
            ),
          ),
          padChild ? Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: child) : child,
        ],
      ),
    );
  }
}

const _planetGlyphs = {
  'sun': '☉',
  'moon': '☽',
  'mars': '♂',
  'mercury': '☿',
  'jupiter': '♃',
  'venus': '♀',
  'saturn': '♄',
  'rahu': '☊',
  'ketu': '☋',
};

class _PlanetCard extends StatelessWidget {
  const _PlanetCard({required this.planet, required this.line});

  final ChartPlanet planet;
  final String line;

  @override
  Widget build(BuildContext context) {
    final colour = planetColor(planet.key);
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.06),
        borderRadius: AppShape.card,
        border: Border.all(color: colour.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colour.withValues(alpha: 0.14)),
            alignment: Alignment.center,
            child: Text(_planetGlyphs[planet.key] ?? planet.abbr, style: TextStyle(fontSize: 20, color: colour)),
          ),
          const SizedBox(height: 8),
          Text(
            KundaliCopy.planetIn(planet.english, planet.placement.sign),
            style: AppText.title.copyWith(fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${planet.placement.rashi} · ${planet.house}${_suffix(planet.house)} house${planet.showRetrograde ? ' · ℞' : ''}',
            style: AppText.legal.copyWith(fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Text(line, style: AppText.meta.copyWith(fontSize: 12, height: 1.35), overflow: TextOverflow.fade),
          ),
        ],
      ),
    );
  }

  static String _suffix(int n) => switch (n) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
}

class _InsightIcon extends StatelessWidget {
  const _InsightIcon({required this.insightKey, this.size = 46});

  final String insightKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = switch (insightKey) {
      'love' => (Icons.favorite_border_rounded, AppColors.love),
      'career' => (Icons.work_outline_rounded, AppColors.insight),
      'finance' => (Icons.savings_outlined, AppColors.money),
      _ => (Icons.star_border_rounded, AppColors.career),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: colour.withValues(alpha: 0.12)),
      child: Icon(icon, color: colour, size: size * 0.5),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.insightKey, required this.insight, required this.onTap});

  final String insightKey;
  final KundaliInsight insight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = switch (insightKey) {
      'love' => AppColors.love,
      'career' => AppColors.insight,
      'finance' => AppColors.money,
      _ => AppColors.career,
    };
    return Material(
      color: tint.withValues(alpha: 0.06),
      borderRadius: AppShape.card,
      child: InkWell(
        borderRadius: AppShape.card,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InsightIcon(insightKey: insightKey, size: 40),
              const SizedBox(height: 8),
              Text(KundaliCopy.insightTitle(insightKey), style: AppText.title.copyWith(fontSize: 14)),
              const SizedBox(height: 4),
              Text(insight.summary, style: AppText.meta.copyWith(fontSize: 12.5, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dasha extends StatelessWidget {
  const _Dasha({required this.chart, required this.summary});

  final KundaliChart chart;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final dasha = chart.dasha!;
    String name(String key, String lord) => '${chart.planet(key)?.english ?? lord} ($lord)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${name(dasha.mahadashaPlanet, dasha.mahadasha)} Mahadasha, ${KundaliCopy.phase(dasha.mahaPhase)}',
          style: AppText.title.copyWith(fontSize: 15),
        ),
        Text(
          'Within it: ${name(dasha.antardashaPlanet, dasha.antardasha)} Antardasha, ${KundaliCopy.phase(dasha.antarPhase)}',
          style: AppText.meta,
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(summary, style: AppText.body),
        ],
        const SizedBox(height: 12),
        for (final span in dasha.sequence)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: span.current ? AppColors.goldWash : AppColors.surface,
              borderRadius: AppShape.control,
              border: Border.all(color: span.current ? AppColors.gold : AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: planetColor(span.planet)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(name(span.planet, span.lord), style: AppText.meta.copyWith(color: AppColors.navy))),
                if (span.current)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(KundaliCopy.now, style: AppText.legal.copyWith(color: AppColors.goldDeep, fontWeight: FontWeight.w700)),
                  ),
                Text('${span.startYear} – ${span.endYear}', style: AppText.meta.copyWith(fontSize: 13)),
              ],
            ),
          ),
      ],
    );
  }
}

class _HouseRow extends StatelessWidget {
  const _HouseRow({required this.house, required this.theme, required this.chart});

  final ChartHouse house;
  final String theme;
  final KundaliChart chart;

  @override
  Widget build(BuildContext context) {
    final occupants = [for (final key in house.occupants) chart.planet(key)?.english ?? key];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.goldWash),
            alignment: Alignment.center,
            child: Text('${house.house}', style: AppText.title.copyWith(fontSize: 13, color: AppColors.goldDeep)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${house.rashi} (${house.sign})${occupants.isEmpty ? '' : ' · ${occupants.join(', ')}'}',
                  style: AppText.title.copyWith(fontSize: 14),
                ),
                if (theme.isNotEmpty) Text(theme, style: AppText.meta.copyWith(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppShape.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.gold, size: 40),
            const SizedBox(height: 12),
            Text(message, style: AppText.body, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SizedBox(
              width: 200,
              child: PrimaryButton(label: KundaliCopy.retry, analyticsId: 'kundali_report_retry', tone: ButtonTone.navy, pill: true, onPressed: onRetry),
            ),
          ],
        ),
      ),
    );
  }
}
