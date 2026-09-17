import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/providers.dart';
import '../../data/repositories/app_config_repository.dart';
import '../../data/sms/sms_code_reader.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/otp_field.dart';
import '../../widgets/phone_field.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/safe_asset.dart';
import '../../widgets/sheet_surface.dart';
import '../../widgets/terms_footer.dart';
import 'onboarding_state.dart';
import 'onboarding_viewmodel.dart';

/// Phone and OTP on one screen.
///
/// The frames in the design share a layout: a hero the user can swipe through, pinned above a
/// sheet whose contents change as the flow advances. Building them as separate routes would
/// rebuild — and so restart — the hero pager on every step.
///
/// The name used to be a third sheet here. It now comes after payment, on the birth screen, so
/// verifying the code always leaves this screen.
class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key, this.initialStep = OnboardingStep.phone});

  final OnboardingStep initialStep;

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  final _phone = TextEditingController();
  final _otp = OtpFieldController();
  final _pager = PageController();

  /// Device-framed screenshots of the app's own screens. Decoration only — the hero slides
  /// independently of which step the sheet is showing.
  static const _hero = Img.onboardHero;

  /// Width measured off the renders, at 63% of the screen. The top offset started at the
  /// render's 4% and was nudged down by hand to sit better against the sheet.
  static const _heroTop = 0.1;
  static const _heroWidth = 0.63;

  /// The exports are ~542x1098, all device with no margin.
  static const _heroAspect = 542 / 1098;

  @override
  void initState() {
    super.initState();
    // Applied after the first frame: the router builds this widget during a navigation, and
    // mutating a provider mid-build is what "modified a provider while the widget tree was
    // building" reports.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final model = ref.read(onboardingViewModelProvider.notifier);
      model.startAt(widget.initialStep);

      // The paywall's promo clip, started two routes before the paywall. Opening a player is a
      // network round trip, and doing it when the paywall mounts is exactly what turns its video
      // card into a spinner on the screen that asks for money. Everything from here to the
      // language pick is lead time.
      //
      // `read`, not `watch`, the same way Home warms the conversation list: this screen has
      // nothing to redraw when the player lands, and the provider is kept alive, so the one read
      // outlives onboarding.
      ref.read(promoVideoProvider);

      // Seeded from state, not the other way round, so returning to the phone sheet from the
      // OTP sheet shows the number the user already typed.
      final state = ref.read(onboardingViewModelProvider);
      _phone.text = state.phone;

      _phone.addListener(() => model.setPhone(_phone.text));
    });
  }

  @override
  void dispose() {
    // Only when a listen ever started, which is also the only way [_smsReader] was ever read —
    // reading it for the first time here would go through `ref` after the widget is gone.
    if (_smsListen > 0) unawaited(_smsReader.cancel());
    _phone.dispose();
    _pager.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- SMS autofill

  /// Android's SMS reader, or a stand-in that never finds a code. Read on first use rather than in
  /// [initState], where the router is still building this widget.
  late final SmsCodeReader _smsReader = ref.read(smsCodeReaderProvider);

  /// Bumped by every new listen and every cancel. A result that arrives for an older value belongs
  /// to a code that is no longer the one on screen — a resend, or a different number — and filling
  /// it would auto-submit a stale code.
  int _smsListen = 0;

  /// How the code in the boxes got there, when it was read from the SMS rather than typed.
  String? _smsEntryMethod;

  /// Sends the code with a listener already running. Both Android APIs only see messages that
  /// arrive after listening starts, and a fast SMS can beat the OTP sheet onto the screen.
  Future<void> _sendOtp() async {
    _cancelSms();
    unawaited(_listenForSms());
    final sent = await ref.read(onboardingViewModelProvider.notifier).sendOtp();
    if (!sent) _cancelSms();
  }

  /// The same around a resend. The first listener may already have been used or declined, and the
  /// new message needs one of its own.
  Future<void> _resendOtp() async {
    _cancelSms();
    unawaited(_listenForSms());
    final sent = await ref.read(onboardingViewModelProvider.notifier).resendOtp();
    if (!sent) _cancelSms();
  }

  Future<void> _listenForSms() async {
    final reader = _smsReader;
    if (!reader.available) return;

    final listen = ++_smsListen;
    final config = ref.read(appConfigProvider).valueOrNull ?? shippedAppConfig;
    final retriever = config.configFlag(smsRetrieverEnabledKey);

    final sms = await reader.waitForCode(retriever: retriever);
    // Replaced or cancelled while it waited: this is not the code the sheet is asking for.
    if (!mounted || listen != _smsListen) return;

    final state = ref.read(onboardingViewModelProvider);
    // A code already typed in full, or one already being verified, is left alone. Overwriting it
    // mid-request would submit twice.
    final usable = sms != null &&
        state.step == OnboardingStep.otp &&
        !state.busy &&
        state.code.length < OnboardingState.otpLength;

    ref.read(analyticsProvider).track(Ev.otpAutofillResult, {
      P.method: retriever
          ? SmartAuthSmsCodeReader.retrieverMethod
          : SmartAuthSmsCodeReader.consentMethod,
      P.result: usable ? 'filled' : 'none',
    });

    if (!usable) return;
    _smsEntryMethod = sms.method;
    // Fires the field's onCompleted exactly as typing the last digit does, which verifies it.
    _otp.fill(sms.code);
  }

  void _cancelSms() {
    if (_smsListen == 0) return;
    _smsListen++;
    _smsEntryMethod = null;
    unawaited(_smsReader.cancel());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingViewModelProvider);

    return Scaffold(
      // The sheet grows when the keyboard opens rather than the whole screen sliding, which is
      // what keeps the hero from being shoved off the top.
      resizeToAvoidBottomInset: true,
      body: AstralBackground(
        surface: AstralSurface.onboarding,
        // A Stack, not a Column. Sizing the hero with Expanded made the mockup shrink to
        // whatever the sheet left over — 54% of the screen width against the render's 63%,
        // and different on each step as the sheet's content changed height. Here the mockup is
        // placed against the screen, so it is the same size on both steps, and the sheet
        // simply overlays whatever it needs.
        child: Stack(
          children: [
            Positioned(
              top: MediaQuery.sizeOf(context).height * _heroTop,
              left: 0,
              right: 0,
              child: _heroPager(),
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: _sheet(state)),
          ],
        ),
      ),
    );
  }

  /// The swipeable mockup. Independent of the step, so it keeps its size and position as the
  /// sheet below it changes.
  Widget _heroPager() {
    final width = MediaQuery.sizeOf(context).width * _heroWidth;

    return SizedBox(
      // Sized from the screen rather than from the space left over, so both steps show
      // the same mockup at the same scale.
      height: width / _heroAspect,
      child: PageView.builder(
        controller: _pager,
        itemCount: _hero.length,
        itemBuilder: (context, i) => Center(
          child: SizedBox(
            width: width,
            child: SafeImage(
              _hero[i],
              fit: BoxFit.contain,
              // Until every mockup is exported: the same framed shape, so the composition
              // reads correctly rather than as a blank band.
              fallback: const _HeroPlaceholder(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheet(OnboardingState state) {
    return SheetSurface(
      padding: const EdgeInsets.fromLTRB(
        AppShape.gutter,
        28,
        AppShape.gutter,
        20,
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          // Keyed by step so the switcher animates between sheets rather than treating them as
          // one widget that changed its children.
          child: KeyedSubtree(
            key: ValueKey(state.step),
            child: switch (state.step) {
              OnboardingStep.phone => _phoneSheet(state),
              OnboardingStep.otp => _otpSheet(state),
            },
          ),
        ),
      ),
    );
  }

  /// The phone sheet ends with the terms, and their links come from config so a policy URL can
  /// be corrected without an app release. Defaults stand in until config resolves.
  Widget get _termsFooter {
    final config = ref.watch(appConfigProvider).valueOrNull ?? shippedAppConfig;
    return TermsFooter(
      termsUrl: config.configLink('terms_url'),
      privacyUrl: config.configLink('privacy_url'),
    );
  }

  Widget _phoneSheet(OnboardingState state) {
    return _Sheet(
      title: 'Enter your mobile number',
      subtitle: "We'll send you a code for secure access.",
      error: state.error,
      children: [
        PhoneField(controller: _phone, onSubmitted: (_) => _sendOtp()),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'continue',
          busy: state.busy,
          onPressed: state.canSendOtp ? _sendOtp : null,
        ),
        const SizedBox(height: 16),
        _termsFooter,
      ],
    );
  }

  Widget _otpSheet(OnboardingState state) {
    final model = ref.read(onboardingViewModelProvider.notifier);

    return _Sheet(
      title: 'Enter verification code',
      subtitle: 'Enter the code sent to your mobile number\n+91 ${state.phone}',
      error: state.error,
      children: [
        OtpField(
          length: OnboardingState.otpLength,
          controller: _otp,
          onChanged: model.setCode,
          // Auto-submitting on the last digit is what makes an autofilled code feel instant;
          // a wrong one still lands on the error path below. The entry method says whether the
          // digits came from the SMS reader or from the keyboard.
          onCompleted: (_) {
            final entryMethod = _smsEntryMethod ?? 'auto_complete';
            _smsEntryMethod = null;
            _verify(entryMethod: entryMethod);
          },
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'continue',
          busy: state.busy,
          onPressed: state.canVerify ? _verify : null,
        ),
        const SizedBox(height: 12),
        _ResendRow(state: state, onResend: _resendOtp),
      ],
    );
  }

  /// [entryMethod] separates a code the OS auto-filled from the SMS from one the user typed.
  /// Only the view knows which happened, and the difference is how the SMS sender id is doing.
  Future<void> _verify({String entryMethod = 'button'}) async {
    final next = await ref
        .read(onboardingViewModelProvider.notifier)
        .verifyOtp(entryMethod: entryMethod);
    if (!mounted) return;

    // Null means the flow stayed here — a rejected code.
    if (next == null) {
      _otp.clear();
      return;
    }

    // Verified: nothing is waiting for a code any more, and a listener left running would still
    // put Android's consent sheet up over the next screen.
    _cancelSms();
    context.go(next.route);
  }
}

/// Shared frame for the two sheets: centred heading, body, error line.
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.title,
    required this.subtitle,
    required this.children,
    this.error,
  });

  final String title;
  final String subtitle;
  final String? error;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppText.sheetTitle, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(subtitle, style: AppText.body, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ...children,
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: AppText.meta.copyWith(color: AppColors.danger),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// "Didn't get the code? Resend", its countdown, and the exhausted case.
///
/// The resend goes through [onResend] rather than straight to the view model, because the screen
/// restarts the SMS listener around it: a new message needs a listener of its own.
class _ResendRow extends StatelessWidget {
  const _ResendRow({required this.state, required this.onResend});

  final OnboardingState state;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    if (state.resendExhausted) {
      return Text(
        'No more codes can be sent right now. Please try again later.',
        style: AppText.meta,
        textAlign: TextAlign.center,
      );
    }

    if (state.resendIn > Duration.zero) {
      return Text(
        'Resend code in ${state.resendCountdownLabel}',
        style: AppText.meta,
        textAlign: TextAlign.center,
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text("Didn't get the code? ", style: AppText.meta),
        GestureDetector(
          onTap: state.canResend
              ? () {
                  HapticFeedback.selectionClick();
                  onResend();
                }
              : null,
          child: Text(
            'Resend',
            style: AppText.meta.copyWith(
              color: AppColors.gold,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.gold,
            ),
          ),
        ),
      ],
    );
  }
}

/// Stands in for the device-framed mockups until they are exported.
class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.62,
        heightFactor: 0.9,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: AppColors.navy.withValues(alpha: 0.35), width: 6),
          ),
          alignment: Alignment.center,
          child: const ZodiacRing(diameter: 150),
        ),
      ),
    );
  }
}
