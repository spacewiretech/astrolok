import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chat_bubble.dart';
import 'chat_copy.dart';
import 'chat_palette.dart';

/// Astro, typing: three dots bouncing in one of Astro's own bubbles, as WhatsApp shows it.
///
/// Shown from the moment the question is read until the reply's first message, and in the pause
/// before each later one, alongside "typing…" in the bar at the top. The wait reads as someone
/// writing back, which is what it is.
class ChatTypingBubble extends StatefulWidget {
  const ChatTypingBubble({super.key, this.tail = true});

  /// Pointed, when it opens a run; flat, when it follows a message Astro has just sent.
  final bool tail;

  @override
  State<ChatTypingBubble> createState() => _ChatTypingBubbleState();
}

class _ChatTypingBubbleState extends State<ChatTypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion keeps the conversation's rhythm — the pauses are timing, not animation — but
    // the dots hold still.
    if (MediaQuery.disableAnimationsOf(context)) {
      _beat
        ..stop()
        ..value = 0;
    } else if (!_beat.isAnimating) {
      _beat.repeat();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: ChatCopy.typingLabel,
      liveRegion: true,
      child: Align(
        alignment: Alignment.centerLeft,
        child: CustomPaint(
          painter: ChatBubbleShape(
            color: ChatPalette.incoming,
            outgoing: false,
            tail: widget.tail,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(ChatBubbleShape.tailWidth + 14, 13, 14, 13),
            child: AnimatedBuilder(
              animation: _beat,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Transform.translate(
                      // Each dot a third of a beat behind the last, rising and settling.
                      offset: Offset(
                        0,
                        -3 * math.max(0, math.sin((_beat.value - i / 6) * 2 * math.pi)),
                      ),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: ChatPalette.meta,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
