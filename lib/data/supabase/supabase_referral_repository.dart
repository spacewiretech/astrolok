import 'package:flutter/foundation.dart';

import '../attribution/attribution.dart';
import '../repositories/referral_repository.dart';
import 'edge_functions.dart';
import 'session_store.dart';

/// Referral and attribution against the Edge Functions.
///
/// Every method here is on a path the user is not waiting for — attribution resolves in the
/// background during a launch, and the invite screen is the only place a human is watching. So
/// nothing throws: a failure is reported as a value the caller can act on, and the caller's
/// options are always "try again later" or "give up", never "crash".
class SupabaseReferralRepository implements ReferralRepository {
  SupabaseReferralRepository(this._functions, this._sessions);

  final EdgeFunctions _functions;
  final SessionStore _sessions;

  @override
  Future<ReferralCode?> myCode() async {
    final token = await _sessions.readToken();
    if (token == null) return null;

    try {
      final data = await _functions.call('referral-code', bearerToken: token);
      if (data['enabled'] == false) return null;

      final code = data['code'] as String?;
      final link = data['link'] as String?;
      if (code == null || link == null) return null;

      return ReferralCode(
        code: code,
        link: link,
        invited: (data['invited'] as num?)?.toInt() ?? 0,
        converted: (data['converted'] as num?)?.toInt() ?? 0,
      );
    } catch (error) {
      debugPrint('[referral] could not fetch the invite code: $error');
      return null;
    }
  }

  @override
  Future<ReferralClaim> claim({
    String? code,
    required String attributionType,
  }) async {
    final token = await _sessions.readToken();
    // No session yet. Not a failure — the attribution service will try again once the user signs
    // in, which is the normal order of events for a referred install.
    if (token == null) return const ReferralClaim(ReferralClaimStatus.failed);

    try {
      final data = await _functions.call(
        'referral-claim',
        bearerToken: token,
        body: {
          'code': ?code,
          'attribution_type': attributionType,
        },
      );

      final status = switch (data['status']) {
        'created' => ReferralClaimStatus.created,
        'already_referred' => ReferralClaimStatus.alreadyReferred,
        'invalid_code' => ReferralClaimStatus.invalidCode,
        'self_referral' => ReferralClaimStatus.selfReferral,
        'not_eligible' => ReferralClaimStatus.notEligible,
        'no_attribution' => ReferralClaimStatus.noAttribution,
        'disabled' => ReferralClaimStatus.disabled,
        // An answer this build does not recognise. Treated as terminal rather than retryable:
        // a newer backend that added a status did so to say something final, and a client that
        // retried everything it did not understand would hammer it.
        _ => ReferralClaimStatus.notEligible,
      };

      return ReferralClaim(
        status,
        referredBy: data['referred_by'] as String?,
        code: data['code'] as String? ?? code,
      );
    } on EdgeError catch (error) {
      // `invalid_code` comes back as a structured error rather than a status, since the function
      // rejects a malformed code before it gets as far as a claim. Terminal either way.
      if (error.code == 'invalid_code') {
        return const ReferralClaim(ReferralClaimStatus.invalidCode);
      }
      // A rejected session is not retryable with the token we have, but it is not the referral's
      // business to sign anyone out — `currentUser()` owns that. Reported as failed so the claim
      // survives to be retried after the next sign-in.
      debugPrint('[referral] claim failed: $error');
      return const ReferralClaim(ReferralClaimStatus.failed);
    } catch (error) {
      debugPrint('[referral] claim failed: $error');
      return const ReferralClaim(ReferralClaimStatus.failed);
    }
  }

  @override
  Future<Attribution?> reportAttribution(Attribution attribution) async {
    final token = await _sessions.readToken();
    if (token == null) return null;

    try {
      final data = await _functions.call(
        'attribution-report',
        bearerToken: token,
        body: {
          'params': attribution.params,
          'channel': attribution.channel,
          'referral_code': ?attribution.referralCode,
        },
      );

      final source = data['acquisition_source'] as String?;
      if (source == null) return null;

      // The backend's resolution, not the one sent up. They agree in the ordinary case; where
      // they differ the backend is right, because it is the only side that cannot be tampered
      // with and the only side that can see the first touch already on record.
      return attribution.copyWith().sourceOverride(source);
    } catch (error) {
      debugPrint('[referral] could not report attribution: $error');
      return null;
    }
  }
}

extension on Attribution {
  /// Replaces the locally-guessed source with the backend's.
  ///
  /// A method rather than another `copyWith` parameter so that overriding the source is
  /// impossible to do by accident — it is the one field the client is explicitly not the
  /// authority on, and it should read as unusual at the call site.
  Attribution sourceOverride(String source) => Attribution(
        source: source,
        channel: channel,
        campaign: campaign,
        campaignId: campaignId,
        adset: adset,
        ad: ad,
        referralCode: referralCode,
        params: params,
      );
}
