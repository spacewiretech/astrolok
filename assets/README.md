# assets

## Purpose

Everything bundled into the app: artwork, glyphs, fonts and the environment file. Paths are
referenced through the constants in [../lib/app/assets.dart](../lib/app/assets.dart), never as
string literals at a call site.

## Subfolders

- `images/` — 12 PNGs: the two full-bleed grounds (`bg_onboarding` nearly white, `bg_home`
  markedly warmer), the three onboarding hero mockups, the three flattened promo cards
  (all 712×346), the three Explore Readings thumbnails (190px square), and `app_icon.png`.
  Declared in Dart as `Img`.
- `icons/` — 18 PNGs: the brand mark and wordmark (`Brand`), the palm flow's glyphs
  (`PalmIcon`), the four face glyphs (`FaceIcon`) and the two chat glyphs (`ChatIcon`).
- `fonts/` — `Poppins-Regular.ttf` and `Poppins-SemiBold.ttf`.
- `env/` — `app.env.example`, the committed template. `app.env` itself is gitignored. Both hold
  two kinds of row: the four UPPERCASE keys `Env` owns, and a mirror of the whole `app_config`
  table under its own key names. The mirror is what the app runs on when Supabase is unreachable
  — see [../lib/app/env.dart](../lib/app/env.dart) and `shippedAppConfig`. **Note the bundling
  rule below: everything written there ships inside the released app.**

## Notes

- **`pubspec.yaml` declares these as directories, not individual files**, so a checkout that has
  not created `assets/env/app.env` still builds — and so **every file in those four folders is
  bundled into the released app**. That is why this README sits at `assets/` and not inside
  them: `assets/` itself is not a declared directory.
- **`app.env` is readable by anyone holding the build.** `unzip -p app.apk
  assets/flutter_assets/assets/env/app.env` prints it. The anon key was always fine there — RLS,
  not secrecy, is what protects the data behind it — but the `app_config` mirror now also carries
  the rows Supabase marks `is_public = false`, by decision. Those are read server-side by Edge
  Functions with `service_role` and are never fetched by the client, so nothing in the app reads
  them; they are in the bundle regardless. Treat the Cashfree, Gemini, Fast2SMS and reconcile
  credentials as rotated on a schedule rather than long-lived.
- **The fonts are for the PDF export only.** They are declared as *assets*, not under pubspec's
  `fonts:` — the UI renders Poppins through `google_fonts` at runtime. The `pdf` package's
  built-in Helvetica covers Latin-1 and nothing else, so a reading containing a curly quote or
  an em dash would render blank boxes without the raw bytes.
- **Several referenced assets do not exist yet.** Every `Svg.*` path in `assets.dart` is still
  to be exported, and `Img.paywallPoster` is absent. This is safe: they load through
  `SafeImage`/`SafeSvg`, which fall back to a Material icon — a missing file costs its own box,
  never the screen. `test/asset_fallback_test.dart` keeps that true.
- `om_mark.png` is an 80×80 export. Both stores want 1024 square, and `web/icons/*` are upscaled
  from it and visibly soft at 512px. One full-size export fixes the launcher icons, the web
  icons and the store listings together.
- Figma source exports live in `design/`, which is gitignored and never shipped.
