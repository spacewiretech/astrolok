import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_typography.dart';
import '../../data/models/astro_message.dart';
import 'chat_bubble.dart';
import 'chat_copy.dart';
import 'chat_greeting.dart';
import 'chat_palette.dart';
import 'chat_rating.dart';
import 'chat_state.dart';

/// Everything pinned below the conversation: the rating card, and WhatsApp's message field with
/// its round green send button.
///
/// The quick replies are no longer here: they sit under Astro's newest message, as WhatsApp's
/// reply buttons do, so a suggestion is read beside the message it follows. See `ChatView`.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.state,
    required this.greeting,
    required this.onSend,
    required this.onDraftRestored,
    required this.onRate,
    this.focus,
  });

  final ChatState state;

  /// The chat language's words for the hints below.
  final ChatGreeting greeting;

  /// The field's focus, when the screen needs to put the cursor there itself. Owned by whoever
  /// passes it; one is made here otherwise.
  final FocusNode? focus;

  /// The second argument names the affordance the message came from: `composer` here.
  final void Function(String message, String entry) onSend;

  /// Told once the returned draft has been put back in the field, so it is not restored again on
  /// the next rebuild.
  final VoidCallback onDraftRestored;

  /// The rating card was answered: a score of 1 (worst) to 5 (best) with whatever was written
  /// beside it, or null and null for a dismissal.
  final void Function(int? rating, String? comment) onRate;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focus ?? (_ownFocus ??= FocusNode());

  /// How long the thank-you stays before the card folds away.
  static const _thanksFor = Duration(milliseconds: 1600);

  /// True while the card is saying thank you. Held here rather than in [ChatState], because the
  /// answer has already gone to the server by then and nothing else needs to know.
  bool _thanked = false;
  Timer? _thanks;

  /// The face picked on the rating card and the words written beside it, before Submit — held
  /// here, because the card is taken off screen whenever a turn is in flight.
  int? _picked;
  final _feedback = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The send button lights up the moment there is something to send, as WhatsApp's does.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(ChatComposer old) {
    super.didUpdateWidget(old);

    // A turn that failed hands its words back. Someone who has just written three sentences to
    // an astrologer should not have to write them again because the network blinked.
    final pending = widget.state.pending;
    if (pending != null && pending.isNotEmpty && _controller.text.isEmpty) {
      // The whole value, with the caret after the text, which is where someone about to keep
      // writing expects it.
      _controller.value = TextEditingValue(
        text: pending,
        selection: TextSelection.collapsed(offset: pending.length),
      );
      // After the frame: this runs while the tree is building, and clearing `pending` then is a
      // provider write mid-build, which Riverpod rejects.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDraftRestored();
      });
    }
  }

  @override
  void dispose() {
    _thanks?.cancel();
    _controller.dispose();
    _feedback.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _send() {
    final message = _controller.text.trim();
    if (message.isEmpty || !widget.state.canSend) return;

    _controller.clear();
    widget.onSend(message, 'composer');
  }

  void _submitRating() {
    final picked = _picked;
    if (picked == null) return;

    widget.onRate(picked, _feedback.text);
    _feedback.clear();
    setState(() {
      _picked = null;
      _thanked = true;
    });
    _thanks?.cancel();
    _thanks = Timer(_thanksFor, () {
      if (mounted) setState(() => _thanked = false);
    });
  }

  /// "Not now". Not thanked for: the card simply goes, and anything half-written goes with it.
  void _dismissRating() {
    widget.onRate(null, null);
    _feedback.clear();
    setState(() => _picked = null);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final hint = switch (state.askFor) {
      AskFor.dob => widget.greeting.dobHint,
      AskFor.birthTime => widget.greeting.timeHint,
      AskFor.birthPlace => widget.greeting.placeHint,
      AskFor.none => widget.greeting.placeholder,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sized rather than switched, so the card folds away instead of the field jumping.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: state.showRating || _thanked
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: ChatRatingCard(
                      thanked: _thanked,
                      picked: _picked,
                      feedback: _feedback,
                      onPick: (rating) => setState(() => _picked = rating),
                      onSubmit: _submitRating,
                      onDismiss: _dismissRating,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (state.exhausted)
            const _Exhausted()
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _Field(
                    controller: _controller,
                    focus: _focus,
                    enabled: state.canSend,
                    hint: hint,
                    onSubmit: _send,
                  ),
                ),
                const SizedBox(width: 6),
                _SendButton(
                  enabled: state.canSend && _controller.text.trim().isNotEmpty,
                  onTap: _send,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// WhatsApp's field: a white pill that grows for a long message, then scrolls.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.focus,
    required this.enabled,
    required this.hint,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
  final String hint;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(18, 2, 12, 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: ChatPalette.shadow, blurRadius: 1, offset: Offset(0, 1))],
      ),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: controller,
        focusNode: focus,
        enabled: enabled,
        style: chatTextStyle().copyWith(fontSize: 16),
        minLines: 1,
        // A composer that expands without limit eats the conversation it belongs to.
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => onSubmit(),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          hintText: hint,
          hintStyle: chatTextStyle().copyWith(fontSize: 16, color: ChatPalette.meta),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: ChatCopy.send,
      excludeSemantics: true,
      child: Material(
        color: ChatPalette.send.withValues(alpha: enabled ? 1 : 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Shown in the field's place once the day's questions are spent — with a helpline, because the
/// field is gone and someone who needs to reach out must still find a number.
class _Exhausted extends StatelessWidget {
  const _Exhausted();

  @override
  Widget build(BuildContext context) {
    final meta = AppText.body.copyWith(fontSize: 13.5, height: 1.35, color: ChatPalette.onChip);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: ChatPalette.chip,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: ChatPalette.shadow, blurRadius: 1, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_bottom_rounded, size: 18, color: ChatPalette.meta),
              const SizedBox(width: 8),
              Expanded(child: Text(ChatCopy.exhausted, style: meta.copyWith(color: ChatPalette.text))),
            ],
          ),
          const SizedBox(height: 6),
          Text(ChatCopy.exhaustedHelpline, style: meta),
        ],
      ),
    );
  }
}
