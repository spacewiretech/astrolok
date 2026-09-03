import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/entitlement.dart';
import '../../data/providers.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/primary_button.dart';
import 'payment_outcome.dart';

/// How the checkout ended, and what to do about it.
///
/// The [PaymentOutcome.pending] case keeps asking the server rather than presenting a verdict:
/// the money may well have moved and the webhook simply has not landed yet, so this screen is
/// the difference between a late confirmation and telling a paying user they did not pay.
///
/// UNSKINNED: structure and behaviour are final, visuals are placeholders until the design
/// exports land.
class PaymentStatusView extends ConsumerStatefulWidget {
  const PaymentStatusView({super.key, required this.outcome});

  final PaymentOutcome outcome;

  @override
  ConsumerState<PaymentStatusView> createState() => _PaymentStatusViewState();
}

class _PaymentStatusViewState extends ConsumerState<PaymentStatusView> {
  /// Slower and longer than the paywall's poll: by the time a user is on this screen the fast
  /// path has already been tried, and what is left is waiting on a webhook.
  static const _pendingDelay = Duration(seconds: 5);
  static const _pendingAttempts = 12;

  bool _polling = false;

  @override
  void initState() {
    super.initState();
    if (widget.outcome == PaymentOutcome.pending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pollUntilEntitled());
    }
  }

  Future<void> _pollUntilEntitled() async {
    if (_polling) return;
    _polling = true;

    for (var i = 0; i < _pendingAttempts; i++) {
      await Future<void>.delayed(_pendingDelay);
      if (!mounted) return;

      try {
        final user = await ref.read(subscriptionRepositoryProvider).refreshStatus();
        if (!mounted) return;
        if (user != null) ref.read(entitlementProvider.notifier).set(user);
        if (user?.entitled ?? false) {
          context.go(Routes.home);
          return;
        }
      } catch (_) {
        // A dropped poll is not a failed payment. Keep asking — giving up here would tell a
        // paying user they had not paid.
      }
    }

    _polling = false;
  }

  @override
  Widget build(BuildContext context) {
    final (title, message, action) = switch (widget.outcome) {
      PaymentOutcome.success => (
          "You're all set",
          'Your subscription is active. Enjoy your readings.',
          'Continue',
        ),
      PaymentOutcome.pending => (
          'Confirming your payment',
          'This can take a moment. You can wait here, or check again later.',
          'Check again',
        ),
      PaymentOutcome.failed => (
          'Payment not completed',
          'Nothing was charged. You can try again whenever you are ready.',
          'Try again',
        ),
    };

    final (icon, tint) = switch (widget.outcome) {
      PaymentOutcome.success => (Icons.check_rounded, AppColors.success),
      PaymentOutcome.pending => (Icons.hourglass_top_rounded, AppColors.gold),
      PaymentOutcome.failed => (Icons.close_rounded, AppColors.danger),
    };

    return Scaffold(
      body: AstralBackground(
        surface: AstralSurface.home,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppShape.gutter, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: widget.outcome == PaymentOutcome.pending
                        ? const SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: AppColors.gold,
                            ),
                          )
                        : Icon(icon, size: 48, color: tint),
                  ),
                ),
                const SizedBox(height: 28),
                Text(title, style: AppText.display, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(message, style: AppText.body, textAlign: TextAlign.center),
                const Spacer(),
                PrimaryButton(label: action, onPressed: _onAction),
                if (widget.outcome != PaymentOutcome.success)
                  TextButton(
                    onPressed: () => context.go(Routes.subscribe),
                    child: Text(
                      'Back to plans',
                      style: AppText.meta.copyWith(color: AppColors.gold),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onAction() {
    switch (widget.outcome) {
      // Home is gated, so if the entitlement has not actually landed the gate bounces them
      // back to the paywall rather than this screen having to decide.
      case PaymentOutcome.success:
        context.go(Routes.home);
      case PaymentOutcome.pending:
        _pollUntilEntitled();
      case PaymentOutcome.failed:
        context.go(Routes.subscribe);
    }
  }
}
