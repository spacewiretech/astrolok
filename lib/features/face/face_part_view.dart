import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/models/face_reading.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/info_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/safe_asset.dart';
import '../../widgets/speak_button.dart';
import '../../widgets/status_chip.dart';
import 'face_copy.dart';
import 'face_reading_viewmodel.dart';

/// One feature of the face, read in full.
///
/// Everything on this page takes the feature's own accent — purple for the eyes, gold for the
/// face shape — so the six detail screens are told apart at a glance rather than being six
/// identical pages with different words.
class FacePartView extends ConsumerWidget {
  const FacePartView({super.key, required this.readingId, required this.part});

  final String readingId;

  /// Null when the URL names a feature this build does not know. Handled rather than asserted:
  /// a route can outlive the build that understood it.
  final FacePartKind? part;

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

    final kind = part;
    final reading = state.reading;
    final entry = kind == null ? null : reading?.part(kind);

    void back() {
      model.stopSpeech();
      context.canPop() ? context.pop() : context.go(Routes.home);
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: state.loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : entry == null
                ? _Missing(onBack: back)
                : _Part(
                    part: entry,
                    image: state.image,
                    canSpeak: state.canSpeak,
                    speaking: state.speaking,
                    exporting: state.exporting,
                    onSpeak: () => model.toggleSpeech(entry.spoken),
                    onExport: model.exportPdf,
                    onBack: back,
                    onAskAstro: () {
                      // The speech engine is app-wide, so a feature left playing would talk
                      // over the sage.
                      model.stopSpeech();
                      context.push(
                        Routes.chat,
                        extra: FaceCopy.askAstroSeedFor(entry.kind.possessive),
                      );
                    },
                  ),
      ),
    );
  }
}

class _Part extends StatelessWidget {
  const _Part({
    required this.part,
    required this.image,
    required this.canSpeak,
    required this.speaking,
    required this.exporting,
    required this.onSpeak,
    required this.onExport,
    required this.onBack,
    required this.onAskAstro,
  });

  final FacePart part;
  final Uint8List? image;
  final bool canSpeak;
  final bool speaking;
  final bool exporting;
  final VoidCallback onSpeak;
  final VoidCallback onExport;
  final VoidCallback onBack;
  final VoidCallback onAskAstro;

  @override
  Widget build(BuildContext context) {
    final accent = part.kind.accent;

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
                semanticLabel: FaceCopy.download,
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
              // The traditional name goes on its own line under the title rather than beside
              // it. Sharing a row cost the title its width and wrapped "Eye Reading" onto two
              // lines, and the widths involved depend on the rendered face — which is not
              // something a layout should be betting on.
              Text(part.kind.readingTitle, style: AppText.display),
              if (part.sanskrit.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  part.sanskrit,
                  style: AppText.title.copyWith(fontSize: 15, color: accent),
                ),
              ],
              const SizedBox(height: 6),
              Text(part.kind.promise, style: AppText.body),

              if (canSpeak) ...[
                const SizedBox(height: 16),
                SpeakButton(
                  speaking: speaking,
                  onTap: onSpeak,
                  listenLabel: FaceCopy.listen,
                  stopLabel: FaceCopy.stopListening,
                  color: accent,
                ),
              ],

              const SizedBox(height: 20),
              _Hero(part: part, image: image),

              if (part.meaning.isNotEmpty) ...[
                const SizedBox(height: 20),
                InfoCard(
                  title: FaceCopy.meansForYou,
                  accent: accent,
                  icon: Icons.auto_awesome_rounded,
                  bullets: part.meaning,
                ),
              ],

              if (part.tip.isNotEmpty) ...[
                const SizedBox(height: 14),
                InfoCard(
                  title: FaceCopy.tip,
                  accent: accent,
                  icon: Icons.lightbulb_outline_rounded,
                  body: part.tip,
                  filled: true,
                ),
              ],

              if (part.blessing.isNotEmpty) ...[
                const SizedBox(height: 14),
                InfoCard(
                  title: FaceCopy.blessingHeading,
                  accent: AppColors.goldDeep,
                  icon: Icons.spa_outlined,
                  body: part.blessing,
                ),
              ],
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(AppShape.gutter, 0, AppShape.gutter, 12),
          child: PrimaryButton(
            label: FaceCopy.askAstroAbout(part.kind.possessive),
            tone: ButtonTone.navy,
            icon: Icons.chat_bubble_outline_rounded,
            onPressed: onAskAstro,
          ),
        ),
      ],
    );
  }
}

/// The photograph, the status chip and the paragraph that carries the reading.
class _Hero extends StatelessWidget {
  const _Hero({required this.part, required this.image});

  final FacePart part;
  final Uint8List? image;

  @override
  Widget build(BuildContext context) {
    final accent = part.kind.accent;
    final asset = part.kind.asset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (image != null)
          ClipRRect(
            borderRadius: AppShape.card,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.memory(
                image!,
                fit: BoxFit.cover,
                // The design crops in on the feature. There is no landmark data on the device
                // to crop by, so the frame stays on the upper face, where five of the six
                // features are — an honest approximation rather than a wrong one.
                alignment: switch (part.kind) {
                  FacePartKind.lips => const Alignment(0, 0.55),
                  FacePartKind.nose => Alignment.center,
                  FacePartKind.forehead => const Alignment(0, -0.85),
                  _ => const Alignment(0, -0.45),
                },
              ),
            ),
          ),
        if (image != null) const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppShape.card,
            border: Border.all(color: AppColors.border),
            boxShadow: const [AppColors.floatingShadow],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusChip(label: part.status.label, color: part.status.color),
                  const Spacer(),
                  // Forehead and eyebrows ship no glyph, so they take the Material icon
                  // directly rather than asking SafeImage to fail its way to the same place.
                  if (asset == null)
                    Icon(part.kind.icon, size: 22, color: accent)
                  else
                    SafeImage(
                      asset,
                      width: 22,
                      height: 22,
                      fit: BoxFit.contain,
                      fallback: Icon(part.kind.icon, size: 22, color: accent),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(part.detail, style: AppText.body.copyWith(height: 1.55)),
            ],
          ),
        ),
      ],
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
            label: 'Go back',
            tone: ButtonTone.navy,
            onPressed: onBack,
          ),
        ],
      ),
    );
  }
}
