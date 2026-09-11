import 'dart:io';

import 'package:astrolok/app/env.dart';
import 'package:astrolok/data/repositories/app_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parses the real `assets/env/app.env`, when there is one.
///
/// Skipped on a checkout that has not made the file — it is gitignored, so CI and a fresh clone
/// both land there. Where it does run it is the only thing between a mistyped line and a
/// release: `app.env` is the layer the app falls back to when Supabase is unreachable, and every
/// way it can go quietly wrong (a `#` inside a URL, an empty value written `""`, a duplicated
/// key) produces a plausible-looking file that yields the wrong value at runtime.
void main() {
  final file = File('assets/env/app.env');
  final template = File('assets/env/app.env.example');

  tearDown(Env.reset);

  test('every key in app.env is also in the committed template', () {
    // The template is the only record of the file's shape for anyone who has not got one, so a
    // key that exists in only one of the two is a key nobody else knows to fill in.
    expect(_keysOf(template), _keysOf(file));
  }, skip: file.existsSync() ? null : 'assets/env/app.env is not present');

  group('the parsed app.env', () {
    setUp(() => Env.loadForTest(file.readAsStringSync()));

    test('supplies the four reserved values without leaking them into the config', () {
      expect(Env.hasSupabase, isTrue, reason: 'SUPABASE_URL and SUPABASE_ANON_KEY are both set');
      expect(Env.appConfigFallback.containsKey('SUPABASE_ANON_KEY'), isFalse);
      expect(Env.appConfigFallback.containsKey('FAST2SMS_API_KEY'), isFalse);
    });

    test('every key the client actually reads resolves to a usable value', () {
      // The list is every `app_config` key with a consumer in lib/. A typo in any of these is a
      // wrong price, a dead policy link or a silent analytics sink, none of which announce
      // themselves at build time.
      final config = shippedAppConfig;

      expect(config.configString('env'), isNotEmpty);
      expect(config.configString(mixpanelTokenKey), isNotEmpty);
      expect(config.configString(facebookAppIdKey), isNotEmpty);
      expect(config.configFlag(facebookEnabledKey), isTrue);
      expect(config.configDouble('trial_price_amount'), greaterThan(0));
      expect(config.configDouble('plan_price_amount'), greaterThan(0));
      expect(config.configString('currency_code'), 'INR');
      expect(config.configInt('cashfree_trial_days'), greaterThan(0));
      expect(config.configString('trial_price_label'), startsWith('₹'));
      expect(config.configString('plan_price_label'), startsWith('₹'));
    });

    test('every link opens something', () {
      // Both stores follow these at review time, and `configLink` can only save a link that is
      // missing or blank — not one that a stray `#` truncated into a 404.
      for (final key in ['privacy_url', 'terms_url', 'help_url']) {
        expect(Uri.tryParse(shippedAppConfig.configLink(key))?.isAbsolute, isTrue, reason: key);
        expect(shippedAppConfig.configLink(key), startsWith('https://'), reason: key);
      }

      // Launched verbatim whatever its scheme, so it is checked as a URI rather than as https.
      final support = Uri.tryParse(shippedAppConfig.configLink('support_url'));
      expect(support?.hasScheme, isTrue);
    });

    test('the paywall video URL survived the parser intact', () {
      // The longest value in the file and the likeliest to meet a hazard: it carries `%20`
      // escapes and a path, and a truncated one shows the static poster with no error anywhere.
      final url = shippedAppConfig.configString('paywall_video_url');

      expect(url, isNotEmpty);
      expect(url, startsWith('https://'));
      expect(url, endsWith('.mp4'), reason: 'a truncated URL loses its extension first');
    });

    test('no value looks like it was truncated or mis-quoted', () {
      // The two hazards `env_test.dart` pins in the abstract, checked against the real file.
      Env.appConfigFallback.forEach((key, value) {
        expect(value, isNot(startsWith('"')), reason: '$key: write an empty value bare');
        expect(value, isNot(startsWith("'")), reason: '$key: unbalanced quote');
        expect(value.trim(), value, reason: '$key: stray whitespace');
      });
    });
  }, skip: file.existsSync() ? null : 'assets/env/app.env is not present');
}

Set<String> _keysOf(File file) => file
    .readAsLinesSync()
    .map((line) => line.trim())
    .where((line) => !line.startsWith('#') && line.contains('='))
    .map((line) => line.split('=').first)
    .toSet();
