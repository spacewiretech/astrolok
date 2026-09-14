import 'package:flutter/foundation.dart';

import 'referral_links.dart';

/// Where an install came from.
///
/// A value type with no behaviour beyond resolving itself, so the precedence rules below can be
/// unit-tested without a platform channel, a network or a clock.
@immutable
class Attribution {
  const Attribution({
    required this.source,
    required this.channel,
    this.campaign,
    this.campaignId,
    this.adset,
    this.ad,
    this.referralCode,
    this.params = const {},
  });

  /// `referral` | `meta` | `google_ads` | `paid_other` | `organic`.
  final String source;

  /// `install_referrer` | `manual_code` | `deep_link`.
  final String channel;

  final String? campaign;
  final String? campaignId;
  final String? adset;
  final String? ad;
  final String? referralCode;

  /// Everything the link or referrer string carried, kept whole and forwarded to the backend.
  ///
  /// The backend re-resolves from these rather than trusting [source]: it is the authority, and a
  /// client that has been tampered with must not be able to declare itself a referral. Keeping
  /// the raw parameters means a campaign field added later needs no app release to be recorded.
  final Map<String, String> params;

  bool get isReferral => referralCode != null;

  /// Identity of *what this says*, for deciding whether it has already been reported.
  ///
  /// Deliberately not `hashCode`: a hash collision here would silently skip a report, and the
  /// string is short enough that there is nothing to gain by shortening it.
  String get signature => '$source|$channel|$campaign|$campaignId|$adset|$ad|$referralCode';

  /// The nothing-known case. Not an error — most organic installs resolve to exactly this.
  static const organic = Attribution(source: 'organic', channel: 'web');

  Attribution copyWith({String? channel}) => Attribution(
        source: source,
        channel: channel ?? this.channel,
        campaign: campaign,
        campaignId: campaignId,
        adset: adset,
        ad: ad,
        referralCode: referralCode,
        params: params,
      );

  /// The super properties this attribution contributes to every subsequent event.
  ///
  /// Nulls are included and stripped by `registerSuper`, which already does that — spelling the
  /// conditionals out here would duplicate the rule and let the two drift.
  Map<String, Object?> get properties => {
        'acquisition_source': source,
        'acquisition_channel': channel,
        'campaign': campaign,
        'campaign_id': campaignId,
        'adset': adset,
        'ad': ad,
        'referral_code': referralCode,
        'is_referred': isReferral,
      };

  Map<String, Object?> toJson() => {
        'source': source,
        'channel': channel,
        'campaign': campaign,
        'campaign_id': campaignId,
        'adset': adset,
        'ad': ad,
        'referral_code': referralCode,
        'params': params,
      };

  static Attribution? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final source = raw['source'];
    final channel = raw['channel'];
    if (source is! String || channel is! String) return null;

