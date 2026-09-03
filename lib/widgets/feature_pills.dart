import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';
import 'safe_asset.dart';

/// One of the paywall's four selling points: a gold disc over a two-line label.
class Feature {
  const Feature({required this.icon, required this.label, this.fallbackIcon});

  /// SVG path. Falls back to [fallbackIcon] until the artwork is exported.
  final String icon;
  final String label;
  final IconData? fallbackIcon;
}

/// The row of four. Laid out with equal-width columns so the two-line labels align on their
/// first line whatever their length.
class FeaturePills extends StatelessWidget {
  const FeaturePills({super.key, required this.features});

  final List<Feature> features;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final feature in features)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                children: [
                  Container(
                    width: AppShape.featureDisc,
                    height: AppShape.featureDisc,
                    decoration: const BoxDecoration(
                      color: AppColors.goldWash,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: SafeSvg(
                      feature.icon,
                      width: 24,
                      height: 24,
                      color: AppColors.gold,
                      fallback: Icon(
                        feature.fallbackIcon ?? Icons.auto_awesome_outlined,
                        size: 24,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    feature.label,
                    style: AppText.tileLabel,
                    textAlign: TextAlign.center,
                    // The labels carry their own line break; a third line means the text has
                    // outgrown the column and should be shortened rather than clipped.
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
