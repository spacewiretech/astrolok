import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';

/// A titled card holding either bullets or a paragraph.
///
/// Two appearances on the line detail screen — the white "What it means for you" card and the
/// tinted "Tip" card beneath it — which are the same object with a different ground, so they
/// are one widget rather than two that must be kept in step.
class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.title,
    required this.accent,
    this.icon,
    this.bullets = const [],
    this.body,
    this.filled = false,
  });

  final String title;

  /// Tints the icon, the title, and — when [filled] — the ground.
  final Color accent;

  final IconData? icon;

  final List<String> bullets;

  /// Shown instead of [bullets] when there are none.
  final String? body;

  /// A wash of [accent] rather than white. The Tip card.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: filled ? accent.withValues(alpha: 0.07) : AppColors.surface,
        borderRadius: AppShape.card,
        border: Border.all(
          color: filled ? accent.withValues(alpha: 0.18) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  title,
                  style: AppText.title.copyWith(fontSize: 15, color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (bullets.isNotEmpty)
            for (final bullet in bullets)
              Padding(
                padding: EdgeInsets.only(bottom: bullet == bullets.last ? 0 : 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A drawn dot rather than a bullet character, so it stays aligned with the
                    // first line of text however the label wraps.
                    Container(
                      margin: const EdgeInsets.only(top: 7, right: 10),
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: AppColors.muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(child: Text(bullet, style: AppText.body)),
                  ],
                ),
              )
          else if (body != null)
            Text(body!, style: AppText.body),
        ],
      ),
    );
  }
}
