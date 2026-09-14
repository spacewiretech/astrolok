import 'package:astrolok/data/attribution/attribution.dart';
import 'package:astrolok/data/attribution/attribution_store.dart';
import 'package:astrolok/data/attribution/referral_links.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// Attribution: link parsing, source precedence, and the persistence that has to survive the
/// process being killed between resolving a referral and reporting it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('referral codes', () {
    test('a well-formed code survives normalisation unchanged', () {
      expect(normaliseReferralCode('ABCD2345'), 'ABCD2345');
    });

    test('case and punctuation carry no meaning', () {
      expect(normaliseReferralCode('  abcd-2345 '), 'ABCD2345');
    });

    test('the four ambiguous letters fold onto what was almost certainly meant', () {
      // Someone reading a code off a screenshot types I for 1 and O for 0. Rejecting them would
      // be technically correct and useless.
      expect(normaliseReferralCode('ILOU2345'), '110V2345');
    });

    test('anything that is not eight code characters is not a code', () {
      expect(normaliseReferralCode('ABCD234'), isNull);
      expect(normaliseReferralCode('ABCD23456'), isNull);
      expect(normaliseReferralCode(''), isNull);
      expect(normaliseReferralCode(null), isNull);
    });

    test('the Dart and Deno alphabets agree', () {
      // The same rule lives here, in `_shared/referral.ts` and in a CHECK constraint. A
      // disagreement shows up as a code the backend issues and the app refuses to open, so this
      // asserts the alphabet itself rather than a single example.
      expect(referralCodeAlphabet, '0123456789ABCDEFGHJKMNPQRSTVWXYZ');
      expect(referralCodeAlphabet.contains('I'), isFalse);
      expect(referralCodeAlphabet.contains('L'), isFalse);
      expect(referralCodeAlphabet.contains('O'), isFalse);
      expect(referralCodeAlphabet.contains('U'), isFalse);
    });
  });

  group('reading a code out of a link', () {
    test('the query form, which is how a code survives the Play Store', () {
      expect(
        referralCodeFromUri(Uri.parse('https://astrolok.app/?ref_code=ABCD2345')),
        'ABCD2345',
      );
      expect(referralCodeFromUri(Uri.parse('astrolok://open?ref=abcd2345')), 'ABCD2345');
    });

    test('a link with no code in it yields none', () {
      expect(referralCodeFromUri(Uri.parse('https://astrolok.app/privacy')), isNull);
      expect(referralCodeFromUri(Uri.parse('astrolok://payment?sub=abc')), isNull);
    });
  });

  group('what counts as a campaign link', () {
    test('the Cashfree return is not one', () {
      // The bug this exists to prevent: the guard used to be `params.isEmpty`, and
      // `astrolok://payment?sub=...` has a query — so every web-fallback payment fired a referral
      // event and overwrote last-touch attribution with an organic deep link.
      expect(
        hasCampaignParams(paramsFromUri(Uri.parse('astrolok://payment?sub=abc123'))),
        isFalse,
      );
    });

    test('a link with no query at all is not one either', () {
      expect(hasCampaignParams(paramsFromUri(Uri.parse('astrolok://open'))), isFalse);
    });

    test('anything genuinely campaign-shaped is', () {
      for (final query in const [
        '?utm_source=meta',
        '?utm_campaign=diwali',
        '?gclid=abc',
        '?fbclid=abc',
        '?ref_code=ABCD2345',
        '?ref=ABCD2345',
        '?UTM_SOURCE=meta',
      ]) {
        expect(
          hasCampaignParams(paramsFromUri(Uri.parse('astrolok://open$query'))),
          isTrue,
          reason: query,
        );
      }
    });
  });

  group('source precedence', () {
    test('a referral code outranks every campaign parameter on the same link', () {
      final result = resolveAttribution(
        const {'utm_source': 'facebook', 'fbclid': 'abc', 'gclid': 'xyz'},
        channel: 'install_referrer',
        referralCode: 'ABCD2345',
      );
      expect(result.source, 'referral');
      expect(result.isReferral, isTrue);
    });

    test('gclid alone is Google Ads', () {
      expect(
        resolveAttribution(const {'gclid': 'abc'}, channel: 'install_referrer').source,
        'google_ads',
      );
    });

    test('fbclid and the Meta sources are Meta', () {
      for (final params in const [
        {'fbclid': 'abc'},
        {'utm_source': 'facebook'},
        {'utm_source': 'Instagram'},
        {'utm_source': 'ig'},
      ]) {
        expect(
          resolveAttribution(params, channel: 'install_referrer').source,
          'meta',
          reason: '$params',
        );
      }
    });

    test('a paid medium with an unknown source is paid, never organic', () {
      // Being wrong towards organic would reclassify paid installs as free and make every
      // campaign look more profitable than it is.
      expect(
        resolveAttribution(
          const {'utm_source': 'somenetwork', 'utm_medium': 'cpc'},
          channel: 'web',
        ).source,
        'paid_other',
      );
    });

    test("the Play Store's own organic stamp resolves to organic", () {
      expect(
        resolveAttribution(
          const {'utm_source': 'google-play', 'utm_medium': 'organic'},
          channel: 'install_referrer',
        ).source,
        'organic',
      );
    });

    test('nothing at all is organic rather than an error', () {
      expect(resolveAttribution(const {}, channel: 'web').source, 'organic');
    });

    test('a code in the parameters is found without being passed separately', () {
      // The install-referrer path never passes a code explicitly; it arrives inside the query
      // string Google hands back.
      final result = resolveAttribution(
        const {'ref_code': 'ABCD2345', 'utm_source': 'referral'},
        channel: 'install_referrer',
      );
      expect(result.referralCode, 'ABCD2345');
      expect(result.source, 'referral');
    });
  });

  group('the Play referrer string', () {
    test('is parsed as the query it is', () {
      final params = paramsFromReferrerString(
        'utm_source=referral&utm_medium=invite&ref_code=ABCD2345',
      );
      expect(params['ref_code'], 'ABCD2345');
      expect(params['utm_medium'], 'invite');
    });

    test('a referrer that is not a query at all does not take the launch down', () {
      expect(paramsFromReferrerString(null), isEmpty);
      expect(paramsFromReferrerString(''), isEmpty);
      expect(paramsFromReferrerString('   '), isEmpty);
    });
  });

  group('super properties', () {
    test('carry the whole acquisition, including the referral flag', () {
      final properties = resolveAttribution(
        const {'utm_campaign': 'diwali', 'utm_id': '99'},
        channel: 'install_referrer',
        referralCode: 'ABCD2345',
      ).properties;

      expect(properties['acquisition_source'], 'referral');
      expect(properties['acquisition_channel'], 'install_referrer');
      expect(properties['campaign'], 'diwali');
      expect(properties['campaign_id'], '99');
      expect(properties['referral_code'], 'ABCD2345');
      expect(properties['is_referred'], isTrue);
    });
  });

  _adInstallTests();

  group('persistence', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    });

    test('a pending attribution survives being read back by a new store', () async {
      // Stands in for the process being killed between resolving a referral and claiming it —
      // which is routine here, since the UPI hand-off kills the app on every payment.
      final attribution = resolveAttribution(
        const {'utm_campaign': 'diwali'},
        channel: 'install_referrer',
        referralCode: 'ABCD2345',
      );

      await AttributionStore().writePending(attribution);

      final restored = await AttributionStore().readPending();
      expect(restored, isNotNull);
      expect(restored!.referralCode, 'ABCD2345');
      expect(restored.campaign, 'diwali');
      expect(restored.source, 'referral');
    });

    test('clearing a pending attribution actually clears it', () async {
      final store = AttributionStore();
      await store.writePending(Attribution.organic);
      await store.clearPending();
      expect(await store.readPending(), isNull);
    });

    test('first touch is recorded once and never replaced', () async {
      final store = AttributionStore();

      final first = resolveAttribution(
        const {'utm_campaign': 'launch'},
        channel: 'install_referrer',
        referralCode: 'AAAA1111',
      );
      final later = resolveAttribution(
        const {'utm_campaign': 'retargeting'},
        channel: 'manual_code',
        referralCode: 'BBBB2222',
      );

      expect(await store.recordFirstTouchIfAbsent(first), isTrue);
      // The value this whole design exists to protect: a later click must not re-attribute an
      // acquisition to the campaign that had the least to do with it.
      expect(await store.recordFirstTouchIfAbsent(later), isFalse);

      final stored = await store.readFirstTouch();
      expect(stored!.referralCode, 'AAAA1111');
      expect(stored.campaign, 'launch');
    });

    test('the one-shot flags latch, and latch across instances', () async {
      final store = AttributionStore();

      expect(await store.hasReadInstallReferrer(), isFalse);
      await store.markInstallReferrerRead();
      expect(await store.hasReadInstallReferrer(), isTrue);
      // The Play API returns the same string forever, so a second read would re-resolve an
      // attribution that cannot have changed.
      expect(await AttributionStore().hasReadInstallReferrer(), isTrue);

      expect(await store.isClaimSettled(), isFalse);
      await store.markClaimSettled();
      expect(await AttributionStore().isClaimSettled(), isTrue);

    });

    test('a corrupt payload reads as nothing known rather than throwing', () async {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData({
        'astrolok.attribution_pending': 'not json at all',
      });
      expect(await AttributionStore().readPending(), isNull);
    });

    test('storage that will not open does not take a launch down', () async {
      // No platform implementation at all, which is what a device with broken preferences looks
      // like from here. Every read must still answer.
      SharedPreferencesAsyncPlatform.instance = _BrokenPreferences();
      final store = AttributionStore();

      expect(await store.readPending(), isNull);
      expect(await store.readFirstTouch(), isNull);
      // Reported as "already done" rather than false, so a broken device does not retry the
      // install referrer and the deferred match on every single launch.
      expect(await store.hasReadInstallReferrer(), isTrue);

      // And the writes are swallowed rather than thrown.
      await store.writePending(Attribution.organic);
      await store.markClaimSettled();
    });
  });
}

