import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/entitlement.dart';
import '../../data/models/app_user.dart';
import '../../data/providers.dart';
import '../../data/repositories/app_config_repository.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/circle_icon_button.dart';
import '../chat/chat_copy.dart';
import '../chat/chat_viewmodel.dart';

/// The account.
///
/// Shows only what this app actually knows about a user. The design mock carried four rows that
/// were deliberately left out, and it is worth saying why so nobody "restores" them later:
///
///  * **Member ID** — there is no human-readable member number anywhere in the system, only a
///    uuid. Printing eight characters of a uuid and calling it a membership is a decoration
///    pretending to be a fact.
///  * **Amount Paid** — `total_paid_amount` exists in Postgres but is not in `USER_COLUMNS` or
///    `entitlementPayload()`, so no client has ever seen it. Showing it needs an Edge Function
///    change, not a widget.
///  * **App Language** — the app has no localisation at all. The row would open a picker with
///    one entry in it.
///  * **The profile photograph** — `AppUser.avatarUrl` exists on the model but has no server
///    column, no upload path, and is never populated. A plain icon is the honest version.
class ProfileView extends ConsumerWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(entitlementProvider);
    // The four external rows below open whatever config says. Defaults stand in until it
    // resolves, so the menu is never briefly full of rows that open nothing.
    final config = ref.watch(appConfigProvider).valueOrNull ?? defaultAppConfig;

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
                          context.canPop() ? context.pop() : context.go(Routes.home),
                    ),
                    Expanded(
                      child: Text(
                        'My Profile',
                        style: AppText.section,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // Balances the back button so the title sits centred.
                    const SizedBox(width: AppShape.avatar),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppShape.gutter,
                    24,
                    AppShape.gutter,
                    32,
                  ),
                  children: [
                    const _Avatar(),
                    const SizedBox(height: 14),
                    Text(
                      user?.hasName ?? false ? user!.name : 'Your account',
                      style: AppText.sheetTitle,
                      textAlign: TextAlign.center,
                    ),
                    if (user != null && user.phone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '+91 ${user.phone}',
                        style: AppText.meta,
                        textAlign: TextAlign.center,
                      ),
                    ],

                    const SizedBox(height: 22),
                    _PlanCard(user: user),

                    if (user?.billingState != null) ...[
                      const SizedBox(height: 14),
                      _BillingNotice(message: user!.billingState!.message),
                    ],

                    const SizedBox(height: 22),
                    _MenuGroup(
                      rows: [
                        _MenuRow(
                          icon: Icons.file_download_outlined,
                          label: 'Downloads',
                          onTap: () => context.push(Routes.downloads),
                        ),
                        _MenuRow(
                          icon: Icons.auto_awesome_outlined,
                          label: ChatCopy.memoryHeading,
                          onTap: () => context.push(Routes.memory),
                        ),
                        _MenuRow(
                          icon: Icons.phone_outlined,
                          label: 'Contact us',
                          // Launched with whatever scheme config gives it, so support can
                          // move off email without an app release.
                          onTap: () => _open(
                            context,
                            Uri.parse(config.configLink('support_url')),
                          ),
                        ),
                        _MenuRow(
                          icon: Icons.info_outline_rounded,
                          label: 'Help & FAQ',
                          onTap: () =>
                              _open(context, Uri.parse(config.configLink('help_url'))),
                        ),
                        _MenuRow(
                          icon: Icons.shield_outlined,
                          label: 'Privacy Policy',
                          onTap: () =>
                              _open(context, Uri.parse(config.configLink('privacy_url'))),
                        ),
                        _MenuRow(
                          icon: Icons.receipt_long_outlined,
                          label: 'Terms & Conditions',
                          onTap: () =>
                              _open(context, Uri.parse(config.configLink('terms_url'))),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),
                    const _LogOutButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _open(BuildContext context, Uri uri) async {
    final opened =
        await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    // A device with no mail client, or no browser. Silence would look like a dead row.
    if (!opened && context.mounted) {
      showAppSnackBar(context, "Couldn't open that on this device.", error: true);
    }
  }
}

/// A plain gold-ringed disc. No photograph — see the class comment on [ProfileView].
class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.gold, width: 2),
        ),
        child: const Icon(
          Icons.person_outline_rounded,
          size: 46,
          color: AppColors.navy,
        ),
      ),
    );
  }
}

/// The subscription, as far as the client can honestly report it.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final entitled = user?.entitled ?? false;
    final inTrial = user?.inTrial ?? false;

    final (label, tint) = switch (user?.paymentType) {
      _ when !entitled => ('Subscription Ended', AppColors.muted),
      PaymentType.trial when inTrial => ('Trial Active', AppColors.gold),
      PaymentType.cancelled => ('Ending Soon', AppColors.career),
      _ => ('Premium Active', AppColors.gold),
    };

    final validTill = user?.entitlementExpiresAt;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: tint, borderRadius: AppShape.pill),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.workspace_premium_outlined,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppText.title.copyWith(fontSize: 13, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (validTill != null)
            _PlanRow(
              // "Valid till" for a live subscription, "Ended" once it has lapsed — the same
              // date means two different things either side of now.
              label: entitled ? 'Valid till' : 'Ended',
              value: _formatDate(validTill),
            )
          else
            Text(
              'No active subscription.',
              style: AppText.meta,
            ),
          if (!entitled) ...[
            const SizedBox(height: 14),
            _RenewLink(),
          ],
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppText.meta),
        Text(value, style: AppText.title.copyWith(fontSize: 15)),
      ],
    );
  }
}

class _RenewLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: () => context.push(Routes.subscribe),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          'Renew to keep your readings',
          style: AppText.title.copyWith(fontSize: 14, color: AppColors.goldDeep),
        ),
      ),
    );
  }
}

class _BillingNotice extends StatelessWidget {
  const _BillingNotice({required this.message});

  final String message;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.gold),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: AppText.meta)),
        ],
      ),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSoft,
        borderRadius: AppShape.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, row) in rows.indexed) ...[
            if (index > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 54,
                color: AppColors.divider,
              ),
            row,
          ],
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.navy),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: AppText.title)),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// The same two lines the paywall already runs, in the place a user would look for them.
class _LogOutButton extends ConsumerWidget {
  const _LogOutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: TextButton(
        onPressed: () async {
          await ref.read(authRepositoryProvider).signOut();
          forgetConversations(ref);
          if (context.mounted) context.go(Routes.onboarding);
        },
        child: Text(
          'Logout',
          style: AppText.title.copyWith(color: AppColors.danger),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
