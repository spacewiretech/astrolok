import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/entitlement.dart';
import '../../data/models/app_user.dart';
import '../../data/providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../splash/splash_viewmodel.dart';
import 'onboarding_state.dart';

/// Drives phone → OTP → name inside the one onboarding screen.
///
/// The steps that end holding a user return the [SplashDestination] the flow resumes at rather
/// than a bare "it worked", because step order is not the same thing as where the user belongs:
/// someone who signs in again on a wiped device already has a name, a birth date and a live
/// trial, and must not be walked through those steps and dropped on the paywall. The ViewModel
/// itself still never touches the router.
class OnboardingViewModel extends Notifier<OnboardingState> {
  Timer? _ticker;

  /// Fields the user has begun filling, so "started typing" is reported once rather than on
  /// every keystroke. The drop-off between entering a number and submitting it is one of the
  /// larger leaks in this funnel, and it is invisible without the numerator.
  final Set<String> _fieldsStarted = {};

  /// When the current code was requested, for `seconds_to_verify`. Measured from the request
  /// rather than from the screen appearing, because the wait for the SMS is the part that
  /// actually loses people.
  DateTime? _otpRequestedAt;

  Analytics get _analytics => ref.read(analyticsProvider);

  @override
  OnboardingState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const OnboardingState();
  }

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  void _fieldStarted(String event) {
    if (!_fieldsStarted.add(event)) return;
    _analytics.track(event);
  }

  int get _secondsToVerify => _otpRequestedAt == null
      ? 0
      : DateTime.now().difference(_otpRequestedAt!).inSeconds;

  /// Restores the step the router asked for, e.g. a returning user resuming at the name sheet.
  void startAt(OnboardingStep step) {
    if (state.step == step) return;
    state = state.copyWith(step: step, clearError: true);
  }

  void goTo(OnboardingStep step) => state = state.copyWith(step: step, clearError: true);

  /// Changing the number invalidates any outstanding code, along with the attempt and resend
  /// budgets that went with it.
  void setPhone(String value) {
    if (value == state.phone) return;
    _fieldStarted(Ev.phoneEntryStarted);
    if (value.length == OnboardingState.phoneLength) {
      _fieldStarted(Ev.phoneNumberEntered);
    }
    _ticker?.cancel();
    state = state.copyWith(phone: value, clearError: true).clearingOtpSession();
  }

  void setCode(String value) {
    if (value.isNotEmpty) _fieldStarted(Ev.otpEntryStarted);
    state = state.copyWith(code: value, clearError: true);
  }

  void setName(String value) {
    if (value.isNotEmpty) _fieldStarted(Ev.nameEntryStarted);
    state = state.copyWith(name: value, clearError: true);
  }

  Future<bool> sendOtp() async {
    // Tracked before the guard, so a tap that the validator refused is still counted — a run of
    // `valid: false` is a broken phone field, and it would otherwise leave no trace at all.
    _analytics.track(Ev.otpRequested, {P.valid: state.canSendOtp});
    if (!state.canSendOtp) return false;

    final sent = await _guard(() async {
      await _auth.sendOtp(state.phone);
      return true;
    });
    if (sent ?? false) {
      _otpRequestedAt = DateTime.now();
      _startCooldown(resendsUsed: 0);
      goTo(OnboardingStep.otp);
    } else {
      _analytics.track(Ev.otpRequestFailed, {P.message: state.error});
    }
    return sent ?? false;
  }

  /// Asks the provider to redeliver. Resets the attempt budget on success, because a user who
  /// exhausted their tries on a stale code deserves a clean slate with the new one.
  Future<bool> resendOtp() async {
    if (!state.canResend) {
      // Why it was refused, which separates "the SMS never arrived and they are out of resends"
      // from "they tapped twice inside the cooldown". Only the first is a delivery problem.
      _analytics.track(Ev.otpResendBlocked, {
        P.reason: state.resendsUsed >= OnboardingState.maxResends ? 'exhausted' : 'cooldown',
        P.secondsRemaining: state.resendIn.inSeconds,
        P.resendsUsed: state.resendsUsed,
      });
      return false;
    }

    _analytics.track(Ev.otpResendRequested, {P.resendsUsed: state.resendsUsed});

    final sent = await _guard(() async {
      await _auth.resendOtp(state.phone);
      return true;
    });
    if (sent ?? false) {
      _otpRequestedAt = DateTime.now();
      state = state.copyWith(code: '', attemptsLeft: OnboardingState.maxAttempts);
      _startCooldown(resendsUsed: state.resendsUsed + 1);
    } else {
      _analytics.track(Ev.otpRequestFailed, {
        P.message: state.error,
        P.trigger: 'resend',
      });
    }
    return sent ?? false;
  }

  /// Handles its own failures rather than delegating to [_guard], because only a code the
  /// provider actually rejected may burn an attempt — a dropped connection must not.
  ///
  /// Returns null when the flow stays on this screen, either because the code was refused or
  /// because the user still has to give a name.
  Future<SplashDestination?> verifyOtp({String entryMethod = 'button'}) async {
    if (!state.canVerify) return null;

    final attemptsUsed = OnboardingState.maxAttempts - state.attemptsLeft + 1;
    _analytics.track(Ev.otpSubmitted, {
      // Whether the code was auto-filled from the SMS or typed. A flow where nobody auto-fills
      // is a flow where the SMS sender id is wrong, and that is invisible from the success rate.
      P.entryMethod: entryMethod,
      P.attemptsUsed: attemptsUsed,
      P.resendsUsed: state.resendsUsed,
    });

    state = state.copyWith(busy: true, clearError: true);

    try {
      final user = await _auth.verifyOtp(phone: state.phone, code: state.code);
      _ticker?.cancel();
      final destination = _destinationFor(user);
      state = state.copyWith(busy: false);

      _analytics.track(Ev.otpVerified, {
        P.entryMethod: entryMethod,
        P.attemptsUsed: attemptsUsed,
        P.resendsUsed: state.resendsUsed,
        // A returning user on a wiped device already has all of this, and must not be counted as
        // a signup. This is the property that separates the two.
        P.isNewUser: !user.hasName,
        P.hasName: user.hasName,
        P.hasBirthDate: user.hasBirthDate,
        P.entitled: user.entitled,
        P.destination: destination.name,
        P.secondsToVerify: _secondsToVerify,
      });

      // A first-time account has no name yet, and the name sheet is part of this same screen —
      // so that case is a step change here, not a route change for the view.
      if (destination == SplashDestination.name) {
        goTo(OnboardingStep.name);
        return null;
      }
      return destination;
    } on InvalidOtpException catch (e) {
      final left = state.attemptsLeft - 1;
      state = state.copyWith(
        busy: false,
        code: '',
        attemptsLeft: left,
        error: left <= 0
            ? 'Too many incorrect attempts. Tap resend to get a new code.'
            : '${e.message} $left attempt${left == 1 ? '' : 's'} left.',
      );
      _trackVerifyFailure('invalid', attemptsUsed, e.message);
      // The dead end. Everyone here has to resend or leave, and the split between those two is
      // the whole question — so it needs to be countable separately from a wrong digit.
      if (left <= 0) {
        _analytics.track(Ev.otpAttemptsExhausted, {P.resendsUsed: state.resendsUsed});
      }
      return null;
    } on OtpExpiredException catch (e) {
      // The code is gone, so spending an attempt on it would be unfair — unlock resend now.
      _ticker?.cancel();
      state = state.copyWith(busy: false, code: '', error: e.message, clearResendAt: true);
      _trackVerifyFailure('expired', attemptsUsed, e.message);
      return null;
    } on OtpSendException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      _trackVerifyFailure('send_failed', attemptsUsed, e.message);
      return null;
    } catch (error) {
      state = state.copyWith(busy: false, error: 'Something went wrong. Please try again.');
      _trackVerifyFailure('unknown', attemptsUsed, error.toString());
      return null;
    }
  }

  void _trackVerifyFailure(String reason, int attemptsUsed, String? message) {
    _analytics.track(Ev.otpVerificationFailed, {
      P.reason: reason,
      P.attemptsUsed: attemptsUsed,
      P.attemptsLeft: state.attemptsLeft,
      P.resendsUsed: state.resendsUsed,
      P.error: message,
      P.secondsToVerify: _secondsToVerify,
    });
  }

  Future<SplashDestination?> saveName() async {
    if (!state.canSaveName) return null;

    // The length rather than the name: it distinguishes a real name from a single character
    // someone typed to get past the sheet, without collecting the name itself as an event.
    _analytics.track(Ev.nameSubmitted, {P.nameLength: state.name.trim().length});

    final destination =
        await _guard(() async => _destinationFor(await _auth.saveName(state.name)));

    if (destination == null) {
      _analytics.track(Ev.nameSaveFailed, {P.message: state.error});
      return null;
    }

    // The end of onboarding proper, and the denominator of everything after it.
    _analytics.track(Ev.signupCompleted, {P.destination: destination.name});
    return destination;
  }

  /// Where the flow goes next for [user].
  ///
  /// Shares [destinationForUser] with the splash so a user who signs in again lands exactly
  /// where a cold start would have put them.
  SplashDestination _destinationFor(AppUser user) {
    ref.read(entitlementProvider.notifier).set(user);
    return destinationForUser(user);
  }

  /// Locks resend for the cooldown and ticks once a second so the countdown label moves.
  void _startCooldown({required int resendsUsed}) {
    _ticker?.cancel();
    state = state.copyWith(
      resendsUsed: resendsUsed,
      resendAvailableAt: DateTime.now().add(OnboardingState.resendCooldown),
      now: DateTime.now(),
    );

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      state = state.copyWith(now: DateTime.now());
      if (state.resendIn == Duration.zero) timer.cancel();
    });
  }

  /// Runs [action] with the busy flag set, turning a throw into [OnboardingState.error].
  ///
  /// Returns null when [action] threw, so a caller that produces a value can use null as its
  /// "did not get there" answer instead of carrying a second flag.
  Future<T?> _guard<T extends Object>(Future<T> Function() action) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await action();
      state = state.copyWith(busy: false);
      return result;
    } on InvalidOtpException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      return null;
    } on OtpExpiredException catch (e) {
      // The code is gone, so spending an attempt on it would be unfair — unlock resend now.
      state = state.copyWith(busy: false, error: e.message, code: '', clearResendAt: true);
      _ticker?.cancel();
      return null;
    } on OtpSendException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      return null;
    } catch (_) {
      state = state.copyWith(busy: false, error: 'Something went wrong. Please try again.');
      return null;
    }
  }
}

final onboardingViewModelProvider =
    NotifierProvider<OnboardingViewModel, OnboardingState>(OnboardingViewModel.new);
