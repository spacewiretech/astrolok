import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';
import 'audio_bars.dart';

/// The listen control, on every reading screen.
///
/// Only ever built when the device actually has a speech engine — `ReadingSpeech.prepare()`
/// answers that, and the screens leave this out entirely when the answer is no. A control that
/// does nothing reads as a bug; an absent one reads as a design.
///
/// While speaking it shows [AudioBars] — three bars rising and falling — which is what tells the
/// user a forty-second narration is running rather than a button having failed to respond.
class SpeakButton extends StatelessWidget {
  const SpeakButton({
    super.key,
    required this.speaking,
    required this.onTap,
    required this.listenLabel,
    required this.stopLabel,
    this.color = AppColors.gold,
    this.alignment = Alignment.centerLeft,
  });

  final bool speaking;
  final VoidCallback onTap;

  final String listenLabel;
  final String stopLabel;

  /// The accent. Defaults to gold; a feature detail screen passes its own so the control sits
  /// inside that page's palette rather than beside it.
  final Color color;

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Semantics(
        button: true,
        label: speaking ? stopLabel : listenLabel,
        excludeSemantics: true,
        child: Material(
          color: speaking ? color : color.withValues(alpha: 0.12),
          borderRadius: AppShape.pill,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (speaking)
                    // White, because the pill fills with the accent while it plays.
                    const AudioBars(speaking: true, color: Colors.white)
                  else
                    Icon(Icons.volume_up_rounded, size: 18, color: color),
                  const SizedBox(width: 9),
                  Text(
                    speaking ? stopLabel : listenLabel,
                    style: AppText.title.copyWith(
                      fontSize: 14,
                      color: speaking ? Colors.white : color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
