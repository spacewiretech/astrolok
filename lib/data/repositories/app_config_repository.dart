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

/// The Facebook app the SDK reports conversions to, and the switch that silences it.
///
/// Unlike [mixpanelTokenKey] these are not the values the SDK initialises from — both native SDKs
/// read the App ID and Client Token out of the manifest and plist at process start, before Dart
/// runs. They are here so that reporting can be switched off, or pointed at a different Facebook
/// app during a campaign migration, without shipping a release. A blank [facebookAppIdKey] or a
/// false [facebookEnabledKey] leaves the sink dormant.
///
/// The Facebook **app secret** is deliberately absent, here and everywhere else in this repo. It
/// is a server-side Conversions API credential, the client SDK has no use for it, and
/// `app_config_secrets_stay_private` would refuse to publish it in any case.
const facebookAppIdKey = 'facebook_app_id';
const facebookEnabledKey = 'facebook_events_enabled';

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
  // The same two prices as numbers, for the ad networks. Facebook's Purchase event bids against
  // a value and a currency code, and neither can be had from the labels above without parsing a
  // rupee sign off marketing copy — which breaks the first time a label reads '₹3 only' or the
  // app is sold outside India.
  //
  // Still not authoritative for billing: what is actually charged comes from the Cashfree plan.
  // A wrong number here misreports ROAS to Facebook; it cannot take anybody's money.
  //
  // NOTE the deliberate disagreement with `plan_price_label` above. Production `app_config`
  // serves `plan_price_label = ₹499` and charges ₹499, while the default here still says ₹249 —
  // a stale default that predates a price rise and is pinned to the marketing site's copy by
  // `website_test.dart`. These amounts track what is *charged*, because an ad network told the
  // wrong number bids the wrong amount for every future customer. Correcting the label and the
  // site copy is a pricing decision, not a code fix, so it is left alone here.
  'trial_price_amount': '3',
  'plan_price_amount': '499',
  'currency_code': 'INR',
  // Blank by design, exactly as [mixpanelTokenKey] is absent by design: no app id means the
  // Facebook sink never starts, which is correct for any build not pointed at a Facebook app.
  facebookAppIdKey: '',
  facebookEnabledKey: 'true',
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

  double configDouble(String key) =>
      double.tryParse(configString(key)) ??
      double.tryParse(defaultAppConfig[key] ?? '') ??
      0;

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
