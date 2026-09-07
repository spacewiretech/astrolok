import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../policy_docs.dart';
import '../site_copy.dart';
import '../site_router.dart';
import '../site_shell.dart';
import '../site_theme.dart';
import '../widgets.dart';

/// Shown for a path that matches nothing, after [siteAliases] has had its chance.
///
/// Deliberately not a redirect to the home page: a visitor who followed a policy link from a
/// store listing needs to be told the link was wrong and handed the right one, not shown the
/// pitch and left assuming they are on the page they asked for.
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key, this.path});

  /// The path that missed. Echoed back so a mistyped URL is obvious on sight.
  final String? path;

  @override
  Widget build(BuildContext context) {
    return Title(
      title: 'Page not found — ${SiteCopy.appName}',
      color: AppColors.navy,
      child: SiteShell(
        child: SiteSection(
          gradient: AppColors.backdropWarm,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('404', style: SiteText.eyebrow),
                const SizedBox(height: 14),
                Text('We could not find that page', style: SiteText.section(context)),
                const SizedBox(height: 16),
                Text(
                  path == null || path!.isEmpty
                      ? 'The link may be out of date, or the address mistyped.'
                      : 'Nothing lives at $path. The link may be out of date, or the '
                          'address mistyped.',
                  style: SiteText.sectionSub(context),
                ),
                const SizedBox(height: 32),
                Text('Try one of these', style: SiteText.cardTitle(context)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 24,
                  runSpacing: 10,
                  children: [
                    for (final doc in PolicyDocs.all)
                      SiteLink(
                        label: doc.navLabel,
                        style: SiteText.cardBody(context),
                        onTap: () => context.go('/${doc.slug}'),
                      ),
                    SiteLink(
                      label: 'Contact Us',
                      style: SiteText.cardBody(context),
                      onTap: () => context.go(SiteRoutes.contact),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                SiteButton(
                  label: 'Back to home',
                  onPressed: () => context.go(SiteRoutes.home),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
