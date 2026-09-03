import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import 'safe_asset.dart';

/// The round white button in a screen's top corners — back on the left, download on the right.
///
/// Used on all four palm screens. The paywall has a private `_CircleButton` of its own that
/// predates this; that one stays where it is rather than being pulled out mid-feature, since
/// moving it would put an unrelated screen in this changeset.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.onTap,
    required this.semanticLabel,
    this.icon,
    this.image,
    this.size = 48,
    this.busy = false,
  });

  final VoidCallback? onTap;

  /// Read out in place of the glyph, which carries no meaning on its own.
  final String semanticLabel;

  /// Drawn when [image] is absent or missing from the bundle.
  final IconData? icon;

  /// An exported PNG, preferred over [icon] when it is in the bundle.
  final String? image;

  final double size;

  /// Swaps the glyph for a spinner — the download button while the PDF is being built.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final glyph = busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy),
          )
        : image == null
            ? Icon(icon ?? Icons.chevron_left_rounded, size: 22, color: AppColors.navy)
            : SafeImage(
                image!,
                width: size,
                height: size,
                fit: BoxFit.contain,
                fallback: Icon(
                  icon ?? Icons.chevron_left_rounded,
                  size: 22,
                  color: AppColors.navy,
                ),
              );

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(child: glyph),
          ),
        ),
      ),
    );
  }
}
