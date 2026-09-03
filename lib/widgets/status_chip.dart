import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_typography.dart';
import '../app/theme/app_theme.dart';

/// The small rounded label beside a palm line's title — "Strong", "Balanced", "Deep".
///
/// Colour is passed in rather than derived here, because it belongs to the thing being
/// labelled: [PalmLineStatus] owns its own tint, and this widget only draws it.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.background,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color color;

  /// Defaults to [color] at a wash. Passed explicitly for the solid navy "Hand Detected" pill.
  final Color? background;

  final IconData? icon;

  /// Tighter padding for a chip sitting inside a row rather than standing alone.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12, vertical: dense ? 4 : 6),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: AppShape.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 13 : 15, color: color),
            const SizedBox(width: 5),
          ],
          // Flexible, not a bare Text: a chip labelled with a long focus name
          // ("Focus: Personality & Strengths") sits beside a title in a Row, and a min-sized
          // Row would rather overflow than let its text shrink.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.meta.copyWith(
                fontSize: dense ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dark pill that floats under the viewfinder while the camera is live.
///
/// Two states, and the wording of each matters: before a capture the app genuinely does not
/// know whether it is looking at a hand — nothing on the device is examining the frame — so it
/// says what to do rather than claiming a detection it has not made. Only after the server has
/// actually read the photo does it assert anything.
class DetectionPill extends StatelessWidget {
  const DetectionPill({super.key, required this.detected, required this.label});

  final bool detected;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: AppShape.pill,
        boxShadow: const [AppColors.floatingShadow],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The guidance wording is a full phrase, and on a 360pt screen the pill's padding
          // leaves it barely enough room. Flexible lets it shrink rather than overflow.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.meta.copyWith(
                color: detected ? AppColors.success : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (detected) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_circle, size: 18, color: AppColors.success),
          ],
        ],
      ),
    );
  }
}
