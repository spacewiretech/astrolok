# Astrolok

Astrology, palm reading and astro talk. Flutter app on Riverpod + go_router, with a Supabase
Edge Functions backend, Fast2SMS OTP sign-in and Cashfree UPI Autopay billing.

**1-day trial, then ₹249/month.**

## Running it

```
flutter pub get
flutter run
```

With no `assets/env/app.env` the app boots on the **fake tier**: any 6-digit code signs you in
and the paywall charges nothing. That is deliberate — the whole flow stays walkable on a fresh
checkout. To talk to a real backend, copy the template and fill it in:

```
cp assets/env/app.env.example assets/env/app.env
```

There are three rungs, chosen in `lib/data/providers.dart` and picked automatically:

1. **Supabase** — OTP proxied through Edge Functions, users persisted, every credential
   off-device. The only path where the paywall actually charges.
2. **Fast2SMS direct** — real SMS, but nothing is stored and the API key ships in the app.
3. **Fake** — in-memory, any 6-digit code.

## Layout

```
lib/
  app/          env, router, entitlement gate, theme
  boot/         the compile-time mobile/web split
  data/
    repositories/   interfaces only
    supabase/       the real implementations
    fast2sms/       direct-SMS fallback
    cashfree/       UPI checkout wrapper
    fake/           in-memory tier
    models/
  features/     <name>/{_view, _viewmodel, _state}.dart
  widgets/      shared design-system widgets
  website/      the marketing site — the whole of the web build
supabase/       migrations + Edge Functions (see supabase/README.md)
design/         Figma PNG exports, gitignored
```

Views never call repositories; ViewModels never call the router. A ViewModel that finishes a
step returns a `SplashDestination` and the view routes on it, so the splash and every
onboarding step agree about where a given user belongs.

## The onboarding gate

One function decides, in `lib/features/splash/splash_viewmodel.dart`:

```
!signedIn      -> onboarding
!hasName       -> onboarding (name step)
!hasBirthDate  -> birth
!entitled      -> subscribe
                  home
```

Everything past the paywall is wrapped in `EntitlementGate`, which re-checks on mount, on
resume, and on a timer armed for the entitlement expiry — a one-day trial will routinely run
out while the app is open in someone's pocket, and the cold-start check alone would miss it.

## Payments

The client sends no amount and no plan id, only its session token; the server resolves
everything billable from `app_config`. The Cashfree SDK callback is **never** treated as proof
of payment — it says the UPI app handed control back, not that money moved — so every outcome
ends by polling `subscription-status`, which reconciles against Cashfree.

Outcomes are three-valued, not two: `pending` exists so a real payment whose webhook is late is
never reported as a failure.

See [supabase/README.md](supabase/README.md) for the backend, the security model and setup.

## The website

`lib/website/` is the marketing site, and it is the entire web build — `lib/main.dart` branches
on `kIsWeb` and the app tree is never compiled for web. That split has to be at compile time:
seven files reach `dart:io`, and dart2js rejects the import before tree-shaking can drop it, so
`lib/boot/mobile_boot.dart` is a conditional export rather than a runtime `if`.

The site shares the brand and nothing else — no Riverpod, no repositories, no network. It exists
because the app ships links that have to resolve: `terms_footer.dart` shows
`astrolok.app/privacy` and `/terms` on the onboarding sheets, `profile_view.dart` adds `/help`,
and Cashfree's merchant checklist wants the refund, shipping and contact pages.

```
flutter build web --release
```

Routes: `/`, `/privacy`, `/terms`, `/refund`, `/shipping`, `/delete-account`, `/contact`, and
`/help` (which lands on contact). `siteAliases` in `site_router.dart` redirects the common
near-misses — `/privacypolicy`, `/terms-and-conditions`, `/support` and a dozen more — and the
router lowercases paths and strips a trailing slash, so `/Privacy/` resolves too.

### The one hosting rule that matters

URLs are clean (`/privacy`, not `/#/privacy`), which **requires the host to serve `index.html`
for unknown paths**. Without that rule every route except `/` returns 404 on a hard load: the
CDN answers before Flutter boots, so no amount of routing in Dart can help.

