import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/models/upi_app.dart';
import '../../widgets/primary_button.dart';
import 'subscription_viewmodel.dart';

/// The paywall: one price, one button, one UPI app.
///
/// UNSKINNED: structure and behaviour are final, visuals are placeholders until the design
/// exports land.
class SubscriptionView extends ConsumerWidget {
  const SubscriptionView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(subscriptionViewModelProvider);
    final offer = state.offer;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppShape.gutter, vertical: 24),
          child: state.loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Text('Unlock your readings', style: AppText.display),
                    const SizedBox(height: 8),
                    if (offer != null)
                      Text(
                        state.trialAvailable
                            ? '${offer.trialPrice} for ${offer.trialDays} '
                                'day${offer.trialDays == 1 ? '' : 's'}, '
                                'then ${offer.planPrice}/month.'
                            : '${offer.planPrice}/month.',
                        style: AppText.price,
                      ),
                    const SizedBox(height: 24),

                    // The mandate consent line. UPI Autopay requires the recurring amount and
                    // cadence to be stated before authorisation, so this is a compliance
                    // requirement rather than marketing copy — it is not conditional.
                    if (offer != null) Text(offer.consent, style: AppText.meta),

                    const Spacer(),
                    if (state.upiApps.isNotEmpty) _UpiRow(state: state),
                    if (state.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        state.error!,
                        style: AppText.meta.copyWith(color: AppColors.danger),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    PrimaryButton(
                      label: state.selectedApp == null
                          ? 'Pay'
                          : 'Pay with ${state.selectedApp!.displayName}',
                      busy: state.busy,
                      onPressed: state.canSubscribe ? () => _subscribe(context, ref) : null,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _subscribe(BuildContext context, WidgetRef ref) async {
    final outcome = await ref.read(subscriptionViewModelProvider.notifier).subscribe();
    // Null means the tap was ignored because one was already in flight — not an outcome, and
    // routing on it would throw a status screen over a payment that is still running.
    if (!context.mounted || outcome == null) return;
    context.go(Routes.paymentStatusFor(outcome));
  }
}

/// The chosen UPI app, with a way to change it.
class _UpiRow extends ConsumerWidget {
  const _UpiRow({required this.state});

  final SubscriptionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = state.selectedApp;

    return Row(
      children: [
        Expanded(
          child: Text(
            selected == null ? 'Choose a UPI app' : 'Paying with ${selected.displayName}',
            style: AppText.meta,
          ),
        ),
        TextButton(
          onPressed: state.busy ? null : () => _pick(context, ref),
          child: Text('Change', style: AppText.meta.copyWith(color: AppColors.brand)),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final chosen = await showModalBottomSheet<UpiApp>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppShape.sheetRadius)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final app in state.upiApps)
              ListTile(
                // The icon arrives as base64 from the SDK and is routinely missing, so the
                // tile has to read correctly without one.
                leading: app.icon == null
                    ? const Icon(Icons.account_balance_wallet_outlined)
                    : Image.memory(app.icon!, width: 32, height: 32),
                title: Text(app.displayName, style: AppText.title),
                trailing: app.id == state.selectedAppId
                    ? const Icon(Icons.check, color: AppColors.brand)
                    : null,
                onTap: () => Navigator.of(context).pop(app),
              ),
          ],
        ),
      ),
    );

    if (chosen != null) {
      ref.read(subscriptionViewModelProvider.notifier).selectApp(chosen.id);
    }
  }
}
