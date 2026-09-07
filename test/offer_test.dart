import 'package:astrolok/data/fake/fake_session.dart';
import 'package:astrolok/data/fake/fake_subscription_repository.dart';
import 'package:astrolok/data/models/subscription_offer.dart';
import 'package:astrolok/data/repositories/app_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('defaultAppConfig', () {
    test('quotes the ₹3 trial and the ₹249 plan', () {
      expect(defaultAppConfig.configString('trial_price_label'), '₹3');
      expect(defaultAppConfig.configString('plan_price_label'), '₹249');
      expect(defaultAppConfig.configInt('cashfree_trial_days'), 1);
    });

    test('ships the marketing claims empty', () {
      // A launch build must not claim a rating or a subscriber count the app has not earned.
      // The paywall hides the whole row while these are blank.
      expect(defaultAppConfig.configString('rating_label'), isEmpty);
      expect(defaultAppConfig.configString('subscriber_label'), isEmpty);
      expect(defaultAppConfig.configString('paywall_video_url'), isEmpty);
    });

    test('a missing key falls back rather than returning a broken value', () {
      expect(<String, String>{}.configString('plan_price_label'), '₹249');
      expect(<String, String>{}.configInt('otp_length'), 6);
      expect(<String, String>{}.configString('nonsense'), isEmpty);
      expect(<String, String>{}.configInt('nonsense'), 0);
    });

    test('configInt survives a value that is not a number', () {
      expect({'cashfree_trial_days': 'soon'}.configInt('cashfree_trial_days'), 1);
    });

    test('configLink refuses to hand back a blank', () {
      // The case configString does not cover: the key is present, so it never reaches the
      // default, and the menu row would be left opening nothing. One cleared cell in the
      // Supabase dashboard is all it takes.
      expect({'terms_url': ''}.configLink('terms_url'), 'https://astrolok.app/terms');
      expect({'terms_url': '   '}.configLink('terms_url'), 'https://astrolok.app/terms');
      expect(<String, String>{}.configLink('help_url'), 'https://astrolok.app/help');
    });

    test('configLink prefers config and trims it', () {
      expect(
        {'privacy_url': '  https://example.com/privacy  '}.configLink('privacy_url'),
        'https://example.com/privacy',
      );
      // Any scheme: support is allowed to move off email without an app release.
      expect(
        {'support_url': 'https://wa.me/919000000000'}.configLink('support_url'),
        'https://wa.me/919000000000',
      );
    });

    test('the shipped links are URIs a phone can actually open', () {
      // A bare domain parses fine and then opens nothing, so scheme is the thing to assert.
      for (final key in ['help_url', 'privacy_url', 'terms_url']) {
        expect(Uri.parse(defaultAppConfig.configLink(key)).scheme, 'https', reason: key);
      }
      final support = Uri.parse(defaultAppConfig.configLink('support_url'));
      expect(support.scheme, 'mailto');
      // Encoded, not raw: a literal space in the subject fails to open on some devices.
      expect(defaultAppConfig.configLink('support_url'), isNot(contains(' ')));
    });
  });

  group('SubscriptionOffer', () {
    test('carries the monthly price as the strikethrough', () async {
      final offer = await FakeSubscriptionRepository(FakeSession.instance).offer();

      expect(offer.trialPrice, '₹3');
      expect(offer.planPrice, '₹249');
      // The paywall renders "₹̶2̶4̶9̶ ₹3" from these two.
      expect(offer.strikePrice, '₹249');
      expect(offer.trialDays, 1);
    });

    test('the consent line states the recurring amount and the cadence', () async {
      // UPI Autopay requires both before a mandate is authorised, so this is a compliance
      // string rather than marketing copy. The mockup has no such line.
      final offer = await FakeSubscriptionRepository(FakeSession.instance).offer();

      expect(offer.consent, contains('₹3'));
      expect(offer.consent, contains('₹249/month'));
      expect(offer.consent, contains('auto-debited'));
    });

    test('the trial length is pluralised', () {
      // "after 1 days" shipped on screen before this test existed. `contains('1 day')` did not
      // catch it, because that matches "1 days" too — hence the negative assertion.
      const one = SubscriptionOffer(trialPrice: '₹3', planPrice: '₹249', trialDays: 1);
      expect(one.consent, contains('after 1 day.'));
      expect(one.consent, isNot(contains('1 days')));

      const many = SubscriptionOffer(trialPrice: '₹3', planPrice: '₹249', trialDays: 3);
      expect(many.consent, contains('after 3 days.'));
    });
  });
}
