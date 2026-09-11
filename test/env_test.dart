import 'package:astrolok/app/env.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Env` had no coverage at all before the env file started carrying `app_config` rows: every
/// getter answered `''` in the suite and nothing asserted why. Now that a mistyped line in that
/// file can change what the paywall quotes, the parsing rules are worth pinning.
void main() {
  tearDown(Env.reset);

  group('the app_config mirror', () {
    test('the four reserved keys are not config rows', () {
      // They are Env's own, read through the getters. Leaking them into the config map would
      // publish the anon key and the Fast2SMS credentials into every screen's config.
      Env.loadForTest('''
SUPABASE_URL=https://example.supabase.co
SUPABASE_ANON_KEY=anon-key
FAST2SMS_API_KEY=sms-key
FAST2SMS_OTP_ID=template-id
otp_length=6
''');

      expect(Env.appConfigFallback, {'otp_length': '6'});
      expect(Env.supabaseUrl, 'https://example.supabase.co');
      expect(Env.hasSupabase, isTrue);
    });

    test('everything else is a config row, whatever its case', () {
      // The discriminator is the reserved list, not the casing, so `GEMINI_AI_KEY` — which is
      // uppercase in the table — travels as a config row like any other.
      Env.loadForTest('''
env=production
plan_price_label=₹499
GEMINI_AI_KEY=secret
''');

      expect(Env.appConfigFallback, {
        'env': 'production',
        'plan_price_label': '₹499',
        'GEMINI_AI_KEY': 'secret',
      });
    });

    test('a blank value is dropped rather than shadowing the compiled default', () {
      // A half-filled line must not be able to blank out a good default. `rating_label` is
      // blank in `defaultAppConfig` too, so nothing in the table needs env to force one.
      Env.loadForTest('''
rating_label=
subscriber_label=
palm_readings_per_day=10
''');

      expect(Env.appConfigFallback, {'palm_readings_per_day': '10'});
    });

    test('an unloaded Env yields no rows at all', () {
      // The state every test and every checkout without an app.env runs in: `shippedAppConfig`
      // has to collapse to `defaultAppConfig` exactly, or the suite starts depending on a
      // gitignored file.
      expect(Env.appConfigFallback, isEmpty);
      expect(Env.hasSupabase, isFalse);
    });
  });

  group('the parser hazards the template warns about', () {
    test('an unquoted # truncates the value, single quotes save it', () {
      // Documented rather than fixed: the fix lives in how the file is written. No value in the
      // table contains a `#` today, but the first URL fragment someone adds would lose its tail
      // silently, and silently is the problem.
      Env.loadForTest('''
bare_url=https://astrolok.app/help#faq
quoted_url='https://astrolok.app/help#faq'
''');

      expect(Env.appConfigFallback['bare_url'], 'https://astrolok.app/help');
      expect(Env.appConfigFallback['quoted_url'], 'https://astrolok.app/help#faq');
    });

    test('an empty value written as "" survives as two literal quote characters', () {
      // Which is why the template says to write `rating_label=` bare. The quote-stripping regex
      // needs a character between the quotes, so `""` never matches it — and the result is a
      // non-blank value that the drop-blanks rule cannot catch.
      Env.loadForTest('wrong=""\nright=\n');

      expect(Env.appConfigFallback['wrong'], '""');
      expect(Env.appConfigFallback.containsKey('right'), isFalse);
    });

    test('a URL query survives intact', () {
      // `support_url` is launched verbatim, whatever its scheme, so the `?`, `=` and `%` in it
      // all have to come back unmangled — an `=` in the value especially, since the parser
      // splits on the first one.
      Env.loadForTest('support_url=mailto:contact@astrolok.app?subject=Astrolok%20support');

      expect(
        Env.appConfigFallback['support_url'],
        'mailto:contact@astrolok.app?subject=Astrolok%20support',
      );
    });
  });

  group('the Fast2SMS fall-through', () {
    test('the app_config spelling is used when the reserved name is blank', () {
      // So that pasting the table in whole is enough, and the legacy direct-to-Fast2SMS tier
      // does not need the same two secrets written twice under different names.
      Env.loadForTest('''
FAST2SMS_API_KEY=
FAST2SMS_OTP_ID=
fast2sms_api_key=from-the-table
fast2sms_otp_id=7b9dae0672
''');

      expect(Env.fast2smsApiKey, 'from-the-table');
      expect(Env.fast2smsOtpId, '7b9dae0672');
      expect(Env.isConfigured, isTrue);
    });

    test('the reserved name wins when both are set', () {
      Env.loadForTest('''
FAST2SMS_API_KEY=reserved
fast2sms_api_key=from-the-table
''');

      expect(Env.fast2smsApiKey, 'reserved');
    });
  });
}
