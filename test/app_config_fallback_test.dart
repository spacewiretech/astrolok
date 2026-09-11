import 'dart:convert';

import 'package:astrolok/app/env.dart';
import 'package:astrolok/data/repositories/app_config_repository.dart';
import 'package:astrolok/data/supabase/supabase_app_config_repository.dart';
// For `debugPrint`, which the two maxAge tests swap out: the repository logs only on the network
// path, so its silence is the proof that the cache was served without a fetch.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The four layers under a config read, and which one wins where.
///
/// ```
/// defaultAppConfig  <  Env (app.env)  <  disk cache  <  Supabase
/// ```
///
/// Env sits below the cache deliberately: the cache holds the last known *server* state, which
/// is fresher truth than a snapshot taken when the build was cut. Getting that order backwards
/// would have an offline install quietly revert to build-time prices after a price change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Points nowhere. Every test here either returns before the client is touched, or wants the
  /// fetch to fail — which is the whole point of a fallback layer.
  ///
  /// Built per test rather than once: the constructor opens an `HttpClient`, and Flutter's test
  /// binding only allows that inside a test zone.
  late SupabaseClient unreachable;

  setUp(() => unreachable = SupabaseClient('https://nonexistent.invalid', 'anon-key'));
  tearDown(Env.reset);

  void seedCache(Map<String, String> rows, {required bool fresh}) {
    SharedPreferences.setMockInitialValues({
      'astrolok.app_config': jsonEncode(rows),
      'astrolok.app_config_at': DateTime.now()
          .subtract(fresh ? const Duration(minutes: 5) : const Duration(days: 2))
          .millisecondsSinceEpoch,
    });
  }

  group('shippedAppConfig', () {
    test('is the compiled map alone when there is no env file', () {
      expect(shippedAppConfig, defaultAppConfig);
    });

    test('lets an env row override a compiled default', () {
      // The case that started this: production charges ₹499 while the compiled default still
      // says ₹249, and an offline first launch used to quote the wrong one.
      Env.loadForTest('plan_price_label=₹499');

      expect(shippedAppConfig['plan_price_label'], '₹499');
      expect(shippedAppConfig['trial_price_label'], defaultAppConfig['trial_price_label']);
    });

    test('carries keys the compiled map has never heard of', () {
      Env.loadForTest('palm_readings_per_day=10\nmixpanel_token=token');

      expect(defaultAppConfig.containsKey('palm_readings_per_day'), isFalse);
      expect(shippedAppConfig['palm_readings_per_day'], '10');
      expect(shippedAppConfig[mixpanelTokenKey], 'token');
    });
  });

  group('a fresh cache', () {
    test('beats env, and never reaches the client', () async {
      Env.loadForTest('plan_price_label=₹499\nenv=production');
      seedCache({'plan_price_label': '₹599'}, fresh: true);

      // Returning at all proves the client was untouched: `unreachable` has no DNS to resolve.
      final config = await SupabaseAppConfigRepository(unreachable).load();

      expect(config['plan_price_label'], '₹599', reason: 'the cache is fresher than the build');
      expect(config['env'], 'production', reason: 'env still fills what the cache lacks');
      expect(config['terms_url'], defaultAppConfig['terms_url']);
    });

    test('is asked again when the caller wants it fresher than the TTL', () async {
      // The bug this exists for: a row whose *value* changes in the dashboard — a language added
      // to `chat_languages` — is not a new key, so the one-shot absence refresh never fires and
      // the edit sat behind the six-hour TTL. Home passes a one-minute window instead.
      //
      // The cache is five minutes old, so it is fresh for the default TTL and stale for that
      // window. A failed fetch is what proves the fetch was attempted at all: `unreachable` has
      // no DNS, and only the network path logs.
      Env.loadForTest('env=production');
      seedCache({'chat_languages': 'Hinglish'}, fresh: true);

      final logs = <String>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      addTearDown(() => debugPrint = previous);

      final config = await SupabaseAppConfigRepository(unreachable)
          .load(maxAge: const Duration(minutes: 1));

      expect(
        logs.any((line) => line.contains('app_config fetch failed')),
        isTrue,
        reason: 'a cache older than maxAge must go to the server',
      );
      // And the stale cache still serves the answer, so a dead network costs nothing.
      expect(config['chat_languages'], 'Hinglish');
    });

    test('is left alone when it is younger than the window asked for', () async {
      // The other half: Home is every back-navigation's destination, so the window has to
      // actually collapse a burst of visits into one request.
      Env.loadForTest('env=production');
      seedCache({'chat_languages': 'Hinglish'}, fresh: true);

      final logs = <String>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      addTearDown(() => debugPrint = previous);

      await SupabaseAppConfigRepository(unreachable)
          .load(maxAge: const Duration(hours: 1));

      expect(logs, isEmpty, reason: 'the client should never have been touched');
    });

    test('reports only its own keys as remote', () {
      // What `analyticsBootstrapProvider` keys off. The env rows are not remote however many of
      // them there are, or the one-shot refresh stops firing the day app.env ships a token.
      Env.loadForTest('mixpanel_token=from-env\nfacebook_app_id=from-env');
      seedCache({'env': 'production'}, fresh: true);

      final repository = SupabaseAppConfigRepository(unreachable);

      return repository.load().then((_) {
        expect(repository.remoteKeys, {'env'});
        expect(repository.remoteKeys.contains(mixpanelTokenKey), isFalse);
      });
    });
  });

  group('a failed fetch', () {
    test('falls back to a stale cache over env', () async {
      Env.loadForTest('plan_price_label=₹499');
      seedCache({'plan_price_label': '₹599'}, fresh: false);

      final config = await SupabaseAppConfigRepository(unreachable).load();

      expect(config['plan_price_label'], '₹599');
    });

    test('falls back to env when there is no cache at all', () async {
      // The first launch offline. This used to land on `defaultAppConfig` and quote ₹249.
      SharedPreferences.setMockInitialValues({});
      Env.loadForTest('plan_price_label=₹499\npalm_readings_per_day=10');

      final config = await SupabaseAppConfigRepository(unreachable).load();

      expect(config['plan_price_label'], '₹499');
      expect(config['palm_readings_per_day'], '10');
      expect(config['terms_url'], defaultAppConfig['terms_url']);
    });
  });

  group('readCachedConfig, which boot reads before runApp', () {
    test('serves env rows when the cache is empty', () async {
      // A first launch can now start Mixpanel from app.env rather than buffering until the
      // fetched config arrives.
      SharedPreferences.setMockInitialValues({});
      Env.loadForTest('mixpanel_token=from-env');

      expect(await SupabaseAppConfigRepository.readCachedConfig(), {
        mixpanelTokenKey: 'from-env',
      });
    });

    test('lets the cache win over env', () async {
      seedCache({'mixpanel_token': 'from-cache'}, fresh: true);
      Env.loadForTest('mixpanel_token=from-env');

      final cached = await SupabaseAppConfigRepository.readCachedConfig();

      expect(cached[mixpanelTokenKey], 'from-cache');
    });

    test('still does not merge the compiled defaults', () async {
      // Unlike every other read path here. Boot's rule is that a *missing* `mixpanel_token`
      // means "no token, queue the events", and `defaultAppConfig` deliberately has no entry
      // for it — merging the map in would answer for `facebook_app_id` and silently start a
      // sink that should have stayed dormant.
      SharedPreferences.setMockInitialValues({});

      final cached = await SupabaseAppConfigRepository.readCachedConfig();

      expect(cached, isEmpty);
      expect(cached.containsKey(facebookAppIdKey), isFalse);
    });
  });

  group('FakeAppConfigRepository', () {
    test('serves the shipped config under its overrides', () async {
      Env.loadForTest('plan_price_label=₹499\nenv=production');

      final config = await const FakeAppConfigRepository({'env': 'staging'}).load();

      expect(config['env'], 'staging');
      expect(config['plan_price_label'], '₹499');
      expect(config['terms_url'], defaultAppConfig['terms_url']);
    });

    test('counts only its overrides as remote', () {
      expect(const FakeAppConfigRepository({'env': 'staging'}).remoteKeys, {'env'});
      expect(const FakeAppConfigRepository().remoteKeys, isEmpty);
    });
  });

  group('configList', () {
    test('splits a dashboard cell into a clean list', () {
      final config = {chatLanguagesKey: ' Hinglish , English ,, Hindi , hindi '};

      // Trimmed, blanks dropped, duplicates removed case-insensitively, order preserved — the
      // same rules `_shared/chat_language.ts` applies to the same row, because the picker and
      // the prompt must not disagree about which languages exist.
      expect(config.configList(chatLanguagesKey), ['Hinglish', 'English', 'Hindi']);
    });

    test('a blank row is an empty list, not the shipped default', () {
      // The opposite of configLink, deliberately. Blanking the cell is the documented off switch
      // for the language picker, so falling back here would make the switch do nothing.
      expect(<String, String>{chatLanguagesKey: ''}.configList(chatLanguagesKey), isEmpty);
      expect(<String, String>{chatLanguagesKey: ' , '}.configList(chatLanguagesKey), isEmpty);
    });

    test('a missing row falls through to the shipped default', () {
      // Absence is not the off switch — a cold start with no config must still offer a picker.
      expect(
        <String, String>{}.configList(chatLanguagesKey),
        ['Hinglish', 'English', 'Hindi'],
      );
    });
  });
}