    return Attribution(
      source: source,
      channel: channel,
      campaign: raw['campaign'] as String?,
      campaignId: raw['campaign_id'] as String?,
      adset: raw['adset'] as String?,
      ad: raw['ad'] as String?,
      referralCode: raw['referral_code'] as String?,
      params: {
        for (final entry in (raw['params'] as Map? ?? const {}).entries)
          entry.key.toString(): entry.value.toString(),
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Attribution &&
      other.source == source &&
      other.channel == channel &&
      other.campaign == campaign &&
      other.campaignId == campaignId &&
      other.adset == adset &&
      other.ad == ad &&
      other.referralCode == referralCode;

  @override
  int get hashCode =>
      Object.hash(source, channel, campaign, campaignId, adset, ad, referralCode);

  @override
  String toString() => 'Attribution($source/$channel, campaign: $campaign, '
      'code: $referralCode)';
}

/// Decides a source from whatever parameters survived the trip.
///
/// ## Precedence: referral > paid > organic
///
/// A referral code is an explicit, first-party statement that a named user sent this person, so it
/// outranks a campaign parameter that merely rode along on the same URL. Paid beats organic for
/// the opposite reason — `utm_medium=organic` is what the Play Store stamps on *every* store
/// visit, including one that began with an ad click, so treating it as authoritative would
/// quietly reclassify paid installs as free and make every campaign look unprofitable.
///
/// ## This is the client's copy, and it is not the authority
///
/// The same rules live in `supabase/functions/_shared/referral.ts`. Duplicating them is a drift
/// risk taken deliberately: the app needs a source *now*, for super properties on events fired
/// before there is a session to report anything with, and the alternative — waiting for the
/// backend — would leave the first launch's events, the denominator of every acquisition funnel,
/// unattributed. When `attribution-report` answers, its resolution overwrites this one.
Attribution resolveAttribution(
  Map<String, String> params, {
  required String channel,
  String? referralCode,
}) {
  String? get(String key) {
    final value = params[key]?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  final code = referralCode ?? normaliseReferralCode(get('ref_code') ?? get('ref'));
  final utmSource = (get('utm_source') ?? '').toLowerCase();
  final utmMedium = (get('utm_medium') ?? '').toLowerCase();

  final source = code != null
      ? 'referral'
      // `gclid` is Google's click id and appears on exactly one thing: a click on a Google ad.
      // The only unambiguous signal here, so it is tested first.
      : (get('gclid') != null || utmSource == 'adwords' || utmSource == 'google-ads')
          ? 'google_ads'
          // `fbclid` is the Meta equivalent; `apps.facebook.com` is what Meta stamps on the Play
          // Store referrer when a click routes through the store rather than a deep link.
          : (get('fbclid') != null ||
                  RegExp(r'facebook|instagram|^meta$|^ig$').hasMatch(utmSource))
              ? 'meta'
              // A paid medium with an unrecognised source is still paid. Better an honest
              // "paid, source unknown" than a false organic.
              : RegExp(r'^(cpc|ppc|paid|cpm|cpi)').hasMatch(utmMedium)
                  ? 'paid_other'
                  : 'organic';

  return Attribution(
    source: source,
    channel: channel,
    campaign: get('utm_campaign') ?? get('campaign'),
    campaignId: get('campaign_id') ?? get('utm_id'),
    adset: get('adset') ?? get('utm_adset') ?? get('utm_term'),
    ad: get('ad') ?? get('utm_ad') ?? get('utm_content'),
    referralCode: code,
    params: params,
  );
}

/// Flattens a URI's query into the map [resolveAttribution] expects.
Map<String, String> paramsFromUri(Uri uri) => {...uri.queryParameters};

/// The parameters that mean "this link came from a campaign".
///
/// An allowlist rather than "has any query at all", because the app already handles a link that
/// carries a query and is emphatically not an acquisition: the Cashfree return,
/// `astrolok://payment?sub=...`. Treating that as a campaign attributed every web-fallback
/// payment to an organic deep link and fired a referral event for it.
const _campaignParams = {
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_content',
  'utm_term',
  'utm_id',
  'campaign',
  'campaign_id',
  'adset',
  'ad',
  'gclid',
  'fbclid',
  'ref_code',
  'ref',
};

/// Whether any of [params] is something this app would attribute an install to.
bool hasCampaignParams(Map<String, String> params) => params.keys.any(
      (key) => _campaignParams.contains(key.toLowerCase()),
    );

/// Parses a Play Install Referrer string, which is a URL query without the URL.
///
/// Google hands back exactly what was in the store link's `referrer` parameter, percent-decoded
/// once. Our own invite links put `ref_code` in there, which is what makes a referral survive an
/// install with no app to open — deterministically, rather than as a guess.
Map<String, String> paramsFromReferrerString(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const {};
  try {
    return {...Uri.splitQueryString(raw)};
  } catch (_) {
    // A referrer string that is not a query at all. Some stores and some test harnesses send a
    // bare token; there is nothing to extract, and it must not take the launch down.
    return const {};
  }
}
