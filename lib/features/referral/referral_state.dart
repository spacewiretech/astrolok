import 'package:flutter/foundation.dart';

import '../../data/repositories/referral_repository.dart';

/// The invite screen, as it is on screen.
@immutable
class ReferralState {
  const ReferralState({
    this.loading = true,
    this.code,
    this.error,
    this.justCopied = false,
  });

  final bool loading;

  /// Null while loading, and also when referrals are switched off server-side or the backend
  /// could not be reached — [error] tells the two apart.
  final ReferralCode? code;

  final String? error;

  /// Drives the "Copied" confirmation on the code chip. Held in state rather than in the widget
  /// so that the view stays a pure function of it, which is the rule everywhere else here.
  final bool justCopied;

  bool get hasCode => code != null;

  ReferralState copyWith({
    bool? loading,
    ReferralCode? code,
    String? error,
    bool clearError = false,
    bool? justCopied,
  }) =>
      ReferralState(
        loading: loading ?? this.loading,
        code: code ?? this.code,
        error: clearError ? null : (error ?? this.error),
        justCopied: justCopied ?? this.justCopied,
      );
}
