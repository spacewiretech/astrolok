import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/otp_field.dart';
import '../../widgets/phone_field.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/safe_asset.dart';
import '../../widgets/sheet_surface.dart';
import '../../widgets/terms_footer.dart';
import 'onboarding_state.dart';
import 'onboarding_viewmodel.dart';

/// Phone, OTP and name on one screen.
///
/// The three frames in the design share a layout: a hero the user can swipe through, pinned
/// above a sheet whose contents change as the flow advances. Building them as three routes
/// would rebuild — and so restart — the hero pager on every step.
class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key, this.initialStep = OnboardingStep.phone});

  final OnboardingStep initialStep;

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _otp = OtpFieldController();
  final _pager = PageController();

  /// Device-framed screenshots of the app's own screens. Decoration only — the hero slides
  /// independently of which step the sheet is showing.
  static const _hero = Img.onboardHero;

  /// Measured off the renders: the mockup starts 4% down the screen and is 63% of its width.
  static const _heroTop = 0.04;
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

      // Seeded from state, not the other way round, so returning to the phone sheet from the
      // OTP sheet shows the number the user already typed.
      final state = ref.read(onboardingViewModelProvider);
      _phone.text = state.phone;
      _name.text = state.name;

      _phone.addListener(() => model.setPhone(_phone.text));
      _name.addListener(() => model.setName(_name.text));
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _pager.dispose();
    super.dispose();
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
        // placed against the screen, so it is the same size on all three steps, and the sheet
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
      // Sized from the screen rather than from the space left over, so all three steps show
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
              OnboardingStep.name => _nameSheet(state),
            },
          ),
        ),
      ),
    );
  }

  Widget _phoneSheet(OnboardingState state) {
    final model = ref.read(onboardingViewModelProvider.notifier);

    return _Sheet(
      title: 'Enter your mobile number',
      subtitle: "We'll send you a code for secure access.",
      error: state.error,
      children: [
        PhoneField(controller: _phone, onSubmitted: (_) => model.sendOtp()),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'continue',
          busy: state.busy,
          onPressed: state.canSendOtp ? model.sendOtp : null,
        ),
        const SizedBox(height: 16),
        const TermsFooter(),
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
          // a wrong one still lands on the error path below.
          onCompleted: (_) => _verify(),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'continue',
          busy: state.busy,
          onPressed: state.canVerify ? _verify : null,
        ),
        const SizedBox(height: 12),
        _ResendRow(state: state),
      ],
    );
  }

  Widget _nameSheet(OnboardingState state) {
    return _Sheet(
      title: 'Enter your name',
      subtitle: 'This name will be displayed on your profile',
      error: state.error,
      children: [
        TextFieldBox(
          controller: _name,
          hint: 'Enter your name',
          keyboardType: TextInputType.name,
          onSubmitted: (_) => _saveName(),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'continue',
          busy: state.busy,
          onPressed: state.canSaveName ? _saveName : null,
        ),
        const SizedBox(height: 16),
        const TermsFooter(),
      ],
    );
  }

  Future<void> _verify() async {
    final next = await ref.read(onboardingViewModelProvider.notifier).verifyOtp();
    if (!mounted) return;
    // Null means the flow stayed here — a rejected code, or the name sheet taking over.
    if (next == null) {
      _otp.clear();
      return;
    }
    context.go(next.route);
  }

  Future<void> _saveName() async {
    final next = await ref.read(onboardingViewModelProvider.notifier).saveName();
    if (!mounted || next == null) return;
    context.go(next.route);
  }
}

/// Shared frame for the three sheets: centred heading, body, error line.
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
class _ResendRow extends ConsumerWidget {
  const _ResendRow({required this.state});

  final OnboardingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  ref.read(onboardingViewModelProvider.notifier).resendOtp();
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
