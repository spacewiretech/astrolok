import 'package:flutter/material.dart';

import '../../app/assets.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/models/astro_message.dart';
import '../../widgets/safe_asset.dart';
import 'chat_copy.dart';
import 'chat_state.dart';

/// Everything pinned below the transcript: the quick replies, whatever the sage asked for, and
/// the field itself.
///
/// One widget rather than three, because they are one region as far as the user is concerned and
/// they share a single rule — when a turn is in flight or the day's questions are gone, none of
/// them accepts input.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.state,
    required this.onSend,
    required this.onDraftRestored,
  });

  final ChatState state;
  /// The second argument names the affordance the message came from — `composer`, `quick_reply`
  /// or `birth_time`. Only this widget knows which, and the three are very different levels of
  /// intent: a tapped suggestion is nearly free, a typed sentence is not.
  final void Function(String message, String entry) onSend;

  /// Told once the returned draft has been put back in the field, so it is not restored again on
  /// the next rebuild.
  final VoidCallback onDraftRestored;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void didUpdateWidget(ChatComposer old) {
    super.didUpdateWidget(old);

    // A turn that failed hands its words back. Someone who has just written three sentences to
    // an astrologer should not have to write them again because the network blinked.
    final pending = widget.state.pending;
    if (pending != null && pending.isNotEmpty && _controller.text.isEmpty) {
      _controller.text = pending;
      widget.onDraftRestored();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send([String? override, String entry = 'composer']) {
    final message = (override ?? _controller.text).trim();
    if (message.isEmpty || !widget.state.canSend) return;

    _controller.clear();
    widget.onSend(message, entry);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: ChatCopy.birthTimePrompt,
    );
    if (picked == null || !mounted) return;

    // Sent as ordinary words rather than as a form value: it becomes a turn in the transcript,
    // and "07:30" sitting in a navy bubble would read as a machine talking. The server picks
    // the time back out of the sentence.
    final hour = picked.hour.toString().padLeft(2, '0');
    final minute = picked.minute.toString().padLeft(2, '0');
    _send('I was born at $hour:$minute.', 'birth_time');
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return Padding(
      padding: EdgeInsets.only(
        left: AppShape.gutter,
        right: AppShape.gutter,
        bottom: 12,
        // Lifts the field clear of the keyboard without a Scaffold resize, which would fight
        // the reversed list above.
        top: 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.askFor == AskFor.birthTime) ...[
            _TimeRequest(
              onPick: _pickTime,
              onUnknown: () => _send(ChatCopy.birthTimeUnknown, 'birth_time'),
            ),
            const SizedBox(height: 10),
          ],

          if (state.options.isNotEmpty) ...[
            _QuickReplies(
              options: state.options,
              onPick: (option, index) {
                analytics.track(Ev.chatQuickReplyTapped, {
                  P.optionIndex: index,
                  P.label: option,
                  P.optionCount: state.options.length,
                });
                _send(option, 'quick_reply');
              },
            ),
            const SizedBox(height: 10),
          ],

          if (state.exhausted)
            const _Exhausted()
          else
            _Field(
              controller: _controller,
              focus: _focus,
              enabled: state.canSend,
              hint: state.askFor == AskFor.birthPlace
                  ? ChatCopy.birthPlaceHint
                  : ChatCopy.placeholder,
              onSubmit: _send,
            ),
        ],
      ),
    );
  }
}

/// The tappable answers under the newest reply.
class _QuickReplies extends StatelessWidget {
  const _QuickReplies({required this.options, required this.onPick});

  final List<String> options;
  final void Function(String option, int index) onPick;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (index, option) in options.indexed)
            Material(
              color: AppColors.goldWash,
              borderRadius: AppShape.pill,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onPick(option, index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    option,
                    style: AppText.meta.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Raised when the sage has asked for the hour of birth.
///
/// A real picker rather than trusting free text: the birth time decides the nakshatra, and
/// "half seven-ish" is not something worth guessing a chart from.
class _TimeRequest extends StatelessWidget {
  const _TimeRequest({required this.onPick, required this.onUnknown});

  final VoidCallback onPick;
  final VoidCallback onUnknown;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.schedule_rounded, size: 18),
            label: Text(ChatCopy.birthTimeAction, style: AppText.meta),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.navy,
              side: const BorderSide(color: AppColors.fieldBorder),
              shape: const RoundedRectangleBorder(borderRadius: AppShape.pill),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Not knowing is a real answer, and the sage is told to read on without it. Without this
        // the only way past the question is to invent one.
        TextButton(
          onPressed: onUnknown,
          child: Text(
            ChatCopy.birthTimeUnknown,
            style: AppText.meta.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}

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
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.pill,
        border: Border.all(color: AppColors.border),
        boxShadow: const [AppColors.floatingShadow],
      ),
      child: Row(
        children: [
          SafeImage(
            ChatIcon.spark,
            width: 18,
            height: 18,
            fit: BoxFit.contain,
            fallback: const Icon(Icons.auto_awesome, size: 18, color: AppColors.gold),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              enabled: enabled,
              style: AppText.body,
              minLines: 1,
              // Grows for a long question, then scrolls. A composer that expands without limit
              // eats the conversation it belongs to.
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: AppText.body.copyWith(color: AppColors.muted),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(enabled: enabled, onTap: onSubmit),
        ],
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
      label: ChatCopy.send,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: SafeImage(
            ChatIcon.send,
            width: 44,
            height: 44,
            fit: BoxFit.contain,
            fallback: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.navy,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                size: 20,
                color: AppColors.gold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown in the field's place once the day's questions are spent.
///
/// The field closes rather than staying open and refusing: there is nothing to retry, and an
/// input that swallows what you type is worse than one that is honestly absent.
class _Exhausted extends StatelessWidget {
  const _Exhausted();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSoft,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_bottom_rounded, size: 20, color: AppColors.gold),
          const SizedBox(width: 10),
          Expanded(child: Text(ChatCopy.exhausted, style: AppText.meta)),
        ],
      ),
    );
  }
}
