import 'package:go_router/go_router.dart';

import 'pages/contact_page.dart';
import 'pages/home_page.dart';
import 'pages/not_found_page.dart';
import 'pages/policy_page.dart';
import 'policy_docs.dart';

abstract final class SiteRoutes {
  static const home = '/';
  static const privacy = '/privacy';
  static const terms = '/terms';
  static const refund = '/refund';
  static const shipping = '/shipping';
  static const deleteAccount = '/delete-account';
  static const contact = '/contact';

  /// `lib/features/profile/profile_view.dart` already ships `https://astrolok.app/help` in its
  /// menu, so the path has to exist. There is no separate help centre to send it to — the
  /// contact page is the answer to "I need help".
  static const help = '/help';

  /// Jump straight to a section of the home page — used by the nav when you are already on
  /// another page. `HomePage` reads it and scrolls after the first frame.
  static String homeSection(String anchor) => '/?to=$anchor';
}

/// Paths that are not canonical but that people and old links use anyway, each redirecting to
/// the real one.
///
/// `/privacypolicy` is the reason this map exists: it is the natural guess for a privacy page,
/// it is what gets typed into a browser, and without an entry here it lands on a 404 that looks
/// like the site is broken. Cheap to carry, and every one of them is a link that would
/// otherwise be dead.
///
/// Note this only helps once Flutter has booted, which needs the host to serve `index.html` for
/// an unknown path — see `url_strategy_web.dart` and `web/404.html`.
const siteAliases = <String, String>{
  '/privacypolicy': SiteRoutes.privacy,
  '/privacy-policy': SiteRoutes.privacy,
  '/policy': SiteRoutes.privacy,
  '/termsandconditions': SiteRoutes.terms,
  '/terms-and-conditions': SiteRoutes.terms,
  '/terms-of-service': SiteRoutes.terms,
  '/tos': SiteRoutes.terms,
  '/refunds': SiteRoutes.refund,
  '/cancellation': SiteRoutes.refund,
  '/cancellation-and-refund': SiteRoutes.refund,
  '/shipping-and-delivery': SiteRoutes.shipping,
  '/delete': SiteRoutes.deleteAccount,
  '/deleteaccount': SiteRoutes.deleteAccount,
  '/account-deletion': SiteRoutes.deleteAccount,
  '/contact-us': SiteRoutes.contact,
  '/contactus': SiteRoutes.contact,
  '/support': SiteRoutes.contact,
};

/// Separate from `appRouter` in `lib/app/router.dart` on purpose: the site shares the brand but
/// none of the app's state, gates or redirects. They could not be merged anyway — both claim
/// `/`, where the app puts its splash.
final siteRouter = buildSiteRouter();

/// A fresh router. The app uses the single [siteRouter]; tests build their own so that
/// navigating in one case cannot leak into the next.
GoRouter buildSiteRouter({String initialLocation = SiteRoutes.home}) => GoRouter(
      initialLocation: initialLocation,

      // Case and a trailing slash are not meant to be significant. A URL read off a printed
      // page or a store listing arrives as `/Privacy/` often enough to be worth normalising
      // here rather than adding four more entries to [siteAliases] for each page.
      redirect: (context, state) {
        final path = state.uri.path;
        var normalised = path.toLowerCase();
        if (normalised.length > 1 && normalised.endsWith('/')) {
          normalised = normalised.substring(0, normalised.length - 1);
        }
        if (normalised == path) return null;
        return state.uri.replace(path: normalised).toString();
      },

      routes: [
        GoRoute(
          path: SiteRoutes.home,
          builder: (context, state) => HomePage(anchor: state.uri.queryParameters['to']),
        ),

        // One route per legal page, generated so that adding a PolicyDoc adds its page, its
        // footer link and its route together.
        for (final doc in PolicyDocs.all)
          GoRoute(
            path: '/${doc.slug}',
            builder: (context, state) => PolicyPage(doc: doc),
          ),

        GoRoute(
          path: SiteRoutes.contact,
          builder: (context, state) => const ContactPage(),
        ),
        GoRoute(
          path: SiteRoutes.help,
          redirect: (context, state) => SiteRoutes.contact,
        ),

        for (final entry in siteAliases.entries)
          GoRoute(
            path: entry.key,
            redirect: (context, state) => entry.value,
          ),
      ],

      // A mistyped URL should say so and offer a way out. Circle360 returns its home page here,
      // which is worse than it sounds — the wrong page loads with a 200 and the visitor is left
      // thinking the link worked.
      errorBuilder: (context, state) => NotFoundPage(path: state.uri.path),
    );
