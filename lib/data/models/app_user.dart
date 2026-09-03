import 'package:flutter/foundation.dart';

/// Mirrors the `public.payment_status` enum. The database is the authority on the spelling.
enum PaymentType {
  trial,
  active,
  expired,
  cancelled;

  static PaymentType parse(Object? raw) {
    return switch (raw) {
      'active' => PaymentType.active,
      'expired' => PaymentType.expired,
      'cancelled' => PaymentType.cancelled,
      // Anything unrecognised — a value added server-side that this build predates — is treated
      // as trial, which grants nothing on its own. Failing towards the paywall is the safe way
      // to be wrong.
      _ => PaymentType.trial,
    };
  }
}

/// Why a live subscription is unhappy, when it is.
///
/// Separate from [PaymentType] on purpose. These states do not change whether the user is let
/// in — they are still fully entitled until the paid period runs out — but they are the only
/// warning anyone gets that it is about to stop. Folding them into [PaymentType] would mean the
/// parser's fallthrough revoked access from exactly the people being warned.
enum BillingState {
  /// The bank has suspended the mandate; renewals will not be collected until it is fixed.
  onHold,

  /// Paused, either by the user or by Cashfree.
  paused,

  /// A renewal failed and is being retried.
  dunning,

  /// A chargeback is open against one of their payments.
  disputed;

  static BillingState? parse(Object? value) => switch (value) {
        'on_hold' => BillingState.onHold,
        'paused' => BillingState.paused,
        'dunning' => BillingState.dunning,
        'disputed' => BillingState.disputed,
        _ => null,
      };

  /// What to tell the user, and what they can do about it.
  String get message => switch (this) {
        BillingState.onHold =>
          'Your UPI mandate is on hold, so the next payment will not go through. '
              'Re-authorise it in your UPI app to keep your readings.',
        BillingState.paused =>
          'Your subscription is paused. Renew it to keep your readings.',
        BillingState.dunning =>
          'The last payment did not go through. We will retry it shortly.',
        BillingState.disputed =>
          'There is a payment dispute open on your account. Contact support if this is '
              'unexpected.',
      };
}

