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
import '../../data/models/face_reading.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/ask_astro_row.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/safe_asset.dart';
import '../../widgets/speak_button.dart';
import '../../widgets/status_chip.dart';
import 'face_copy.dart';
import 'face_reading_state.dart';
import 'face_reading_viewmodel.dart';

/// Step three: the reading itself.
///
/// On white rather than the warm ground the first two steps use — the design switches here,
/// and it is the right call: this screen is dense with text and the zodiac artwork behind it
/// would fight every card.
class FaceReadingView extends ConsumerWidget {
  const FaceReadingView({super.key, required this.readingId});

  final String readingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(faceReadingViewModelProvider(readingId));
    final model = ref.read(faceReadingViewModelProvider(readingId).notifier);

    ref.listen(
      faceReadingViewModelProvider(readingId).select((s) => s.error),
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
                ? _Missing(onBack: () => context.go(Routes.faceCapture))
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

  final FaceReadingState state;
  final FaceReadingViewModel model;
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
                semanticLabel: FaceCopy.download,
                busy: state.exporting,
                onTap: model.exportPdf,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppShape.gutter,
              12,
              AppShape.gutter,
              32,
            ),
            children: [
              const AccentHeading(
                lead: FaceCopy.readingTitleLead,
                accent: FaceCopy.readingTitleAccent,
                tail: FaceCopy.readingTitleTail,
              ),
              const SizedBox(height: 8),
              Text(
                reading.headline.isEmpty ? FaceCopy.readingSubtitle : reading.headline,
                style: AppText.body,
                textAlign: TextAlign.center,
              ),

              if (reading.invocation.isNotEmpty) ...[
                const SizedBox(height: 14),
                _Invocation(text: reading.invocation),
              ],

              if (state.canSpeak) ...[
                const SizedBox(height: 16),
                SpeakButton(
                  speaking: state.speaking,
                  onTap: () => model.toggleSpeech(reading.spoken),
                  listenLabel: FaceCopy.listen,
                  stopLabel: FaceCopy.stopListening,
                  alignment: Alignment.center,
                ),
              ],

              const SizedBox(height: 22),
              _Portrait(image: state.image),

              if (!reading.coreTrait.isEmpty) ...[
                const SizedBox(height: 18),
                _CoreTraitCard(trait: reading.coreTrait),
              ],

              if (reading.traits.isNotEmpty) ...[
                const SizedBox(height: 16),
                _TraitRow(traits: reading.traits),
              ],

              if (reading.face.observations.isNotEmpty) ...[
                const SizedBox(height: 26),
                Text(FaceCopy.observationsHeading, style: AppText.section),
                const SizedBox(height: 10),
                for (final observation in reading.face.observations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(top: 8, right: 10),
                          decoration: const BoxDecoration(
                            color: AppColors.gold,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(child: Text(observation, style: AppText.meta)),
                      ],
                    ),
                  ),
              ],

              const SizedBox(height: 26),
              Text(FaceCopy.partsHeading, style: AppText.section),
              const SizedBox(height: 4),

              for (final part in reading.parts)
                _PartRow(
                  part: part,
                  onTap: () {
                    model.stopSpeech();
                    analytics.track(Ev.readingDetailOpened, {
                      P.feature: ReadingFeature.face,
                      P.readingId: readingId,
                      P.detail: part.kind.name,
                    });
                    context.push(Routes.facePartFor(readingId, part.kind));
                  },
                ),

              if (reading.blessing.isNotEmpty) ...[
                const SizedBox(height: 22),
                _BlessingCard(text: reading.blessing),
              ],

