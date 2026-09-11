# lib/website

## Purpose

The marketing site — and **the entire web build**. `lib/main.dart` branches on `kIsWeb` and
returns here; the phone app tree is never compiled for web.

## Files

- `site_app.dart` — the root widget the web build runs. Declares: `AstrolokSiteApp`.
- `site_router.dart` — Declares: `SiteRoutes`, `siteAliases` (redirects for common near-misses),
  `siteRouter`, `buildSiteRouter({initialLocation})`. Lowercases paths, strips a trailing slash,
  generates the policy routes, and sends anything unmatched to `NotFoundPage`.
- `site_shell.dart` — page chrome and layout. Declares: `ContentWidth`, `SiteSection`,
  `SectionHeading`, `SiteShell`, `HomeAnchors`, `SiteNav`, `SiteFooter`, `goToSection()`.
- `site_theme.dart` — Declares: `Breaks`, `SiteShape`, `SiteColors`, `SiteText`,
  `buildSiteTheme()`, plus `isMobile()`, `isDesktop()`, `gridColumns()`.
- `site_copy.dart` — Declares: `SitePlaceholders`, `SiteCopy`, `FeatureCopy`, `StepCopy`,
  `FaqCopy`. **The only file holding business facts.**
- `policy_docs.dart` — Declares: `PolicyDoc`, `PolicySection`, `PolicyDocs` (`.all`).
- `widgets.dart` — Declares: `SiteButton`, `StoreCta`, `FeatureCard`, `StepCard`, `FaqItem`,
  `SiteLink`, `openExternal()`.
- `url_strategy.dart` — conditional export on `dart.library.js_interop`.
- `url_strategy_web.dart` — `configureUrlStrategy()` → `usePathUrlStrategy()`, dropping the `#`.
- `url_strategy_stub.dart` — the no-op off web.

## Subfolders

- `pages/` — one file per route.

## Notes

- **It shares the brand and nothing else** with the app: no Riverpod, no `ProviderScope`, no
  repositories, no `Env`, no network. It exists because the app ships links that must resolve —
  `terms_footer.dart` shows `/privacy` and `/terms`, `profile_view.dart` adds `/help`, and
  Cashfree's merchant checklist wants refund, shipping and contact pages.
- The two apps both claim `/`, so the routers cannot be merged.
- **Adding a `PolicyDoc` to `PolicyDocs.all` adds its page, its route and its footer link
  together** — that is the only edit a new legal page needs.
- **The one hosting rule that matters:** URLs are clean (`/privacy`, not `/#/privacy`), which
  requires the host to serve `index.html` for unknown paths. Without that, every route except
  `/` 404s on a hard load — the CDN answers before Flutter boots. `web/404.html` is the
  portable fallback; see [../../web/](../../web/) and the root README's host table.
- Before launch: everything site-specific is in `SitePlaceholders`. `supportPhone` and both
  store URLs are still null — which is what renders every download button as "Coming soon".
  The legal pages are drafts written to match what the app does, not legal advice.
- Build with `flutter build web --release`. Tests: `test/website_test.dart` (52 of the suite's
  tests), including price parity with the paywall defaults.
