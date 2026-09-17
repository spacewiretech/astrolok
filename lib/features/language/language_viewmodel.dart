import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics_events.dart';
import '../../data/entitlement.dart';
import '../../data/providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../splash/splash_viewmodel.dart';

@immutable
class LanguageState {
  const LanguageState({this.selected, this.busy = false, this.error});

  /// The card showing the check. Set the moment it is tapped, before the save answers, so the
  /// tap reads as landing; cleared again if the save fails.
  final String? selected;

  final bool busy;
  final String? error;
}

/// The language picker between OTP and the paywall.
///
/// Saves through the same `update-profile` path Profile's picker uses, because the prompt is
/// assembled server-side: chat, palm and face all read `users.language` from there.
class LanguageViewModel extends AutoDisposeNotifier<LanguageState> {
  @override
  LanguageState build() => const LanguageState();

  /// Saves [language] and reports where the flow resumes, or null if it stays put.
  ///
  /// Also where signup ends. `Signup Completed` used to fire on the name, which now comes after
  /// payment — and the ad platforms optimise on registration happening before the purchase. This
  /// screen is only reachable while the account has no language, so it fires once per account.
  Future<SplashDestination?> choose(String language) async {
    if (state.busy) return null;
    state = LanguageState(selected: language, busy: true);

    final analytics = ref.read(analyticsProvider);
    analytics.track(Ev.languageSelected, {
      P.chatLanguage: language,
      P.source: 'onboarding',
    });

    try {
      final user = await ref.read(authRepositoryProvider).saveChatLanguage(language);
      ref.read(entitlementProvider.notifier).set(user);
      final destination = destinationForUser(user);
      state = LanguageState(selected: language);

      analytics.track(Ev.signupCompleted, {P.destination: destination.name});
      return destination;
    } catch (error) {
      debugPrint('[language] could not save $language: $error');
      state = const LanguageState(error: "Couldn't save your language. Please try again.");
      analytics.track(Ev.languageSaveFailed, {
        P.chatLanguage: language,
        P.error: error is OtpSendException ? error.message : error.toString(),
      });
      return null;
    }
  }
}

final languageViewModelProvider =
    AutoDisposeNotifierProvider<LanguageViewModel, LanguageState>(LanguageViewModel.new);
