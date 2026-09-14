import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import 'chat_copy.dart';

/// Five faces, asked once per account, in the conversation that first reaches five questions.
///
/// Lives in the composer rather than the transcript. The transcript is a reversed list pinned to
/// its bottom edge, so a row appearing there after a reply has been scrolled into view would push
/// that reply down under the reader's eyes — the one movement `_bringReplyIntoView` exists to get
/// right. Above the quick replies it takes room from the list without moving anything inside it.
///
/// Stateless: whether it is up, and whether it is saying thank you, belongs to the composer.
class ChatRatingCard extends StatelessWidget {
  const ChatRatingCard({super.key, required this.thanked, required this.onRate});

  /// Showing the thank-you rather than the question.
  final bool thanked;

  /// 1 (worst) to 5 (best), or null for a dismissal.
  final ValueChanged<int?> onRate;

  /// Worst to best. [ChatCopy.ratingLabels] names each one for a screen reader.
  static const faces = ['😞', '😕', '😐', '🙂', '😍'];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(14, thanked ? 12 : 4, thanked ? 14 : 4, thanked ? 12 : 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
      ),
      child: thanked ? const _Thanks() : _Question(onRate: onRate),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({required this.onRate});

  final ValueChanged<int?> onRate;

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
              onPressed: () => onRate(null),
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
                  label: ChatCopy.ratingLabels[index],
                  excludeSemantics: true,
                  child: InkResponse(
                    onTap: () => onRate(index + 1),
                    radius: 26,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Center(
                        child: Text(face, style: const TextStyle(fontSize: 28, height: 1.2)),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
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
