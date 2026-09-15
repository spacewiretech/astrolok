import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import 'chat_copy.dart';

/// Five faces and an optional written answer, asked once per account, in the conversation that
/// first reaches five questions.
///
/// Lives in the composer rather than the transcript. The transcript is a reversed list pinned to
/// its bottom edge, so a row appearing there after a reply has been scrolled into view would push
/// that reply down under the reader's eyes — the one movement `_bringReplyIntoView` exists to get
/// right. Above the quick replies it takes room from the list without moving anything inside it.
///
/// Nothing is sent until Submit. Stateless: whether it is up, which face is picked, what has been
/// typed and whether it is saying thank you all belong to the composer. The card is taken off
/// screen while a turn is in flight, and a half-written comment has to be waiting when it returns.
class ChatRatingCard extends StatelessWidget {
  const ChatRatingCard({
    super.key,
    required this.thanked,
    required this.picked,
    required this.feedback,
    required this.onPick,
    required this.onSubmit,
    required this.onDismiss,
  });

  /// Showing the thank-you rather than the question.
  final bool thanked;

  /// The face chosen so far, 1 (worst) to 5 (best), or null before one is tapped.
  final int? picked;

  /// The written answer. Optional, and owned by the composer.
  final TextEditingController feedback;

  final ValueChanged<int> onPick;

  /// Sends the picked face and whatever was written. Only reachable once a face is picked.
  final VoidCallback onSubmit;

  /// "Not now": no score and no comment.
  final VoidCallback onDismiss;

  /// Worst to best. [ChatCopy.ratingLabels] names each one for a screen reader.
  static const faces = ['😞', '😕', '😐', '🙂', '😍'];

  /// Matches `chat_feedback.comment`'s check constraint and the server's own cap.
  static const maxCommentChars = 500;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(14, thanked ? 12 : 4, thanked ? 14 : 4, thanked ? 12 : 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
      ),
      child: thanked
          ? const _Thanks()
          : _Question(
              picked: picked,
              feedback: feedback,
              onPick: onPick,
              onSubmit: onSubmit,
              onDismiss: onDismiss,
            ),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({
    required this.picked,
    required this.feedback,
    required this.onPick,
    required this.onSubmit,
    required this.onDismiss,
  });

  final int? picked;
  final TextEditingController feedback;
  final ValueChanged<int> onPick;
  final VoidCallback onSubmit;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                ChatCopy.ratingPrompt,
                style: AppText.meta.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: ChatCopy.ratingDismiss,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
            ),
          ],
        ),
        Row(
          children: [
            for (final (index, face) in ChatRatingCard.faces.indexed)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: picked == index + 1,
                  label: ChatCopy.ratingLabels[index],
                  excludeSemantics: true,
                  child: InkResponse(
                    onTap: () => onPick(index + 1),
                    radius: 26,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Center(
                        child: _Face(
                          face: face,
                          picked: picked == index + 1,
                          // The others step back once one is chosen, so the choice reads at a glance.
                          faded: picked != null && picked != index + 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, right: 10),
          // One row, not the field above the button. The card sits over the composer and the
          // keyboard, and on a small phone a stacked Submit overflowed the screen by itself.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _FeedbackField(controller: feedback)),
              const SizedBox(width: 8),
              FilledButton(
                // A written answer with no score is not a rating, so the face comes first.
                onPressed: picked == null ? null : onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.border,
                  disabledForegroundColor: AppColors.muted,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  // The field's own height, so the two read as one control.
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: const RoundedRectangleBorder(borderRadius: AppShape.pill),
                  textStyle: AppText.meta.copyWith(fontWeight: FontWeight.w600),
                ),
                child: const Text(ChatCopy.ratingSubmit),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One face, with a gold ring once it is the chosen one.
class _Face extends StatelessWidget {
  const _Face({required this.face, required this.picked, required this.faded});

  final String face;
  final bool picked;
  final bool faded;

  static const _ease = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: _ease,
      opacity: faded ? 0.45 : 1,
      child: AnimatedContainer(
        duration: _ease,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: picked ? AppColors.goldWash : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: picked ? AppColors.gold : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Text(face, style: const TextStyle(fontSize: 28, height: 1.2)),
      ),
    );
  }
}

/// The optional written answer.
///
/// Never autofocused: the card appears on its own after a reply, and a keyboard springing up
/// unasked would cover the answer the user is still reading.
class _FeedbackField extends StatelessWidget {
  const _FeedbackField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: AppShape.control,
      borderSide: const BorderSide(color: AppColors.border),
    );

    return TextField(
      controller: controller,
      style: AppText.body,
      minLines: 1,
      // Grows for a few lines, then scrolls, so the card never pushes the composer off screen.
      maxLines: 3,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      inputFormatters: [LengthLimitingTextInputFormatter(ChatRatingCard.maxCommentChars)],
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.cardSoft,
        hintText: ChatCopy.feedbackHint,
        hintMaxLines: 1,
        hintStyle: AppText.body.copyWith(color: AppColors.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: const BorderSide(color: AppColors.gold)),
      ),
    );
  }
}

class _Thanks extends StatelessWidget {
  const _Thanks();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('🙏', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(child: Text(ChatCopy.ratingThanks, style: AppText.meta)),
      ],
    );
  }
}
