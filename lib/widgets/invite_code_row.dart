import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_typography.dart';
import '../data/attribution/attribution_service.dart';
import '../data/repositories/referral_repository.dart';
import 'phone_field.dart';

/// "Have an invite code?" — the manual fallback, collapsed until asked for.
///
/// ## Why this exists at all
///
/// An invite is a Play Store link carrying `ref_code`, and Google hands that back through the
/// Install Referrer API on first launch — so almost every referred install attributes itself with
/// nobody typing anything. This covers the cases where Google has no referrer to give: a build
/// installed from an APK, a device restored from a backup, or someone who reached the listing by
/// searching for the app after being told about it rather than by tapping the link.
///
/// Deliberately unobtrusive. There is no reward yet, so almost nobody has a reason to open it, and
/// a mandatory field here would cost more signups than the attribution is worth.
///
/// ## Where it has to live
///
/// Before the paywall. `referral-claim` refuses an account that has ever had a trial or a paid
/// period, so a code typed after checkout is always `not_eligible` — which is why this sits on the
/// language screen and did not follow the name to after payment.
///
/// ## Why it is safe to leave in the funnel
///
/// It renders as a single text button until tapped, it never blocks the screen's own action, and
/// callers hide it entirely when `referral_enabled` is false — so if it ever does measurably hurt
/// conversion it can be switched off from the dashboard without a release.
class InviteCodeRow extends StatefulWidget {
  const InviteCodeRow({super.key});

  @override
  State<InviteCodeRow> createState() => _InviteCodeRowState();
}

class _InviteCodeRowState extends State<InviteCodeRow> {
  final _controller = TextEditingController();
  bool _open = false;
  bool _busy = false;
  String? _message;
  bool _applied = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    final result = await attributionService.submitManualCode(_controller.text);
    if (!mounted) return;

    setState(() {
      _busy = false;
      // `alreadyReferred` counts as applied: the user's install is attributed, just not to the
      // code they typed, and telling them their invite "failed" would be both confusing and
      // untrue.
      _applied = result.status == ReferralClaimStatus.created ||
          result.status == ReferralClaimStatus.alreadyReferred;
      _message = switch (result.status) {
        ReferralClaimStatus.created => 'Invite applied',
        ReferralClaimStatus.alreadyReferred => 'Invite applied',
        ReferralClaimStatus.invalidCode => 'That code is not valid',
        ReferralClaimStatus.selfReferral => 'You cannot use your own invite code',
        ReferralClaimStatus.notEligible => 'This code cannot be applied to your account',
        // Everything else is a "not now" rather than a "no" — an unreachable backend, or the
        // feature switched off between the screen rendering and the tap.
        _ => 'Could not apply that code right now',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_applied) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          _message ?? 'Invite applied',
          style: AppText.meta.copyWith(color: AppColors.success),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (!_open) {
      return TextButton(
        onPressed: () => setState(() => _open = true),
        child: Text(
          'Have an invite code?',
          style: AppText.meta.copyWith(color: AppColors.muted),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          TextFieldBox(
            controller: _controller,
            hint: 'Invite code',
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _submit,
            child: Text(
              _busy ? 'Applying…' : 'Apply code',
              style: AppText.meta.copyWith(color: AppColors.goldDeep),
            ),
          ),
          if (_message != null)
            Text(
              _message!,
              style: AppText.meta.copyWith(color: AppColors.danger),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}
