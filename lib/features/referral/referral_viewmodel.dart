import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/providers.dart';

import 'referral_state.dart';

/// The invite screen.
///
/// Thin on purpose: the code is minted and counted by the backend, and nothing here decides
/// anything about a referral. Its whole job is to fetch a code, put it on a clipboard or into a
/// share sheet, and report that it happened.
class ReferralViewModel extends Notifier<ReferralState> {
  @override
  ReferralState build() {
    // Fetched on construction rather than from the view's initState, so a rebuild of the screen
    // does not refetch. Riverpod keeps the notifier alive across those.
    Future.microtask(load);
    return const ReferralState();
  }

  Analytics get _analytics => ref.read(analyticsProvider);

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);

    final code = await ref.read(referralRepositoryProvider).myCode();

    state = ReferralState(
      loading: false,
      code: code,
      // A null code is either "switched off" or "could not reach the backend", and the repository
      // deliberately does not distinguish them — both leave the user with nothing to share, and
      // an error that says which would be about us rather than about them.
      error: code == null ? 'Invites are not available right now. Please try again later.' : null,
    );
  }

  Future<void> copy() async {
    final code = state.code;
    if (code == null) return;

    await Clipboard.setData(ClipboardData(text: code.link));
    _analytics.track(Ev.inviteCodeCopied, {P.referralCode: code.code});

    state = state.copyWith(justCopied: true);
  }

  /// Clears the "Copied" confirmation once the view has shown it for long enough.
  void copyConfirmationShown() => state = state.copyWith(justCopied: false);

  Future<void> share() async {
    final code = state.code;
    if (code == null) return;

    // Unlike the two reading exports, which share a file and no text, this passes the link as
    // `text` — carrying the URL out of the app is the entire point of the screen.
    await SharePlus.instance.share(
      ShareParams(
        text: 'I am using Astrolok for palm and face readings. '
            'Try it with my invite: ${code.link}',
        subject: 'Try Astrolok',
      ),
    );

    // After the sheet returns, matching how the reading exports report theirs. The platform does
    // not reliably say which app was chosen — or whether one was — so this counts the intent to
    // share rather than a completed share, and is named accordingly.
    _analytics.track(Ev.inviteShared, {P.referralCode: code.code});
  }
}

final referralViewModelProvider =
    NotifierProvider<ReferralViewModel, ReferralState>(ReferralViewModel.new);
