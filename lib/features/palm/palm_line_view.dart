import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/models/palm_reading.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/info_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/safe_asset.dart';
import '../../widgets/speak_button.dart';
import '../../widgets/status_chip.dart';
import 'palm_copy.dart';
import 'palm_reading_viewmodel.dart';

/// One line, in full.
class PalmLineView extends ConsumerWidget {
  const PalmLineView({super.key, required this.readingId, required this.line});

  /// Null when the URL named a line this build does not know.
  final PalmLineKind? line;

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

    final kind = line;
    final reading = state.reading;
    final entry = kind == null ? null : reading?.line(kind);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: state.loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : entry == null
                ? _Missing(
                    onBack: () => context.canPop()
                        ? context.pop()
                        : context.go(Routes.palmCapture),
                  )
                : _Line(
                    line: entry,
                    focus: reading!.focus,
                    image: state.image,
                    speaking: state.speaking,
                    canSpeak: state.canSpeak,
                    exporting: state.exporting,
                    onSpeak: () => model.toggleSpeech(entry.spoken),
                    onExport: model.exportPdf,
                    onBack: () {
                      model.stopSpeech();
                      context.canPop() ? context.pop() : context.go(Routes.home);
                    },
                    onAskAstro: () {
                      // The narration has to stop before the chat opens: the speech engine is
                      // app-wide, so a line left playing would talk over the sage.
                      model.stopSpeech();
                      context.push(
                        Routes.chat,
                        extra: PalmCopy.askAstroSeedFor(entry.title.toLowerCase()),
                      );
                    },
                  ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.line,
    required this.focus,
    required this.image,
    required this.speaking,
    required this.canSpeak,
    required this.exporting,
    required this.onSpeak,
    required this.onExport,
    required this.onBack,
    required this.onAskAstro,
  });

  final PalmLine line;
  final PalmFocus focus;
  final Uint8List? image;
  final bool speaking;
  final bool canSpeak;
  final bool exporting;
  final VoidCallback onSpeak;
  final VoidCallback onExport;
  final VoidCallback onBack;
  final VoidCallback onAskAstro;

  @override
  Widget build(BuildContext context) {
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
                onTap: onBack,
              ),
              const Spacer(),
              CircleIconButton(
                icon: Icons.file_download_outlined,
                semanticLabel: PalmCopy.download,
                busy: exporting,
                onTap: onExport,
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppShape.gutter,
              24,
              AppShape.gutter,
              24,
            ),
            children: [
              Text(line.title, style: AppText.display),
              if (line.sanskrit.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  line.sanskrit,
                  style: AppText.title.copyWith(fontSize: 15, color: line.kind.accent),
                ),
              ],
              const SizedBox(height: 6),
              Text(line.kind.subtitle, style: AppText.body),

              if (canSpeak) ...[
                const SizedBox(height: 16),
                SpeakButton(
                  speaking: speaking,
                  onTap: onSpeak,
                  listenLabel: PalmCopy.listen,
                  stopLabel: PalmCopy.stopListening,
                  color: line.kind.accent,
                ),
              ],

              const SizedBox(height: 20),
              _Hero(line: line, focus: focus, image: image),

              if (line.meaning.isNotEmpty) ...[
                const SizedBox(height: 20),
                InfoCard(
                  title: PalmCopy.meansForYou,
                  accent: line.kind.accent,
                  icon: Icons.auto_awesome_rounded,
                  bullets: line.meaning,
                ),
              ],

              if (line.tip.isNotEmpty) ...[
                const SizedBox(height: 14),
                InfoCard(
                  title: PalmCopy.tip,
                  accent: line.kind.accent,
                  icon: Icons.lightbulb_outline_rounded,
                  body: line.tip,
                  filled: true,
                ),
              ],

              if (line.blessing.isNotEmpty) ...[
                const SizedBox(height: 14),
                InfoCard(
                  title: PalmCopy.blessingHeading,
                  accent: AppColors.goldDeep,
                  icon: Icons.spa_outlined,
                  body: line.blessing,
                ),
              ],
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppShape.gutter,
            0,
            AppShape.gutter,
            12,
          ),
          child: PrimaryButton(
            label: 'Ask Astro about your ${line.title.toLowerCase()}',
            tone: ButtonTone.navy,
            icon: Icons.chat_bubble_outline_rounded,
            // Seeded with this line specifically, so the conversation opens where the button
            // promised rather than at the top of the reading.
            onPressed: onAskAstro,
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.line, required this.focus, required this.image});

  final PalmLine line;
  final PalmFocus focus;
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
              width: 100,
              height: 170,
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
                  label: 'Focus: ${line.title}',
                  color: line.kind.accent,
                  icon: line.kind.icon,
                  dense: true,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: line.kind.accent.withValues(alpha: 0.05),
                    borderRadius: AppShape.control,
                    border: Border.all(
                      color: line.kind.accent.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusChip(
                        label: line.status.label,
                        color: line.status.color,
                        dense: true,
                      ),
                      const SizedBox(height: 8),
                      Text(line.detail, style: AppText.body.copyWith(fontSize: 14)),
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
            label: 'Go back',
            tone: ButtonTone.navy,
            onPressed: onBack,
          ),
        ],
      ),
    );
  }
}
