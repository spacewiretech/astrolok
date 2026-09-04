import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';

/// The listen control, on every reading screen.
///
/// Only ever built when the device actually has a speech engine — `ReadingSpeech.prepare()`
/// answers that, and the screens leave this out entirely when the answer is no. A control that
/// does nothing reads as a bug; an absent one reads as a design.
///
/// While speaking it shows three bars rising and falling. That is doing real work: on-device
/// TTS gives no progress callback worth binding a bar to, and without *some* sign of life a
/// forty-second narration looks identical to a button that did not respond. The animation is
/// honest about what it claims — it says "this is playing", not "you are 40% through".
class SpeakButton extends StatefulWidget {
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
  State<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<SpeakButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bars = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.speaking) _bars.repeat();
  }

  @override
  void didUpdateWidget(SpeakButton old) {
    super.didUpdateWidget(old);
    if (widget.speaking && !_bars.isAnimating) {
      _bars.repeat();
    } else if (!widget.speaking && _bars.isAnimating) {
      _bars.stop();
      _bars.value = 0;
    }
  }

  @override
  void dispose() {
    _bars.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speaking = widget.speaking;

    return Align(
      alignment: widget.alignment,
      child: Semantics(
        button: true,
        label: speaking ? widget.stopLabel : widget.listenLabel,
        excludeSemantics: true,
        child: Material(
          color: speaking ? widget.color : widget.color.withValues(alpha: 0.12),
          borderRadius: AppShape.pill,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (speaking)
                    _Equaliser(animation: _bars)
                  else
                    Icon(Icons.volume_up_rounded, size: 18, color: widget.color),
                  const SizedBox(width: 9),
                  Text(
                    speaking ? widget.stopLabel : widget.listenLabel,
                    style: AppText.title.copyWith(
                      fontSize: 14,
                      color: speaking ? Colors.white : widget.color,
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

/// Three bars, out of phase, so the group reads as sound rather than as a loading spinner.
class _Equaliser extends StatelessWidget {
  const _Equaliser({required this.animation});

  final Animation<double> animation;

  static const _phases = [0.0, 0.33, 0.66];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 16,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final phase in _phases)
              Container(
                width: 3.5,
                // A sine off a shared clock: cheap, and the three never line up.
                height: 5 +
                    9 *
                        (0.5 +
                            0.5 *
                                math.sin(
                                  (animation.value + phase) * 2 * math.pi,
                                )),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
