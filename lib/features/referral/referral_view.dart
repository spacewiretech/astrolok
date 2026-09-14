import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/primary_button.dart';
import 'referral_state.dart';
import 'referral_viewmodel.dart';

/// Invite friends: the user's own code, and the two ways to pass it on.
class ReferralView extends ConsumerStatefulWidget {
  const ReferralView({super.key});

  @override
  ConsumerState<ReferralView> createState() => _ReferralViewState();
}

class _ReferralViewState extends ConsumerState<ReferralView> {
  @override
  void initState() {
    super.initState();
    analytics.track(Ev.inviteScreenViewed);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(referralViewModelProvider);
    final model = ref.read(referralViewModelProvider.notifier);

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
                        'Invite friends',
                        style: AppText.section,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // Balances the back button so the title stays optically centred.
                    const SizedBox(width: 44),
                  ],
                ),
              ),
              Expanded(
                child: state.loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : _Body(state: state, model: model),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.model});

  final ReferralState state;
  final ReferralViewModel model;

  @override
  Widget build(BuildContext context) {
    final code = state.code;

    if (code == null) {
      return Padding(
        padding: const EdgeInsets.all(AppShape.gutter),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              state.error ?? 'Invites are not available right now.',
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Try again', onPressed: model.load),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppShape.gutter, 8, AppShape.gutter, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Share your invite',
            style: AppText.title,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Send this link to a friend. When they join Astrolok and start their trial, '
            'we will know they came from you.',
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          _CodeChip(code: code.code, copied: state.justCopied, onTap: model.copy),
          const SizedBox(height: 24),
          PrimaryButton(label: 'Share invite', onPressed: model.share),
          const SizedBox(height: 12),
          TextButton(
            onPressed: model.copy,
            child: Text(
              state.justCopied ? 'Link copied' : 'Copy link',
              style: AppText.button.copyWith(color: AppColors.goldDeep),
            ),
          ),
          const SizedBox(height: 28),
          // Two numbers rather than one: the gap between them is the whole story of whether
          // invites are working. Plenty of joins and no trials is a different problem entirely
          // from nobody joining.
          Row(
            children: [
              Expanded(child: _Stat(value: code.invited, label: 'Joined')),
              const SizedBox(width: 12),
              Expanded(child: _Stat(value: code.converted, label: 'Started a trial')),
            ],
          ),
        ],
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code, required this.copied, required this.onTap});

  final String code;
  final bool copied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.goldWash,
          borderRadius: BorderRadius.circular(AppShape.cardRadius),
          border: Border.all(color: AppColors.gold),
        ),
        child: Column(
          children: [
            Text(
              code,
              // Spaced out because this is a string people read aloud and type by hand. The
              // alphabet already excludes I, L, O and U for the same reason.
              style: AppText.display.copyWith(letterSpacing: 6, fontSize: 28),
            ),
            const SizedBox(height: 4),
            Text(
              copied ? 'Copied' : 'Tap to copy your link',
              style: AppText.meta.copyWith(
                color: copied ? AppColors.success : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppShape.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text('$value', style: AppText.title),
          const SizedBox(height: 2),
          Text(label, style: AppText.meta, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
