import 'package:flutter/foundation.dart';

import '../attribution/attribution.dart';

/// This user's invite code, and how it is doing.
@immutable
class ReferralCode {
  const ReferralCode({
    required this.code,
    required this.link,
    this.invited = 0,
    this.converted = 0,
  });

  final String code;

  /// The full shareable URL — the Play Store listing carrying this code in `referrer`, built
  /// by the backend so the listing can be corrected without a release.
  final String link;

  /// How many accounts this user has brought in, and how many of those went on to pay.
  ///
  /// Two numbers rather than one because the gap between them is the whole story of whether an
  /// invite is working: plenty of signups and no conversions is a completely different problem
  /// from no signups at all.
  final int invited;
  final int converted;
}

/// What the backend did with a claim.
///
/// Every value except [failed] is terminal — the client stops asking. That is the point: a claim
/// that will never succeed must not be retried forever, and the only case worth retrying is the
/// one where the backend was never reached.
enum ReferralClaimStatus {
  /// The relationship was created by this call.
  created,

  /// Someone already holds the claim on this user — an earlier attempt of this same call, or a
  /// different link. Not an error.
  alreadyReferred,

  /// The code names nobody.
  invalidCode,

  /// The user tried to refer themselves.
  selfReferral,

  /// Not a fresh signup — a reinstall, or an existing user who opened a friend's link.
  notEligible,

  /// Nothing to attribute: the install carried no referral code.
  noAttribution,

  /// Referrals are switched off server-side.
  disabled,

  /// The backend was not reached. The **only** status worth retrying.
  failed,
}

@immutable
class ReferralClaim {
  const ReferralClaim(this.status, {this.referredBy, this.code});

  final ReferralClaimStatus status;
  final String? referredBy;
  final String? code;

  /// Whether the client should stop trying, and forget what it was holding.
  ///
  /// [ReferralClaimStatus.failed] is the obvious exclusion — the backend was never reached, so
  /// nothing has been decided. [ReferralClaimStatus.disabled] is the less obvious one and was a
  /// bug on the first pass: referrals being switched off is a *temporary* state of the server, not
  /// a judgement about this user, and treating it as final meant a few minutes with the flag off
  /// silently discarded the pending referral of everyone who launched the app in that window.
  bool get isTerminal =>
      status != ReferralClaimStatus.failed && status != ReferralClaimStatus.disabled;
}

/// Referral and attribution calls.
///
/// Narrow on purpose, and every method must swallow its own failures — this sits on the launch
/// path, and attribution is never a good enough reason to fail a cold start.
abstract interface class ReferralRepository {
  /// The signed-in user's invite code, minting one if they have none. Null when referrals are
  /// disabled or the call failed.
  Future<ReferralCode?> myCode();

  /// Attributes this signed-in user to a referrer. Idempotent: safe to call any number of times
  /// with anything.
  Future<ReferralClaim> claim({
    String? code,
    required String attributionType,
  });

  /// Records where this user came from. Returns the backend's authoritative resolution, which
  /// overrides whatever the client worked out locally, or null if it could not be reached.
  Future<Attribution?> reportAttribution(Attribution attribution);
}

/// The implementation used wherever there is no backend to talk to.
///
/// The Fast2SMS and fake tiers have no `users` table, so there is nothing a referral could point
/// at. Returning "disabled" rather than throwing keeps the whole feature walkable on a fresh
/// checkout, exactly like the fake payment tier — the invite screen simply says it is unavailable
/// instead of the app failing to boot.
class NoopReferralRepository implements ReferralRepository {
  const NoopReferralRepository();

  @override
  Future<ReferralCode?> myCode() async => null;

  @override
  Future<ReferralClaim> claim({
    String? code,
    required String attributionType,
  }) async =>
      const ReferralClaim(ReferralClaimStatus.disabled);

  @override
  Future<Attribution?> reportAttribution(Attribution attribution) async => null;
}
