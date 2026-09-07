/// The web half of [mobile_boot.dart]'s conditional export.
///
/// Never called: `main()` runs the site and returns before reaching this. It exists so the web
/// build has a symbol to resolve without pulling in the `dart:io` half.
Future<void> bootMobileApp() async {
  throw UnsupportedError('The Astrolok app is phone-only; the web build runs the site.');
}