@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.phone,
    this.name = '',
    this.birthDate,
    this.avatarUrl,
    this.paymentType = PaymentType.trial,
    this.trialEndsAt,
    this.currentPeriodEnd,
    this.entitled = false,
    this.billingState,
  });

  final String id;

  /// Ten digits without the country code, e.g. `9931145610`.
  final String phone;
  final String name;

  /// Date of birth, collected on the step after the name. Date only — no time, no place — so
  /// the time component is always midnight and must not be read as a birth time.
  final DateTime? birthDate;

  final String? avatarUrl;

  final PaymentType paymentType;

  /// When the paid trial runs out. Null until Cashfree captures the authorisation amount — a
  /// null here is what makes a brand new account land on the paywall rather than inside the app.
  final DateTime? trialEndsAt;

  /// End of the month covered by the last successful debit.
  final DateTime? currentPeriodEnd;

  /// Computed by the server. The client never decides this while it is online — see
  /// [recomputeOffline] for the one case where it has to derive the answer itself.
  final bool entitled;

  /// Set when the mandate needs attention. Null is the healthy case, and it never affects
  /// [entitled] — this is a warning, not a gate.
  final BillingState? billingState;

  bool get hasName => name.trim().isNotEmpty;

  bool get hasBirthDate => birthDate != null;

  /// Kept so the screens that only ask "can this user get in" read unchanged.
  bool get isSubscribed => entitled;

  /// True while inside the paid trial, so the paywall can tell a first-time subscriber apart
  /// from someone whose trial lapsed.
  bool get inTrial => paymentType == PaymentType.trial && entitled;

  /// False only for an account that has never authorised a mandate — the trial offer applies.
  bool get hasEverSubscribed => trialEndsAt != null || currentPeriodEnd != null;

  /// The instant access lapses if nothing else changes, before any grace.
  ///
  /// Used to schedule the mid-session re-check: a one-day trial will routinely run out while
  /// the app is open, and without this nothing would notice until the next cold start.
  DateTime? get entitlementExpiresAt => switch (paymentType) {
        PaymentType.trial => trialEndsAt,
        PaymentType.active || PaymentType.cancelled => currentPeriodEnd,
        PaymentType.expired => null,
      };

  /// Grace window matching `app_config.entitlement_grace_hours`.
  ///
  /// Only used offline. Circle 360 allows 12 hours here, which suits a two-day trial; on a
  /// one-day trial that would hand out a further 50% for free, so this is two hours. Still
  /// lenient enough that a paid-up user with no signal — who cannot reach the paywall to fix
  /// anything either — is not locked out over a brief outage.
  static const _offlineGrace = Duration(hours: 2);

  /// Re-derives [entitled] from the stored dates.
  ///
  /// A cached `entitled: true` is a fact about the moment it was written, not about now. Trust
  /// it as-is and a trial that ended overnight still opens the app until the network returns.
  AppUser recomputeOffline([DateTime? asOf]) {
    final now = asOf ?? DateTime.now();
    bool future(DateTime? at, Duration grace) =>
        at != null && now.isBefore(at.add(grace));

    final derived = switch (paymentType) {
      PaymentType.active =>
        currentPeriodEnd == null || future(currentPeriodEnd, _offlineGrace),
      PaymentType.trial => future(trialEndsAt, _offlineGrace),
      // No grace: a cancelled mandate has no in-flight debit to wait for.
      PaymentType.cancelled => future(currentPeriodEnd, Duration.zero),
      PaymentType.expired => false,
    };

    return derived == entitled ? this : copyWith(entitled: derived);
  }

  /// Parses the user object every Edge Function returns.
  ///
  /// Returns null rather than throwing on a malformed payload: a shape this build does not
  /// recognise must land the caller on sign-in, not crash the splash screen.
  static AppUser? fromServer(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['user_id'];
    if (id is! String) return null;

    return AppUser(
      id: id,
      phone: raw['mobile_no'] as String? ?? '',
      name: raw['name'] as String? ?? '',
      birthDate: parseBirthDate(raw['dob']),
      paymentType: PaymentType.parse(raw['payment_type']),
      trialEndsAt: _parseDate(raw['trial_ends_at']),
      currentPeriodEnd: _parseDate(raw['current_period_end']),
      entitled: raw['entitled'] == true,
      billingState: BillingState.parse(raw['billing_state']),
    );
  }

  /// `dob` is a Postgres `date`, so it arrives as a bare `YYYY-MM-DD` with no zone.
  ///
  /// Parsed without [DateTime.toLocal] on purpose: a birth date is a calendar fact, not an
  /// instant, and shifting it by a timezone offset is how a 1st becomes the 31st.
  static DateTime? parseBirthDate(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;

    final parsed = DateTime(year, month, day);
    // Rejects 31 February and friends: DateTime rolls those forward silently.
    if (parsed.year != year || parsed.month != month || parsed.day != day) return null;
    return parsed;
  }

  /// The wire format `update-profile` expects.
  static String formatBirthDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  AppUser copyWith({
    String? name,
    DateTime? birthDate,
    String? avatarUrl,
    PaymentType? paymentType,
    DateTime? trialEndsAt,
    DateTime? currentPeriodEnd,
    bool? entitled,
    BillingState? billingState,

    /// Explicit, because null is a meaningful value here — it means the mandate recovered.
    bool clearBillingState = false,
  }) {
    return AppUser(
      id: id,
      phone: phone,
      name: name ?? this.name,
      birthDate: birthDate ?? this.birthDate,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      paymentType: paymentType ?? this.paymentType,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      currentPeriodEnd: currentPeriodEnd ?? this.currentPeriodEnd,
      entitled: entitled ?? this.entitled,
      billingState: clearBillingState ? null : (billingState ?? this.billingState),
    );
  }
}
