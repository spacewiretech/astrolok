import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/models/astro_message.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/primary_button.dart';
import '../chat/chat_copy.dart';
import 'memory_viewmodel.dart';

/// Everything Astro has learned about the user, and the means to take it back.
///
/// This screen exists because the alternative — remembering silently — is the version that
/// cannot be defended. These are things somebody told an astrologer about their life, and being
/// able to see them and remove them is the difference between a memory and a dossier.
class MemoryView extends ConsumerWidget {
  const MemoryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(memoryViewModelProvider);
    final model = ref.read(memoryViewModelProvider.notifier);

    ref.listen(memoryViewModelProvider.select((s) => s.error), (_, error) {
      if (error == null) return;
      showAppSnackBar(context, error, error: true);
      model.errorShown();
    });

    return Scaffold(
      body: AstralBackground(
        surface: AstralSurface.home,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppShape.gutter, 4, AppShape.gutter, 0),
                child: Row(
                  children: [
                    CircleIconButton(
                      image: PalmIcon.backCircle,
                      icon: Icons.chevron_left_rounded,
                      semanticLabel: 'Back',
                      onTap: () =>
                          context.canPop() ? context.pop() : context.go(Routes.profile),
                    ),
                    Expanded(
                      child: Text(
                        ChatCopy.memoryHeading,
                        style: AppText.section,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: AppShape.avatar),
                  ],
                ),
              ),

              Expanded(
                child: state.loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.gold),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppShape.gutter,
                          16,
                          AppShape.gutter,
                          32,
                        ),
                        children: [
                          Text(
                            ChatCopy.memorySubtitle,
                            style: AppText.meta,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 22),

                          if (state.facts.isEmpty)
                            _Empty()
                          else ...[
                            for (final fact in state.facts) ...[
                              _FactCard(
                                fact: fact,
                                enabled: !state.busy,
                                onForget: () => model.forget(key: fact.key),
                              ),
                              const SizedBox(height: 10),
                            ],
                            const SizedBox(height: 18),
                            PrimaryButton(
                              label: ChatCopy.forgetAll,
                              tone: ButtonTone.outline,
                              onPressed: state.busy
                                  ? null
                                  : () => _confirmForgetAll(context, model),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Confirmed, because it cannot be undone and the user cannot see what they are about to lose
  /// once it is gone.
  Future<void> _confirmForgetAll(BuildContext context, MemoryViewModel model) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppShape.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ChatCopy.forgetAllTitle, style: AppText.sheetTitle),
              const SizedBox(height: 10),
              Text(
                ChatCopy.forgetAllBody,
                style: AppText.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              PrimaryButton(
                label: ChatCopy.forgetAllDismiss,
                tone: ButtonTone.navy,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: ChatCopy.forgetAllConfirm,
                tone: ButtonTone.outline,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed ?? false) await model.forget();
  }
}

/// One fact, with its own way out.
class _FactCard extends StatelessWidget {
  const _FactCard({
    required this.fact,
    required this.enabled,
    required this.onForget,
  });

  final AstroFact fact;
  final bool enabled;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The de-slugged key — "Works as" — rather than the raw `works_as`. The keys are
                // invented by the model, so there is no table to translate them with; de-slugging
                // is the only thing that generalises.
                Text(
                  fact.label,
                  style: AppText.meta.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 2),
                Text(fact.value, style: AppText.body),
              ],
            ),
          ),
          IconButton(
            onPressed: enabled ? onForget : null,
            icon: const Icon(Icons.close_rounded, size: 20),
            color: AppColors.muted,
            tooltip: 'Forget this',
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.auto_awesome_outlined, size: 44, color: AppColors.gold),
          const SizedBox(height: 16),
          Text(
            ChatCopy.memoryEmpty,
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
