import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/entitlement.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/primary_button.dart';
import 'cancellation_reason_viewmodel.dart';

/// "Why are you leaving?" — opened by the push sent minutes after a mandate is cancelled.
///
/// **Ungated.** A trial user who cancels loses access that same minute; behind `EntitlementGate`
/// this screen would bounce them to the paywall, which is precisely the person it exists to ask.
class CancellationReasonView extends ConsumerStatefulWidget {
  const CancellationReasonView({super.key, this.notificationId});

  final String? notificationId;

  @override
  ConsumerState<CancellationReasonView> createState() => _CancellationReasonViewState();
}

class _CancellationReasonViewState extends ConsumerState<CancellationReasonView> {
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = cancellationReasonViewModelProvider(widget.notificationId);
    final state = ref.watch(provider);
    final model = ref.read(provider.notifier);
    final entitled = ref.watch(entitlementProvider)?.entitled ?? false;

    return Scaffold(
      body: AstralBackground(
        surface: AstralSurface.onboarding,
        child: SafeArea(
          child: state.done ? _Thanks(entitled: entitled) : _Form(
                state: state,
                model: model,
                comment: _comment,
              ),
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.state, required this.model, required this.comment});

  final CancellationReasonState state;
  final CancellationReasonViewModel model;
  final TextEditingController comment;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppShape.gutter, 28, AppShape.gutter, 16),
            children: [
              const Center(child: BrandLogo(size: 40)),
              const SizedBox(height: 24),
              const AccentHeading(lead: 'Why are you', accent: 'leaving?'),
              const SizedBox(height: 10),
              Text(
                'Sorry to see you go. One tap tells us what to fix — it goes straight to the team.',
                style: AppText.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              for (final (key, label) in cancellationReasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ReasonTile(
                    label: label,
                    selected: state.reason == key,
                    onTap: state.busy ? null : () => model.choose(key),
                  ),
                ),
              if (state.reason != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppShape.control,
                    border: Border.all(color: AppColors.fieldBorder),
                  ),
                  child: TextField(
                    controller: comment,
                    onChanged: model.setComment,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 5,
                    style: AppText.body.copyWith(color: AppColors.navy),
                    cursorColor: AppColors.gold,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Anything else you want to tell us? (optional)',
                      hintStyle: AppText.body.copyWith(color: AppColors.muted),
                      counterStyle: AppText.legal,
                    ),
                  ),
                ),
              ],
              if (state.error != null) ...[
                const SizedBox(height: 12),
                Text(state.error!, style: AppText.meta.copyWith(color: AppColors.danger), textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppShape.gutter, 4, AppShape.gutter, 8),
          child: PrimaryButton(
            label: 'Send',
            analyticsId: 'cancellation_reason_send',
            tone: ButtonTone.navy,
            pill: true,
            busy: state.busy,
            onPressed: state.canSubmit ? model.submit : null,
          ),
        ),
        TextButton(
          onPressed: state.busy ? null : model.dismiss,
          child: Text('Skip', style: AppText.meta),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.goldWash : AppColors.surface,
        borderRadius: AppShape.control,
        child: InkWell(
          borderRadius: AppShape.control,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: AppShape.control,
              border: Border.all(color: selected ? AppColors.gold : AppColors.border, width: selected ? 1.4 : 1),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? AppColors.gold : AppColors.fieldBorder,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: AppText.title.copyWith(fontSize: 15))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thanks extends StatelessWidget {
  const _Thanks({required this.entitled});

  final bool entitled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppShape.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: BrandLogo(size: 48)),
          const SizedBox(height: 24),
          Text('Thank you 🙏', style: AppText.display, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            'Your answer helps us make Astrolok better. Your readings and your Kundali will be here if you come back.',
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          PrimaryButton(
            label: entitled ? 'Back to Home' : 'Resume my plan',
            analyticsId: entitled ? 'cancellation_home' : 'cancellation_resume',
            tone: ButtonTone.gold,
            pill: true,
            onPressed: () => context.go(entitled ? Routes.home : Routes.subscribe),
          ),
        ],
      ),
    );
  }
}
