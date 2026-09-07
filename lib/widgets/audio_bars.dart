import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Three bars rising and falling, for anything that is currently speaking.
///
/// This is doing real work rather than decorating: on-device TTS gives no progress callback worth
/// binding a bar to, and without *some* sign of life a forty-second narration looks identical to
/// a button that did not respond. The animation is honest about what it claims — it says "this is
/// playing", not "you are 40% through".
///
/// It owns its own clock, starting and stopping with [speaking], so a caller only has to say
/// whether sound is coming out. Shared by the reading screens' [SpeakButton] and the chat's
/// per-reply listen control, so the two cannot drift into looking like different things doing the
/// same job.
class AudioBars extends StatefulWidget {
  const AudioBars({
    super.key,
    required this.speaking,
    required this.color,
    this.size = 16,
  });

  final bool speaking;

  final Color color;

  /// Height of the tallest bar. Width follows from it, so one number sizes the whole group.
  final double size;

  @override
  State<AudioBars> createState() => _AudioBarsState();
}

class _AudioBarsState extends State<AudioBars> with SingleTickerProviderStateMixin {
  late final AnimationController _bars = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// A third of a cycle apart, so the three never line up and the group never reads as a bar
  /// chart or a progress indicator.
  static const _phases = [0.0, 0.33, 0.66];

  @override
  void initState() {
    super.initState();
    if (widget.speaking) _bars.repeat();
  }

  @override
  void didUpdateWidget(AudioBars old) {
    super.didUpdateWidget(old);

    if (widget.speaking && !_bars.isAnimating) {
      _bars.repeat();
    } else if (!widget.speaking && _bars.isAnimating) {
      // Stopped and reset rather than left where it stopped, so the next play starts from the
      // same place every time instead of wherever the last one happened to end.
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
    final width = widget.size * 1.125;
    final bar = math.max(2.0, widget.size * 0.22);
    final floor = widget.size * 0.3;
    final swing = widget.size - floor;

    return SizedBox(
      width: width,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _bars,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final phase in _phases)
              Container(
                width: bar,
                // A sine off a shared clock: cheap, and the three never line up.
                height: floor +
                    swing *
                        (0.5 + 0.5 * math.sin((_bars.value + phase) * 2 * math.pi)),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
