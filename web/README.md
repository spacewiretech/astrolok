# web

## Purpose

The web build's host page and static assets. What gets served is the **marketing site**
([../lib/website/](../lib/website/)) — the phone app is never compiled for web.

## Files

- `index.html` — the host page. Carries a small script that restores a path stashed by
  `404.html` (via `sessionStorage['astrolok:redirect']`) with `history.replaceState`, **before
  Flutter boots**.
- `404.html` — the portable half of the deep-link fix. Stashes the path the visitor actually
  asked for and bounces to `/`. Marked `noindex`.
- `manifest.json` — PWA manifest.
- `favicon.png`.

## Subfolders

- `icons/` — `Icon-192`, `Icon-512` and the two maskable variants, referenced by the manifest.

## Notes

- **The one hosting rule that matters:** URLs are clean (`/privacy`, not `/#/privacy`), which
  **requires the host to serve `index.html` for unknown paths**. Without that rule every route
  except `/` returns 404 on a hard load — the CDN answers before Flutter boots, so no amount of
  routing in Dart can help. The root README has the one-line rule per host (Firebase, Netlify,
  Vercel, Cloudflare Pages, nginx, Apache).
- `404.html` is **the safety net, not the plan.** A host configured with the rewrite never
  reaches it. It works, but it answers 404 where a rewrite answers 200 — which matters to
  crawlers and to the policy URLs handed to Play Console and Cashfree.
- The restore script degrades: in a private window with storage blocked the visitor lands on the
  home page, which is a worse answer than the one they asked for but not a broken one.
- **No host config is committed** — deployment is done by hand.
- `icons/*` are upscaled from the 80×80 `assets/icons/om_mark.png` and are soft at 512px. A
  full-size export is already needed for the store listings and would fix both.
- Build with `flutter build web --release`.
