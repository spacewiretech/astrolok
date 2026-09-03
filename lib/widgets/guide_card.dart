import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';
import 'safe_asset.dart';

/// A small outlined card with a glyph over a label.
///
/// Used twice in the palm flow: the "Good Lighting / Open your hand / Avoid blurry photos" row
/// under the viewfinder, and the four chips around the hand on the scan screen.
///
/// Not [FeaturePills], which looks close but is not: that draws a filled gold disc behind its
/// icon for the paywall's feature row, where this is a bordered rounded card with the glyph
/// sitting directly on the ground.
class GuideCard extends StatelessWidget {
  const GuideCard({
    super.key,
    required this.label,
    this.image,
    this.icon,
    this.tint,
    this.active = false,
    this.done = false,
  });

  final String label;

  /// An exported PNG. Falls back to [icon] when it is not in the bundle.
  final String? image;
  final IconData? icon;

  /// The glyph's colour. Navy for the capture tips, gold for the scan chips.
  final Color? tint;

  /// The stage currently running, on the scan screen: filled rather than outlined.
  final bool active;

  /// A stage already finished — the glyph is replaced by a tick.
  final bool done;

  @override
  Widget build(BuildContext context) {
    final colour = tint ?? AppColors.navy;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: active ? AppColors.goldWash : AppColors.surface,
        borderRadius: AppShape.control,
        border: Border.all(
          color: active ? AppColors.gold : AppColors.border,
          width: active ? 1.4 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 26,
            child: done
                ? const Icon(Icons.check_circle, size: 22, color: AppColors.success)
                : image == null
                    ? Icon(icon ?? Icons.auto_awesome_outlined, size: 22, color: colour)
                    : SafeImage(
                        image!,
                        width: 24,
                        height: 24,
                        fit: BoxFit.contain,
                        fallback: Icon(
                          icon ?? Icons.auto_awesome_outlined,
                          size: 22,
                          color: colour,
                        ),
                      ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppText.tileLabel.copyWith(fontSize: 12),
            textAlign: TextAlign.center,
            // Two lines is what the design's longest label needs; a third means the copy has
            // outgrown the column and should be shortened rather than clipped.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
