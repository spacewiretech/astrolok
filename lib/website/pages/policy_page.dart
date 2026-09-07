import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../policy_docs.dart';
import '../site_copy.dart';
import '../site_shell.dart';
import '../site_theme.dart';
import '../widgets.dart';

/// Renders any [PolicyDoc]. All five legal pages route here.
class PolicyPage extends StatelessWidget {
  const PolicyPage({super.key, required this.doc});

  final PolicyDoc doc;

  @override
  Widget build(BuildContext context) {
    return Title(
      title: '${doc.title} — ${SiteCopy.appName}',
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
                    Text(
                      'LAST UPDATED ${SitePlaceholders.lastUpdated.toUpperCase()}',
                      style: SiteText.eyebrow,
                    ),
                    const SizedBox(height: 14),
                    Text(doc.title, style: SiteText.section(context)),
                    const SizedBox(height: 16),
                    Text(doc.intro, style: SiteText.sectionSub(context)),
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
                    for (final section in doc.sections) _Section(section: section),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 28),
                    _OtherPolicies(current: doc),
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

class _Section extends StatelessWidget {
  const _Section({required this.section});

  final PolicySection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.heading, style: SiteText.policyHeading(context)),
          const SizedBox(height: 12),
          for (final paragraph in section.paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(paragraph, style: SiteText.prose(context)),
            ),
          for (final bullet in section.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A dot drawn rather than a bullet character, so it sits on the cap height
                  // of the first line instead of the baseline.
                  Container(
                    margin: const EdgeInsets.only(top: 10, right: 14),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.gold,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(child: Text(bullet, style: SiteText.prose(context))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Cross-links to the other legal pages, so a visitor who landed on one from a store listing
/// can reach the rest without going back to the footer.
class _OtherPolicies extends StatelessWidget {
  const _OtherPolicies({required this.current});

  final PolicyDoc current;

  @override
  Widget build(BuildContext context) {
    final others = PolicyDocs.all.where((doc) => doc.slug != current.slug);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Other policies', style: SiteText.cardTitle(context)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 24,
          runSpacing: 10,
          children: [
            for (final doc in others)
              SiteLink(
                label: doc.navLabel,
                style: SiteText.cardBody(context),
                onTap: () => context.go('/${doc.slug}'),
              ),
            SiteLink(
              label: 'Contact Us',
              style: SiteText.cardBody(context),
              onTap: () => context.go('/contact'),
            ),
          ],
        ),
      ],
    );
  }
}
