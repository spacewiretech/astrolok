import 'package:flutter_web_plugins/url_strategy.dart';

/// Drops the `#` from site URLs.
///
/// Requires the host to rewrite unknown paths to `index.html`, or every route except `/` 404s
/// on a hard load — the CDN answers before Flutter boots, so the router's `errorBuilder` never
/// runs. `web/404.html` is the portable fallback for hosts without a rewrite rule; the README
/// has the real rule for each host.
void configureUrlStrategy() => usePathUrlStrategy();