              const SizedBox(height: 26),
              Text(FaceCopy.moreHeading, style: AppText.section),
              const SizedBox(height: 12),
              AskAstroRow(
                title: FaceCopy.askAstroTitle,
                subtitle: FaceCopy.askAstroSubtitle,
                onTap: () {
                  model.stopSpeech();
                  analytics.track(Ev.askAstroTapped, {
                    P.feature: ReadingFeature.face,
                    P.readingId: readingId,
                    P.source: 'face_reading',
                  });
                  context.push(Routes.chat, extra: FaceCopy.askAstroSeed);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The opening line, set apart so it reads as the reader speaking rather than as body copy.
class _Invocation extends StatelessWidget {
  const _Invocation({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppText.body.copyWith(color: AppColors.goldDeep, height: 1.5),
      textAlign: TextAlign.center,
    );
  }
}

/// The photograph, gold-framed, as in the design.
class _Portrait extends StatelessWidget {
  const _Portrait({required this.image});

  final Uint8List? image;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 190,
        height: 190,
        decoration: BoxDecoration(
          borderRadius: AppShape.card,
          border: Border.all(color: AppColors.gold, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: image == null
            // The reading text outlives its picture — after a reinstall, or on a second
            // device. A mark rather than a grey box, so the gap reads as designed.
            ? const ColoredBox(
                color: AppColors.goldWash,
                child: Center(child: BrandMark(size: 56)),
              )
            : Image.memory(image!, fit: BoxFit.cover),
      ),
    );
  }
}

/// "Your core Trait — Naturally Intuitive".
class _CoreTraitCard extends StatelessWidget {
  const _CoreTraitCard({required this.trait});

  final FaceCoreTrait trait;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.cardSoft,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.gold),
              const SizedBox(width: 7),
              Text(FaceCopy.coreTrait, style: AppText.meta),
            ],
          ),
          const SizedBox(height: 8),
          Text(trait.title, style: AppText.section, textAlign: TextAlign.center),
          if (trait.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(trait.summary, style: AppText.meta, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// The four chips under the core trait.
class _TraitRow extends StatelessWidget {
  const _TraitRow({required this.traits});

  final List<FaceTraitKind> traits;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final trait in traits) ...[
          if (trait != traits.first) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: AppShape.control,
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Icon(trait.icon, size: 22, color: trait.color),
                  const SizedBox(height: 6),
                  // `tileLabel` rather than `title`: four chips share the width, which leaves
                  // about 70pt each, and the longest words in the vocabulary — "Independent",
                  // "Determined", "Disciplined" — ellipsise at anything larger.
                  Text(
                    trait.label,
                    style: AppText.tileLabel.copyWith(color: AppColors.heading),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One row of the "Your Face Reveals" list.
class _PartRow extends StatelessWidget {
  const _PartRow({required this.part, required this.onTap});

  final FacePart part;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = part.kind.accent;
    final asset = part.kind.asset;

    return Semantics(
      button: true,
      label: '${part.title}, ${part.status.label}. ${part.summary}',
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
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: AppShape.control,
                ),
                child: Center(
                  child: asset == null
                      ? Icon(part.kind.icon, size: 24, color: accent)
                      : SafeImage(
                          asset,
                          width: 26,
                          height: 26,
                          fit: BoxFit.contain,
                          fallback: Icon(part.kind.icon, size: 24, color: accent),
                        ),
                ),
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
                            part.title,
                            style: AppText.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusChip(
                          label: part.status.label,
                          color: part.status.color,
                          dense: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // The category gloss, not the reading's own summary. The design lists a
                    // stable "Emotions & Intuition" under each feature so the six rows read as
                    // a map of what is covered; the reading's summary is on the detail page,
                    // where there is room for it.
                    Text(
                      part.kind.subtitle,
                      style: AppText.meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
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
                FaceCopy.blessingHeading,
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
          const Icon(
            Icons.face_retouching_natural_outlined,
            size: 48,
            color: AppColors.gold,
          ),
          const SizedBox(height: 16),
          Text(
            FaceCopy.readingMissing,
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: FaceCopy.takePhotoAction,
            tone: ButtonTone.navy,
            onPressed: onBack,
          ),
        ],
      ),
    );
  }
}
