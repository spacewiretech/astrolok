/// Runtime configuration served from the backend rather than baked into the build.
///
/// Everything that is not a credential lives here — environment name, limits, paywall copy —
/// so it can be changed without shipping a new app version.
abstract interface class AppConfigRepository {
  /// [force] skips the disk cache and asks the server.
  ///
  /// For the one case the cache cannot serve: a key that did not exist when this install last
  /// cached, which is indistinguishable from a key the server does not have. Everything else
  /// should take the cache — the splash waits on this call.
  Future<Map<String, String>> load({bool force = false});
}

/// The Mixpanel project token, served as a config row rather than compiled in.
///
/// Deliberately absent from [defaultAppConfig]: no row means no token, no token means the app
/// runs on `NoopAnalytics`, and that is the correct behaviour for a checkout that has not been
/// pointed at a Mixpanel project. A default here would instead send every developer's traffic to
/// whichever project the constant named.
const mixpanelTokenKey = 'mixpanel_token';

/// Values the app falls back to when config has never been fetched and there is no network.
///
/// A cold start must never block on the network, so these have to be good enough to run on.
const defaultAppConfig = <String, String>{
  'env': 'production',
  'min_supported_version': '1.0.0',
  'otp_length': '6',
  'otp_expiry_minutes': '5',
  'otp_resend_cooldown_seconds': '30',
  // Paywall copy. The amounts actually charged come from the Cashfree plan and from private
  // config rows — these only decide what the screen says.
  'trial_price_label': '₹3',
  'plan_price_label': '₹249',
  'cashfree_trial_days': '1',
  // Marketing claims, deliberately empty. The paywall hides the rating row entirely while
  // these are blank rather than shipping a rating the app has not earned yet.
  'rating_label': '',
  'subscriber_label': '',
  // Empty until a video exists; the paywall shows a static poster instead.
  'paywall_video_url': '',
  // Support and legal links, opened from the account menu and the onboarding footer. Both
  // stores check these at review time, so a dead one fails a review — read them with
  // [AppConfigValues.configLink], which refuses to hand back a blank.
  //
  // `support_url` is launched verbatim, whatever its scheme, so support can move from an
  // inbox to a WhatsApp or help-desk link without an app release.
  'support_url': 'mailto:contact@astrolok.app?subject=Astrolok%20support',
  'help_url': 'https://astrolok.app/help',
  'privacy_url': 'https://astrolok.app/privacy',
  'terms_url': 'https://astrolok.app/terms',
};

/// Typed reads over the raw key/value map, so a bad or missing value can never crash a screen.
extension AppConfigValues on Map<String, String> {
  String configString(String key) => this[key] ?? defaultAppConfig[key] ?? '';

  int configInt(String key) =>
      int.tryParse(configString(key)) ??
      int.tryParse(defaultAppConfig[key] ?? '') ??
      0;

  bool configFlag(String key) => configString(key).toLowerCase() == 'true';

  /// Like [configString], but a row that exists and is *blank* falls back to the shipped
  /// default as well.
  ///
  /// [configString] only covers a missing key. A link is different: one cleared cell in the
  /// dashboard would leave a row in the account menu that opens nothing, and a policy link
  /// that opens nothing is how a store review fails.
  String configLink(String key) {
    final value = configString(key).trim();
    return value.isEmpty ? (defaultAppConfig[key] ?? '') : value;
  }
}