| Host | Rule |
|---|---|
| Firebase | `"rewrites": [{"source": "**", "destination": "/index.html"}]` in `firebase.json` |
| Netlify | a `_redirects` file containing `/* /index.html 200` |
| Vercel | `"rewrites": [{"source": "/(.*)", "destination": "/index.html"}]` in `vercel.json` |
| Cloudflare Pages | a `_redirects` file containing `/* /index.html 200` |
| nginx | `location / { try_files $uri $uri/ /index.html; }` |
| Apache | `FallbackResource /index.html` |

No host config is committed, since deployment is done by hand. `web/404.html` is the portable
safety net for a host with no rewrite: it stashes the requested path and bounces to `/`, where a
script in `index.html` restores it before Flutter boots. It works, but it answers 404 where a
rewrite answers 200 — which matters to crawlers and to the policy URLs given to Play Console and
Cashfree. Set the rewrite if the host allows one.

### Before it goes live

Everything site-specific is in `SitePlaceholders` (`lib/website/site_copy.dart`) — nothing else
hard-codes an address, an email or a store URL. Still open: `supportPhone` is null (the contact
page hides the row rather than printing a fake number), and both store URLs are null, which is
what renders every download button as "Coming soon". Setting either makes that button live with
no other edit.

The legal pages are drafts written to match what the app actually does, not legal advice. Have
them reviewed — particularly the photo-handling sections of the privacy policy.

Also note `web/icons/*` are upscaled from an 80×80 `om_mark.png`, so they are soft at 512px. A
full-size export would fix that, and the same export is already needed for the store listings.

## Tests

```
flutter analyze && flutter test      # 246 tests, 52 of them the website
cd supabase && deno test functions/tests/payments_test.ts   # 38 tests
```

## Status

Onboarding, birth date, paywall and payment flow are wired end to end against the backend. The
screens carry **placeholder styling** — structure and behaviour are final, visuals land once the
Figma exports are in `design/`. Palm reading and astro talk screens come after that.

---

## Folder index

*Every code folder carries a `README.md` mapping its files. This is the top level; each entry
links to the fuller index inside.*

### Files

- `pubspec.yaml` — dependencies, each with a comment explaining why it is there rather than an
  alternative. Also the `flutter_launcher_icons` config and the **directory-based** asset
  declarations.
- `analysis_options.yaml` — lints (`flutter_lints`).
- `.metadata`, `pubspec.lock` — tooling state.

### Subfolders

- [`lib/`](lib/) — all Dart source, for both the phone app and the site. Start at `main.dart`.
- [`supabase/`](supabase/) — the backend: 14 Edge Functions, `_shared/`, migrations, tests.
  Has its own README above this index.
- [`test/`](test/) — the Flutter suite, 23 files, flat.
- [`assets/`](assets/) — bundled artwork, glyphs, fonts and the env template.
- [`web/`](web/) — the web build's host page, the 404 deep-link fallback, PWA icons.
- [`android/`](android/), [`ios/`](ios/) — the two real platform targets. Both carry a committed
  `*.example` template for the per-environment Facebook values.
- [`macos/`](macos/), [`linux/`](linux/), [`windows/`](windows/) — unmodified `flutter create`
  scaffolding. Not shipped, and would not build.

### Notes

- Not indexed, deliberately: generated platform scaffolding (Xcode project dirs, xcasset
  catalogs, `res/mipmap-*`, gradle wrapper), and the four `assets/*` subfolders — `pubspec.yaml`
  declares those as directories, so any file placed in them is bundled into the released app.
  `assets/README.md` covers all four from outside that boundary.
- The test counts quoted earlier in this file have drifted. As of this index: `flutter test`
  runs 351 (not 246) and `deno test functions/tests/` runs 182 (not 38). One Flutter test is
  currently failing — `offer_test.dart`, "the trial length is pluralised", which asserts trial
  copy `SubscriptionOffer` no longer emits.
