import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';

enum StageStatus { done, active, pending }

@immutable
class StageItem {
  const StageItem({required this.title, required this.status, this.detail});

  final String title;
  final StageStatus status;

  /// A line under the title — shown for the active stage.
  final String? detail;
}

/// The waiting screen's list of what is being prepared, each stage ticked, in progress or ahead.
class StageChecklist extends StatelessWidget {
  const StageChecklist({super.key, required this.items});

  final List<StageItem> items;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.border),
        boxShadow: const [AppColors.floatingShadow],
      ),
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox.square(dimension: 26, child: _marker(item.status, still)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: AppText.title.copyWith(
                            fontSize: 15,
                            color: item.status == StageStatus.pending ? AppColors.muted : AppColors.navy,
                          ),
                        ),
                        if (item.detail != null && item.status == StageStatus.active)
                          Text(item.detail!, style: AppText.meta.copyWith(fontSize: 13)),
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

  Widget _marker(StageStatus status, bool still) => switch (status) {
        StageStatus.done => const DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.gold),
            child: Icon(Icons.check_rounded, size: 17, color: Colors.white),
          ),
        StageStatus.active => DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.gold, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: still
                  ? const Icon(Icons.more_horiz_rounded, size: 12, color: AppColors.goldDeep)
                  : const CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
            ),
          ),
        StageStatus.pending => DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.fieldBorder, width: 1.5),
            ),
          ),
      };
}
