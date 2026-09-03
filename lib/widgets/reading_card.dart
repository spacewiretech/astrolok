import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';
import 'safe_asset.dart';

/// One row of Home's "Explore Readings" list: artwork, title, subtitle, gold chevron disc.
class ReadingCard extends StatelessWidget {
  const ReadingCard({
    super.key,
    required this.image,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.fallbackIcon = Icons.auto_awesome_outlined,
  });

  final String image;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// Stands in until the thumbnail is exported.
  final IconData fallbackIcon;

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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: SafeImage(
                    image,
                    fit: BoxFit.contain,
                    fallback: Center(
                      child: Icon(fallbackIcon, size: 30, color: AppColors.gold),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: AppText.title),
                      const SizedBox(height: 3),
                      Text(subtitle, style: AppText.meta),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const _ChevronDisc(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChevronDisc extends StatelessWidget {
  const _ChevronDisc();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppShape.chevronDisc,
      height: AppShape.chevronDisc,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.gold, width: 1.4),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.navy),
    );
  }
}