/// A preferences platform where every call fails, standing in for storage that will not open.
final class _BrokenPreferences extends SharedPreferencesAsyncPlatform {
  Never _fail() => throw StateError('preferences unavailable');

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) => _fail();

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) => _fail();

  @override
  Future<double?> getDouble(String key, SharedPreferencesOptions options) => _fail();

  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) => _fail();

  @override
  Future<List<String>?> getStringList(String key, SharedPreferencesOptions options) => _fail();

  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) =>
      _fail();

  @override
  Future<Map<String, Object>> getPreferences(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) =>
      _fail();

  @override
  Future<void> setBool(String key, bool value, SharedPreferencesOptions options) => _fail();

  @override
  Future<void> setString(String key, String value, SharedPreferencesOptions options) => _fail();

  @override
  Future<void> setDouble(String key, double value, SharedPreferencesOptions options) => _fail();

  @override
  Future<void> setInt(String key, int value, SharedPreferencesOptions options) => _fail();

  @override
  Future<void> setStringList(
    String key,
    List<String> value,
    SharedPreferencesOptions options,
  ) =>
      _fail();

  @override
  Future<void> clear(ClearPreferencesParameters parameters, SharedPreferencesOptions options) =>
      _fail();
}

/// An ad install, end to end through the client half: what Google hands back out of the Play
/// Install Referrer, and what the app makes of it.
///
/// This is the flow a video ad produces — a store link carrying `referrer`, an install, then the
/// first launch reading it back. There is no referral code anywhere in it.
void _adInstallTests() {
  group('an ad install', () {
    test('a Meta campaign referrer resolves to meta with its campaign intact', () {
      final params = paramsFromReferrerString(
        'utm_source=meta&utm_medium=cpc&utm_campaign=diwali_video'
        '&utm_content=ad_a&utm_term=lookalike_2pc&fbclid=XYZ',
      );
      final result = resolveAttribution(params, channel: 'install_referrer');

      expect(result.source, 'meta');
      expect(result.campaign, 'diwali_video');
      expect(result.ad, 'ad_a');
      expect(result.adset, 'lookalike_2pc');
      // Nothing to claim: an ad install is not a referral, and the client must not call
      // referral-claim for it.
      expect(result.referralCode, isNull);
      expect(result.isReferral, isFalse);
    });

    test('a Google App campaign referrer resolves to google_ads', () {
      // Google sets this itself on an App campaign install; `gclid` is the only unambiguous
      // signal in the whole resolver.
      final params = paramsFromReferrerString(
        'utm_source=google-play&utm_medium=organic&gclid=ABC123',
      );
      expect(resolveAttribution(params, channel: 'install_referrer').source, 'google_ads');
    });

    test('a plain organic Play install stays organic', () {
      final params = paramsFromReferrerString('utm_source=google-play&utm_medium=organic');
      expect(resolveAttribution(params, channel: 'install_referrer').source, 'organic');
    });

    test('an ad referrer and a referral link cannot be confused', () {
      final ad = resolveAttribution(
        paramsFromReferrerString('utm_source=meta&utm_campaign=x'),
        channel: 'install_referrer',
      );
      final referral = resolveAttribution(
        paramsFromReferrerString('utm_source=referral&utm_medium=invite&ref_code=ABCD2345'),
        channel: 'install_referrer',
      );

      expect(ad.isReferral, isFalse);
      expect(referral.isReferral, isTrue);
      expect(referral.referralCode, 'ABCD2345');
    });
  });
}
