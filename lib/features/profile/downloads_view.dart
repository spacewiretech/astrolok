import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/models/face_reading.dart' show FacePartKind;
import '../../data/models/palm_reading.dart' show PalmLineKind;
import '../../widgets/astral_background.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/primary_button.dart';
import 'downloads_viewmodel.dart';

/// Every reading still on this device.
///
/// Backed by the two local caches rather than by a server endpoint — there is no history API,
/// and each cache keeps its newest ten. A reading that has aged out of both is gone, which the
/// empty state says plainly rather than implying a sync problem.
///
/// Tapping a row opens the reading, where the download button already lives. That is why there
/// is no per-row export here: one export button, on the screen that has the reading loaded, is
/// less to keep in step than two.
class DownloadsView extends ConsumerWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(downloadsViewModelProvider);

    return Scaffold(
      body: AstralBackground(
        surface: AstralSurface.home,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppShape.gutter, 4, AppShape.gutter, 0),
                child: Row(
                  children: [
                    CircleIconButton(
                      image: PalmIcon.backCircle,
                      icon: Icons.chevron_left_rounded,
                      semanticLabel: 'Back',
                      onTap: () =>
                          context.canPop() ? context.pop() : context.go(Routes.profile),
                    ),
                    Expanded(
                      child: Text(
                        'Downloads',
                        style: AppText.section,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: AppShape.avatar),
                  ],
                ),
              ),

              Expanded(
                child: entries.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  ),
                  // A cache that will not load is not worth an error screen: it reads exactly
                  // like having no readings yet, and the way out is the same.
                  error: (error, stack) => const _Empty(),
                  data: (readings) => readings.isEmpty
                      ? const _Empty()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            AppShape.gutter,
                            20,
                            AppShape.gutter,
                            32,
                          ),
                          itemCount: readings.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) => _ReadingRow(
                            reading: readings[index],
                            onTap: () => _open(context, readings[index]),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the reading itself, where Listen and Download already are.
  void _open(BuildContext context, SavedReading reading) {
    context.push(
      switch (reading.kind) {
        SavedReadingKind.palm => Routes.palmReadingFor(reading.id),
        SavedReadingKind.face => Routes.faceReadingFor(reading.id),
      },
    );
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({required this.reading, required this.onTap});

  final SavedReading reading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, icon, accent) = switch (reading.kind) {
      SavedReadingKind.palm => (
          'Palm Reading',
          PalmLineKind.heart.icon,
          AppColors.gold,
        ),
      SavedReadingKind.face => (
          'Face Reading',
          FacePartKind.eyes.icon,
          AppColors.career,
        ),
    };

    return Material(
      color: AppColors.surface,
      borderRadius: AppShape.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: AppShape.card,
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: AppShape.control,
                ),
                child: Icon(icon, size: 24, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppText.title),
                    const SizedBox(height: 3),
                    Text(
                      reading.title.isEmpty
                          ? reading.focusLabel
                          : reading.title,
                      style: AppText.meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(reading.createdAt),
                      style: AppText.legal,
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

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppShape.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.auto_stories_outlined,
            size: 48,
            color: AppColors.gold,
          ),
          const SizedBox(height: 16),
          Text(
            'No readings saved on this device yet.',
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Read your palm or your face, and it will be waiting here.',
            style: AppText.meta,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Read my palm',
            tone: ButtonTone.navy,
            onPressed: () => context.push(Routes.palmCapture),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: 'Read my face',
            tone: ButtonTone.outline,
            onPressed: () => context.push(Routes.faceCapture),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
