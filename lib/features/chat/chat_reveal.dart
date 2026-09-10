import 'package:flutter/material.dart';

/// Drives one reply's entrance: the answer types itself out, then the reasoning arrives under it.
///
/// The transport is not streaming — the whole reply lands in one response — so this is a staged
/// reveal rather than a live feed. It is doing two things worth the code. It puts the answer on
/// screen alone for a beat, which is what makes "answer first" land as an experience rather than
/// as a layout decision. And it gives a two-second gap between the reply arriving and the whole
/// screen being full of text, which is the difference between reading a reply and being handed
/// one.
///
/// One controller with [Interval]s rather than a controller per part: a long reply has up to five
/// pieces, and five tickers per bubble in a scrolling list is how a chat screen starts dropping
/// frames on the phones this app is actually used on.
class ChatReveal extends StatefulWidget {
  const ChatReveal({
    super.key,
    required this.active,
    required this.verdict,
    required this.builder,
    this.onFinished,
    this.onEntered,
  });

  /// False for everything already on screen — history, the cache, anything the list recycled.
  ///
  /// Only the one reply that just arrived animates. Without this the transcript, which is a
  /// `ListView.builder`, would replay a bubble's entrance every time it scrolled back into view.
  final bool active;

  /// The text that types out. Its length sets how long the whole sequence takes.
  final String verdict;

  /// Given how much of the verdict to show, and how far through the staged part the rest is.
  final Widget Function(BuildContext context, String verdict, double progress) builder;

  /// Called once, when the sequence finishes, so the caller can stop marking this reply as the
  /// one being revealed.
  final VoidCallback? onFinished;

  /// Called once, on the first frame this reply exists, with the bubble's own context.
  ///
  /// The transcript is a reversed list pinned to the bottom, and [RevealedPart] fades rather
  /// than grows — so a reply is laid out at its full height immediately and a long one puts its
  /// verdict above the top of the screen, leaving the reader looking at the blank part of a card
  /// that is still filling in. The caller uses this context to scroll the top of the bubble into
  /// view. Only fires when [active]; history is already where the reader left it.
  final void Function(BuildContext context)? onEntered;

  @override
  State<ChatReveal> createState() => _ChatRevealState();
}

class _ChatRevealState extends State<ChatReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Roughly a brisk reading pace. Slower reads as a gimmick; faster is not perceptibly typing.
  static const _msPerChar = 26;

  /// A verdict is capped at 25 words server-side, but a model that ignores that must not be able
  /// to hold the screen hostage for ten seconds.
  static const _maxTypingMs = 2200;

  /// How long the explanation and sections take to arrive after the answer has finished.
  static const _stagedMs = 620;

  late final int _typingMs;

  /// Where typing ends and the staged fade begins, as a fraction of the whole.
  late final double _split;

  @override
  void initState() {
    super.initState();

    _typingMs = widget.verdict.isEmpty
        ? 0
        : (widget.verdict.length * _msPerChar).clamp(0, _maxTypingMs);

    final total = _typingMs + _stagedMs;
    _split = total == 0 ? 0 : _typingMs / total;

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    );

    if (widget.active) {
      // After the first layout, or there is no render box to measure yet. Once per reply: the
      // bubble is keyed by message id, so this State is built exactly once for each one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onEntered?.call(context);
      });

      _controller.forward().then((_) {
        if (mounted) widget.onFinished?.call();
      });
    } else {
      // Everything already on screen starts finished. Not `forward()` from 1, which would still
      // schedule a frame.
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Skips to the end. A reply someone has already read should not make them wait for it.
  void _complete() {
    if (_controller.isCompleted) return;
    _controller.value = 1;
    widget.onFinished?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Opaque so a tap anywhere on the bubble lands, including the gaps between its lines.
      behavior: HitTestBehavior.opaque,
      onTap: _controller.isCompleted ? null : _complete,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final value = _controller.value;

          final typed = _typingMs == 0
              ? widget.verdict
              : widget.verdict.substring(
                  0,
                  ((value / _split).clamp(0.0, 1.0) * widget.verdict.length).round(),
                );

          // 0 until the answer has finished typing, then 0 to 1 across the rest.
          final progress = _split >= 1
              ? (value >= 1 ? 1.0 : 0.0)
              : ((value - _split) / (1 - _split)).clamp(0.0, 1.0);

          return widget.builder(context, typed, progress);
        },
      ),
    );
  }
}

/// One piece of the explanation, fading and rising into place at its own moment.
///
/// [index] staggers it: the opening arrives first, then each section behind it. Reads as a reply
/// being set down a line at a time rather than pasted in whole.
class RevealedPart extends StatelessWidget {
  const RevealedPart({
    super.key,
    required this.progress,
    required this.index,
    required this.child,
  });

  /// 0 to 1 across the staged part of the sequence.
  final double progress;

  final int index;
  final Widget child;

  /// How much of the staged window each part waits through before starting. Small enough that a
  /// three-section reply still finishes inside the window rather than being cut off by it.
  static const _stagger = 0.16;

  @override
  Widget build(BuildContext context) {
    final start = (index * _stagger).clamp(0.0, 0.8);
    final t = ((progress - start) / (1 - start)).clamp(0.0, 1.0);
    final eased = Curves.easeOut.transform(t);

    return Opacity(
      opacity: eased,
      child: Transform.translate(
        // Rises the last few pixels into place. Small on purpose: a bigger travel makes a long
        // reply look like it is being shaken onto the screen.
        offset: Offset(0, 8 * (1 - eased)),
        child: child,
      ),
    );
  }
}
