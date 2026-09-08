import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/models/palm_reading.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/ask_astro_row.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/safe_asset.dart';
import '../../widgets/speak_button.dart';
import '../../widgets/status_chip.dart';
import 'palm_copy.dart';
import 'palm_reading_state.dart';
import 'palm_reading_viewmodel.dart';

/// Step three: the reading itself.
///
/// On white rather than the warm ground the first two steps use — the design switches here,
/// and it is the right call: this screen is dense with text and the zodiac artwork behind it
/// would fight every card.
class PalmReadingView extends ConsumerWidget {
  const PalmReadingView({super.key, required this.readingId});

  final String readingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(palmReadingViewModelProvider(readingId));
    final model = ref.read(palmReadingViewModelProvider(readingId).notifier);

    ref.listen(
      palmReadingViewModelProvider(readingId).select((s) => s.error),
      (_, error) {
        if (error != null) showAppSnackBar(context, error, error: true);
      },
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: state.loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : state.reading == null
                ? _Missing(onBack: () => context.go(Routes.palmCapture))
                : _Reading(state: state, model: model, readingId: readingId),
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({
    required this.state,
    required this.model,
    required this.readingId,
  });

  final PalmReadingState state;
  final PalmReadingViewModel model;
  final String readingId;

  @override
  Widget build(BuildContext context) {
    final reading = state.reading!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppShape.gutter, 4, AppShape.gutter, 0),
          child: Row(
            children: [
              CircleIconButton(
                image: PalmIcon.backCircle,
                icon: Icons.chevron_left_rounded,
                semanticLabel: 'Back',
                onTap: () {
                  model.stopSpeech();
                  // The scan screen it came from was replaced, so there is nothing sensible
                  // behind this except Home.
                  context.canPop() ? context.pop() : context.go(Routes.home);
                },
              ),
              const Spacer(),
              CircleIconButton(
                icon: Icons.file_download_outlined,
                semanticLabel: PalmCopy.download,
                busy: state.exporting,
                onTap: model.exportPdf,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Padding(
        //   padding: const EdgeInsets.symmetric(horizontal: AppShape.gutter + 12),
        //   // Past the last step, so all three read as complete.
        //   child: const StepIndicator(labels: PalmCopy.steps, current: 2),
        // ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppShape.gutter,
              28,
              AppShape.gutter,
              32,
            ),
            children: [
              const AccentHeading(
                lead: PalmCopy.readingTitleLead,
                accent: PalmCopy.readingTitleAccent,
                textAlign: TextAlign.left,
              ),
              const SizedBox(height: 6),
              Text(
                reading.headline.isEmpty ? PalmCopy.readingSubtitle : reading.headline,
                style: AppText.body,
              ),

              if (reading.invocation.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  reading.invocation,
                  style: AppText.body.copyWith(color: AppColors.goldDeep, height: 1.5),
                ),
              ],

              if (state.canSpeak) ...[
                const SizedBox(height: 16),
                SpeakButton(
                  speaking: state.speaking,
                  onTap: () => model.toggleSpeech(reading.spoken),
                  listenLabel: PalmCopy.listen,
                  stopLabel: PalmCopy.stopListening,
                ),
              ],

              const SizedBox(height: 20),
              _HeroCard(reading: reading, image: state.image),

              if (reading.hand.chips.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(PalmCopy.handHeading, style: AppText.section),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final chip in reading.hand.chips)
                      StatusChip(
                        label: chip,
                        color: AppColors.body,
                        background: AppColors.cardSoft,
                        dense: true,
                      ),
                  ],
                ),
              ],

              const SizedBox(height: 28),
              Text(PalmCopy.linesHeading, style: AppText.section),
              const SizedBox(height: 8),

              for (final line in reading.lines)
                _LineRow(
                  line: line,
                  onTap: () {
                    model.stopSpeech();
                    analytics.track(Ev.readingDetailOpened, {
                      P.feature: ReadingFeature.palm,
                      P.readingId: readingId,
                      P.detail: line.kind.name,
                    });
                    context.push(Routes.palmLineFor(readingId, line.kind));
                  },
                ),

              if (reading.blessing.isNotEmpty) ...[
                const SizedBox(height: 22),
                _BlessingCard(text: reading.blessing),
              ],

              const SizedBox(height: 24),
              Text(PalmCopy.moreHeading, style: AppText.section),
              const SizedBox(height: 12),
              AskAstroRow(
                title: PalmCopy.askAstroTitle,
                subtitle: PalmCopy.askAstroSubtitle,
                onTap: () {
                  model.stopSpeech();
                  // Seeded, so the chat opens already discussing this reading rather than on a
                  // blank screen. The server loads the newest reading for grounding anyway.
                  analytics.track(Ev.askAstroTapped, {
                    P.feature: ReadingFeature.palm,
                    P.readingId: readingId,
                    P.source: 'palm_reading',
                  });
                  context.push(Routes.chat, extra: PalmCopy.askAstroSeed);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The photo, the focus pill and the headline trait.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.reading, required this.image});

  final PalmReading reading;
  final Uint8List? image;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.border),
        boxShadow: const [AppColors.floatingShadow],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: AppShape.control,
            child: SizedBox(
              width: 110,
              height: 150,
              // Falls back to the palm artwork when the photo is gone — after a reinstall, or
              // on a second device. The reading text outlives its picture by design.
              child: image == null
                  ? SafeImage(
                      Img.readingPalm,
                      fit: BoxFit.cover,
                      fallback: const ColoredBox(color: AppColors.goldWash),
                    )
                  : Image.memory(image!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusChip(
                  label: PalmCopy.focusLabel(reading.focus.label),
                  color: reading.focus.color,
                  icon: reading.focus.icon,
                  dense: true,
                ),
                const SizedBox(height: 10),
                if (!reading.strongestTrait.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardSoft,
                      borderRadius: AppShape.control,
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.auto_awesome_rounded,
                              size: 15,
                              color: AppColors.gold,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                PalmCopy.strongestTrait,
                                style: AppText.meta.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.gold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          reading.strongestTrait.title,
                          style: AppText.title.copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          reading.strongestTrait.summary,
                          style: AppText.meta.copyWith(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the "Your Palm lines" list.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.onTap});

  final PalmLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${line.title}, ${line.status.label}. ${line.summary}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppShape.card,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: line.kind.accent.withValues(alpha: 0.1),
                  borderRadius: AppShape.control,
                ),
                child: Icon(line.kind.icon, size: 24, color: line.kind.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            line.title,
                            style: AppText.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusChip(
                          label: line.status.label,
                          color: line.status.color,
                          dense: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      line.summary.isEmpty ? line.kind.subtitle : line.summary,
                      style: AppText.meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The closing ashirvad.
class _BlessingCard extends StatelessWidget {
  const _BlessingCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSoft,
        borderRadius: AppShape.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandMark(size: 24),
              const SizedBox(width: 8),
              Text(
                PalmCopy.blessingHeading,
                style: AppText.title.copyWith(fontSize: 14, color: AppColors.goldDeep),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(text, style: AppText.body.copyWith(height: 1.5)),
        ],
      ),
    );
  }
}


class _Missing extends StatelessWidget {
  const _Missing({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppShape.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.back_hand_outlined, size: 48, color: AppColors.gold),
          const SizedBox(height: 16),
          Text(
            PalmCopy.readingMissing,
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: PalmCopy.scanAction,
            tone: ButtonTone.navy,
            onPressed: onBack,
          ),
        ],
      ),
    );
  }
}
