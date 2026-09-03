import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';

/// Which of the design's three button treatments to draw.
enum ButtonTone {
  /// Gold fill — every step that moves the flow forward.
  gold,

  /// Navy fill — the reading screens' primary action.
  navy,

  /// White fill, hairline outline — "Upload from gallery" beneath a navy button.
  outline,
}

/// The full-width action button at the foot of a sheet or screen.
///
/// A disabled button keeps its shape and fades: the design has no separate disabled style, so
/// opacity is the least surprising treatment.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.tone = ButtonTone.gold,
    this.icon,
    this.pill = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final ButtonTone tone;

  /// Drawn before the label — the camera on "Take a photo", the chat glyph on "Start Chat".
  final IconData? icon;

  /// Fully rounded instead of the standard corner radius.
  final bool pill;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final onDark = tone != ButtonTone.outline;
    final foreground = onDark ? Colors.white : AppColors.heading;
    final radius = pill ? AppShape.pill : AppShape.control;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: SizedBox(
        width: double.infinity,
        height: AppShape.buttonHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            // The gold is very slightly graded in the renders; flat colour for the rest.
            gradient: tone == ButtonTone.gold ? AppColors.goldFill : null,
            color: switch (tone) {
              ButtonTone.gold => null,
              ButtonTone.navy => AppColors.navy,
              ButtonTone.outline => AppColors.surface,
            },
            border: tone == ButtonTone.outline
                ? Border.all(color: AppColors.fieldBorder)
                : null,
            borderRadius: radius,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              child: Center(
                child: busy
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 20, color: foreground),
                            const SizedBox(width: 8),
                          ],
                          Text(label, style: AppText.button.copyWith(color: foreground)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A gold pill that hugs its label — the paywall's "Try Now" and the promo card's "Start Chat".
///
/// Separate from [PrimaryButton] rather than a flag on it, because this one must not stretch:
/// both live in a Row beside other content.
class GoldPillButton extends StatelessWidget {
  const GoldPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  /// Smaller padding, for the promo card where space is tighter.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: AppColors.goldFill,
          borderRadius: AppShape.pill,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: AppShape.pill,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 20 : 28,
                vertical: compact ? 12 : 15,
              ),
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 18, color: Colors.white),
                          const SizedBox(width: 8),
                        ],
                        Text(label, style: AppText.button),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
