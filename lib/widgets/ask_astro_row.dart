import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';
import 'brand_logo.dart';

/// The "Want to know more?" row at the foot of a reading.
///
/// Was a private widget in `palm_reading_view.dart` and again, near-identically, in
/// `face_reading_view.dart` — the palm copy took only `onTap`, the face one `title` and `onTap`,
/// which is the sort of drift two copies acquire. One widget now, since both open the same chat.
class AskAstroRow extends StatelessWidget {
  const AskAstroRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              const BrandMark(size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.title),
                    const SizedBox(height: 3),
                    Text(subtitle, style: AppText.meta),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
