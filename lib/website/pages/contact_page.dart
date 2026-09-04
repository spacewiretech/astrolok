import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../policy_docs.dart';
import '../site_copy.dart';
import '../site_shell.dart';
import '../site_theme.dart';
import '../widgets.dart';

/// Contact Us. Required by the payment provider's merchant checklist, and where `/help` —
/// already shipped in the app's profile menu — lands.
class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  @override
  Widget build(BuildContext context) {
    const phone = SitePlaceholders.supportPhone;

    return Title(
      title: 'Contact Us — ${SiteCopy.appName}',
      color: AppColors.navy,
      child: SiteShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SiteSection(
              background: SiteColors.tint,
              tight: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CONTACT', style: SiteText.eyebrow),
                    const SizedBox(height: 14),
                    Text('Get in touch', style: SiteText.section(context)),
                    const SizedBox(height: 16),
                    Text(
                      'Questions about a reading, a payment or your account — write to us and '
                      'a person will answer.',
                      style: SiteText.sectionSub(context),
                    ),
                  ],
                ),
              ),
            ),
            SiteSection(
              tight: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ContactRow(
                      icon: Icons.mail_outline_rounded,
                      label: 'Email',
                      value: SitePlaceholders.supportEmail,
                      onTap: () =>
                          openExternal('mailto:${SitePlaceholders.supportEmail}'),
                    ),
                    // Hidden rather than shown as a placeholder while there is no number —
                    // a fake phone number on a contact page is worse than no phone number.
                    if (phone != null)
                      _ContactRow(
                        icon: Icons.call_outlined,
                        label: 'Phone',
                        value: phone,
                        onTap: () => openExternal('tel:$phone'),
                      ),
                    const _ContactRow(
                      icon: Icons.location_on_outlined,
                      label: 'Registered office',
                      value: '${SitePlaceholders.legalEntity}\n'
                          '${SitePlaceholders.address}',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We reply within two working days, and usually the same day.',
                      style: SiteText.cardBody(context),
                    ),
                    const SizedBox(height: 34),
                    const Divider(),
                    const SizedBox(height: 28),
                    Text('Common requests', style: SiteText.cardTitle(context)),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 24,
                      runSpacing: 10,
                      children: [
                        SiteLink(
                          label: 'Cancel my subscription',
                          style: SiteText.cardBody(context),
                          onTap: () => context.go('/${PolicyDocs.refund.slug}'),
                        ),
                        SiteLink(
                          label: 'Delete my account',
                          style: SiteText.cardBody(context),
                          onTap: () => context.go('/${PolicyDocs.deleteAccount.slug}'),
                        ),
                        SiteLink(
                          label: 'How my photos are handled',
                          style: SiteText.cardBody(context),
                          onTap: () => context.go('/${PolicyDocs.privacy.slug}'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: AppColors.goldWash,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 21, color: AppColors.goldDeep),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: SiteText.cardTitle(context).copyWith(fontSize: 16)),
                const SizedBox(height: 4),
                if (onTap == null)
                  Text(value, style: SiteText.prose(context))
                else
                  SiteLink(
                    label: value,
                    style: SiteText.prose(context),
                    onTap: onTap!,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
