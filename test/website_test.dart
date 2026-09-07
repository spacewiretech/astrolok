import 'package:astrolok/data/repositories/app_config_repository.dart';
import 'package:astrolok/website/pages/contact_page.dart';
import 'package:astrolok/website/pages/home_page.dart';
import 'package:astrolok/website/pages/not_found_page.dart';
import 'package:astrolok/website/pages/policy_page.dart';
import 'package:astrolok/website/policy_docs.dart';
import 'package:astrolok/website/site_app.dart';
import 'package:astrolok/website/site_copy.dart';
import 'package:astrolok/website/site_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// The marketing site. Everything here runs against a desktop-sized window, because that is
/// the layout most of the site's shape decisions are about.
///
/// The routing cases are the point of this file: the site's whole job is that the policy URLs
/// shipped inside the app — `defaultAppConfig`'s `privacy_url`, `terms_url` and `help_url`,
/// which the onboarding footer and the account menu open — reach the page they promise.
void main() {
  /// A 1440x2400 window: wide enough for the desktop breakpoint, tall enough that a whole page
  /// lays out without scrolling, so `find.text` sees every section.
  const desktop = Size(1440, 2400);

  setUpAll(() {
    // The site draws Poppins and Inter through google_fonts, which would otherwise try to
    // fetch them over a network the test has no business touching.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpSite(WidgetTester tester, {String at = SiteRoutes.home}) async {
    tester.view.physicalSize = desktop;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(AstrolokSiteApp(router: buildSiteRouter(initialLocation: at)));
    await tester.pumpAndSettle();
  }

  group('home', () {
    testWidgets('leads with the headline and the price', (tester) async {
      await pumpSite(tester);

      expect(find.text(SiteCopy.heroHeadline), findsOneWidget);
      expect(find.text(SiteCopy.priceLine), findsWidgets);
    });

    testWidgets('names every reading', (tester) async {
      await pumpSite(tester);

      for (final feature in SiteCopy.features) {
        expect(find.text(feature.title), findsWidgets, reason: feature.title);
      }
    });

    testWidgets('says Chat with Astro is not built yet', (tester) async {
      await pumpSite(tester);

      // Home shows a "coming soon" snackbar rather than a dead chevron; the site has to be
      // just as honest, or it is selling something that does not exist.
      expect(find.text('Coming soon'), findsWidgets);
    });
  });

  test('prices match the paywall defaults', () {
    // `app_config_repository.dart` is the source of truth — the server can override it at
    // runtime. If a price changes there and not here, the site quietly advertises the old one.
    expect(SiteCopy.trialPrice, defaultAppConfig['trial_price_label']);
    expect(SiteCopy.planPrice, defaultAppConfig['plan_price_label']);
    expect('${SiteCopy.trialDays}', defaultAppConfig['cashfree_trial_days']);
  });

  group('policy pages', () {
    for (final doc in PolicyDocs.all) {
      testWidgets('/${doc.slug} renders in full', (tester) async {
        await pumpSite(tester, at: '/${doc.slug}');

        expect(find.byType(PolicyPage), findsOneWidget);
        // The intro, not the title: a title like "Privacy Policy" is also the footer's link
        // label for the same page, so it legitimately appears more than once.
        expect(find.text(doc.intro), findsOneWidget);

        for (final section in doc.sections) {
          expect(find.text(section.heading), findsOneWidget, reason: section.heading);
        }
      });
    }

    testWidgets('every doc has real content', (tester) async {
      for (final doc in PolicyDocs.all) {
        expect(doc.sections, isNotEmpty, reason: doc.slug);
        for (final section in doc.sections) {
          expect(
            section.paragraphs.isNotEmpty || section.bullets.isNotEmpty,
            isTrue,
            reason: '${doc.slug} / ${section.heading} is an empty section',
          );
        }
      }
    });
  });

  group('routing', () {
    testWidgets('the home route builds the home page', (tester) async {
      await pumpSite(tester);
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('/contact builds the contact page', (tester) async {
      await pumpSite(tester, at: SiteRoutes.contact);
      expect(find.byType(ContactPage), findsOneWidget);
    });

    testWidgets('/help lands on contact', (tester) async {
      // Already shipped in the app's profile menu, so this path is not optional.
      await pumpSite(tester, at: SiteRoutes.help);
      expect(find.byType(ContactPage), findsOneWidget);
    });

    // The reported bug: `/privacypolicy` is the natural guess for a privacy page and used to
    // land on nothing. Each alias is checked against the page it claims to reach.
    for (final entry in siteAliases.entries) {
      testWidgets('${entry.key} redirects to ${entry.value}', (tester) async {
        await pumpSite(tester, at: entry.key);

        final slug = entry.value.substring(1);
        final doc = PolicyDocs.bySlug(slug);

        if (doc != null) {
          expect(find.byType(PolicyPage), findsOneWidget, reason: entry.key);
          expect(find.text(doc.intro), findsOneWidget, reason: entry.key);
        } else {
          expect(find.byType(ContactPage), findsOneWidget, reason: entry.key);
        }
        expect(find.byType(NotFoundPage), findsNothing, reason: entry.key);
      });
    }

    testWidgets('a mixed-case path with a trailing slash still resolves', (tester) async {
      await pumpSite(tester, at: '/Privacy/');

      expect(find.byType(PolicyPage), findsOneWidget);
      expect(find.text(PolicyDocs.privacy.intro), findsOneWidget);
    });

    testWidgets('an unknown path shows the 404, not the home page', (tester) async {
      await pumpSite(tester, at: '/no-such-page');

      expect(find.byType(NotFoundPage), findsOneWidget);
      // Circle360 returns its home page here, which reads as though the link worked.
      expect(find.byType(HomePage), findsNothing);
      expect(find.textContaining('/no-such-page'), findsOneWidget);
    });

    test('no alias shadows a canonical route', () {
      final canonical = {
        SiteRoutes.home,
        SiteRoutes.contact,
        SiteRoutes.help,
        for (final doc in PolicyDocs.all) '/${doc.slug}',
      };

      for (final alias in siteAliases.keys) {
        expect(canonical, isNot(contains(alias)), reason: '$alias is already a real route');
        expect(alias, alias.toLowerCase(), reason: '$alias is unreachable after normalising');
      }
    });

    test('every alias points at a route that exists', () {
      final canonical = {
        SiteRoutes.contact,
        for (final doc in PolicyDocs.all) '/${doc.slug}',
      };

      for (final target in siteAliases.values) {
        expect(canonical, contains(target));
      }
    });
  });

  group('narrow layouts', () {
    // A RenderFlex overflow throws in a test, so pumping every page at a phone width and
    // asserting nothing was thrown is the whole check — the same approach as `layout_test.dart`.
    const phone = Size(360, 4000);

    Future<void> pumpAt(WidgetTester tester, Size size, String route) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        AstrolokSiteApp(router: buildSiteRouter(initialLocation: route)),
      );
      await tester.pumpAndSettle();
    }

    final routes = <String>[
      SiteRoutes.home,
      SiteRoutes.contact,
      '/no-such-page',
      for (final doc in PolicyDocs.all) '/${doc.slug}',
    ];

    for (final route in routes) {
      testWidgets('$route fits a 360pt phone', (tester) async {
        await pumpAt(tester, phone, route);
        expect(tester.takeException(), isNull, reason: route);
      });
    }

    testWidgets('the nav collapses to a hamburger below the breakpoint', (tester) async {
      await pumpAt(tester, phone, SiteRoutes.home);

      // The desktop links would overflow a phone, so they must not be built at all.
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
      expect(find.text('How it works'), findsNothing);
    });

    testWidgets('the desktop nav is present above the breakpoint', (tester) async {
      await pumpAt(tester, const Size(1280, 2400), SiteRoutes.home);

      expect(find.byIcon(Icons.menu_rounded), findsNothing);
      expect(find.text('How it works'), findsOneWidget);
    });
  });

  group('the footer', () {
    testWidgets('links to every policy and to support', (tester) async {
      await pumpSite(tester);

      for (final doc in PolicyDocs.all) {
        expect(find.text(doc.navLabel), findsWidgets, reason: doc.navLabel);
      }
      expect(find.text(SitePlaceholders.supportEmail), findsWidgets);
    });
  });

  group('placeholders', () {
    test('carry no unfilled markers', () {
      final values = <String>[
        SitePlaceholders.legalEntity,
        SitePlaceholders.address,
        SitePlaceholders.supportEmail,
        SitePlaceholders.siteDomain,
        SitePlaceholders.lastUpdated,
        SitePlaceholders.copyrightYear,
      ];

      for (final value in values) {
        expect(value, isNotEmpty);
        expect(value, isNot(contains('XXX')));
        expect(value, isNot(contains('TODO')));
        expect(value, isNot(matches(RegExp(r'\[.+\]'))));
      }
    });

    test('the support email is the one the app opens', () {
      expect(SitePlaceholders.supportEmail, contains('@'));
      expect(SitePlaceholders.supportEmail, endsWith(SitePlaceholders.siteDomain));
      // The app opens `support_url` from config, which ships as a mailto: at this address.
      // Config can point it somewhere else entirely — that is the feature — but what a build
      // carries and what the contact page prints must not disagree.
      expect(
        defaultAppConfig.configLink('support_url'),
        contains(SitePlaceholders.supportEmail),
      );
    });

    test('store links are still deliberately absent', () {
      // Flipping either to a real URL makes every download button live; until then the
      // buttons render "Coming soon" rather than pointing at a listing that does not exist.
      expect(SitePlaceholders.playStoreUrl, isNull);
      expect(SitePlaceholders.appStoreUrl, isNull);
    });
  });

  group('the links the app already ships', () {
    // This is the whole reason the site exists. `terms_footer.dart` shows these on the
    // onboarding sheets and `profile_view.dart` in the account menu; they were dead before
    // the site, and this pins them to routes that actually resolve.
    //
    // They come from the `app_config` table now, so config can point a build anywhere and
    // this cannot follow it there. What it can still guarantee is the part that ships: the
    // defaults baked into the binary, which are also what a blank row falls back to.
    const shipped = ['privacy_url', 'terms_url', 'help_url'];

    test('point at this site', () {
      for (final key in shipped) {
        expect(
          defaultAppConfig.configLink(key),
          startsWith('https://${SitePlaceholders.siteDomain}/'),
          reason: key,
        );
      }
    });

    for (final key in shipped) {
      final url = defaultAppConfig.configLink(key);
      testWidgets('$url resolves to a real page', (tester) async {
        final path = Uri.parse(url).path;
        await pumpSite(tester, at: path);

        expect(find.byType(NotFoundPage), findsNothing, reason: url);
      });
    }
  });
}
