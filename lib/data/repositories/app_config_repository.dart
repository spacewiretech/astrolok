import '../../app/env.dart';

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
  ///
  /// [maxAge] asks for a *fresher* cache than the six-hour default without going as far as
  /// [force]: the cache is used if it is younger than this, and the server asked otherwise.
  ///
  /// It exists because `force` and the default TTL between them cannot express the common case.
  /// A row whose **value** changes in the dashboard — a language added to `chat_languages`, a
  /// price corrected — is not a new key, so nothing triggers the one-shot refresh above, and the
  /// edit stays invisible to an installed app for up to six hours. Screens that promise a
  /// dashboard edit reaches users quickly pass a short window here.
  Future<Map<String, String>> load({bool force = false, Duration? maxAge});

  /// Keys the backend, or its disk cache, actually served on the most recent [load] — with the
  /// env rows and the compiled defaults excluded.
  ///
  /// `analyticsBootstrapProvider` has to ask this rather than test the merged map for a missing
  /// key. Its rule is that *absence* means "this install's cache predates the row", and the
  /// merged map now answers every key that ships in `app.env` whether the server knows it or
  /// not — which would silently retire the one-shot refresh that rule exists to trigger.
  Set<String> get remoteKeys;
}

/// Everything this build ships: the env rows over the compiled defaults.
///
/// The layer under the network, and the single base every read path merges onto, so the cache
/// path and the fetch path cannot disagree about what a missing key falls back to.
Map<String, String> get shippedAppConfig => {
      ...defaultAppConfig,
      ...Env.appConfigFallback,
    };

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

/// The languages Astro can reply in, comma-separated, and which one is the default.
///
/// Named constants because both are read in two places that must not drift — the Profile picker
/// and the forced refresh in `providers.dart` that exists so a language added in the dashboard
/// does not wait out a six-hour cache before anyone can pick it.
const chatLanguagesKey = 'chat_languages';
const chatLanguageDefaultKey = 'chat_language_default';

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
  // Which languages Astro can answer in, and which one a user who has never chosen gets. Read
  // with [AppConfigValues.configList]; the server keeps its own copy of this fallback, because
  // the prompt is assembled there and cannot ask the device what it thinks the list is.
  //
  // Defaulted rather than left blank so the picker works on a cold start. Blanking the row in
  // the dashboard is the off switch: an empty list hides the row entirely.
  chatLanguagesKey: 'Hinglish,English,Hindi',
  chatLanguageDefaultKey: 'Hinglish',
};

/// Typed reads over the raw key/value map, so a bad or missing value can never crash a screen.
///
/// Every fallback goes through [shippedAppConfig] rather than [defaultAppConfig] directly. The
/// map handed to these accessors is not always a fully merged one — the widget sites read
/// `appConfigProvider.valueOrNull ?? shippedAppConfig` and get the raw thing while the fetch is
/// still pending — so the env rows have to be reachable from here as well.
extension AppConfigValues on Map<String, String> {
  String configString(String key) => this[key] ?? shippedAppConfig[key] ?? '';

  int configInt(String key) =>
      int.tryParse(configString(key)) ??
      int.tryParse(shippedAppConfig[key] ?? '') ??
      0;

  bool configFlag(String key) => configString(key).toLowerCase() == 'true';

  double configDouble(String key) =>
      double.tryParse(configString(key)) ??
      double.tryParse(shippedAppConfig[key] ?? '') ??
      0;

  /// Like [configString], but a row that exists and is *blank* falls back to the shipped
  /// default as well.
  ///
  /// [configString] only covers a missing key. A link is different: one cleared cell in the
  /// dashboard would leave a row in the account menu that opens nothing, and a policy link
  /// that opens nothing is how a store review fails.
  String configLink(String key) {
    final value = configString(key).trim();
    return value.isEmpty ? (shippedAppConfig[key] ?? '') : value;
  }

  /// A comma-separated row, as a list. Trimmed, with blanks and duplicates dropped.
  ///
  /// The opposite of [configLink] on purpose: an empty result is a meaningful answer here, not a
  /// misconfiguration to paper over. Blanking `chat_languages` is the documented way to hide the
  /// language picker, so falling back to the shipped default would defeat the off switch.
  ///
  /// Comma-separated rather than JSON because every value in `app_config` is plain text with no
  /// type column, and a comma list is what someone can edit in a dashboard cell without quoting
  /// anything. `_shared/chat_language.ts` parses the same row the same way.
  List<String> configList(String key) {
    final seen = <String>{};
    final values = <String>[];

    for (final entry in configString(key).split(',')) {
      final value = entry.trim();
      if (value.isEmpty || !seen.add(value.toLowerCase())) continue;
      values.add(value);
    }

    return values;
  }
}
