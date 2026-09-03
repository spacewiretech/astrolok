import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../widgets/otp_field.dart';
import '../../widgets/phone_field.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/sheet_surface.dart';
import 'onboarding_state.dart';
import 'onboarding_viewmodel.dart';

/// Phone, OTP and name on one screen.
///
/// The three Figma frames share a layout: a hero that the user can swipe through pinned to the
/// top, and a sheet below it whose contents change as the flow advances. Building them as three
/// routes would rebuild — and so restart — the hero pager on every step.
///
/// UNSKINNED: the structure and behaviour are final, the visuals are placeholders until the
/// design exports land.
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

  int _heroPage = 0;

  /// Copy for the hero carousel. Replaced with the real artwork in Track B.
  static const _slides = [
    ('Read your palm', 'Point your camera and get a reading in seconds.'),
    ('Talk to an astrologer', 'Real astrologers, available around the clock.'),
    ('Your daily horoscope', 'Personalised to your birth chart, every morning.'),
  ];

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
      backgroundColor: AppColors.night,
      body: Column(
        children: [
          Expanded(child: _hero()),
          SheetSurface(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    // Keyed by step so the switcher animates between sheets rather than
                    // treating them as one widget that changed its children.
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The swipeable top half. Independent of the step, so it keeps its position as the sheet
  /// below it changes.
  Widget _hero() {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pager,
              itemCount: _slides.length,
              onPageChanged: (i) => setState(() => _heroPage = i),
              itemBuilder: (context, i) {
                final (title, subtitle) = _slides[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppShape.gutter),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: AppText.display.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: AppText.body.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _heroPage ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _heroPage ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneSheet(OnboardingState state) {
    final model = ref.read(onboardingViewModelProvider.notifier);

    return _Sheet(
      title: 'Enter your mobile number',
      subtitle: "We'll text you a code to confirm it's you.",
      error: state.error,
      children: [
        PhoneField(
          controller: _phone,
          onSubmitted: (_) => model.sendOtp(),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Continue',
          busy: state.busy,
          onPressed: state.canSendOtp ? model.sendOtp : null,
        ),
      ],
    );
  }

  Widget _otpSheet(OnboardingState state) {
    final model = ref.read(onboardingViewModelProvider.notifier);

    return _Sheet(
      title: 'Enter the code',
      subtitle: 'Sent to +91 ${state.phone}',
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
        const SizedBox(height: 16),
        _ResendRow(state: state),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Verify',
          busy: state.busy,
          onPressed: state.canVerify ? _verify : null,
        ),
        TextButton(
          onPressed: state.busy ? null : () => model.goTo(OnboardingStep.phone),
          child: Text('Change number', style: AppText.meta),
        ),
      ],
    );
  }

  Widget _nameSheet(OnboardingState state) {
    return _Sheet(
      title: 'What should we call you?',
      subtitle: 'Your readings are addressed to this name.',
      error: state.error,
      children: [
        TextFieldBox(
          controller: _name,
          hint: 'Your name',
          keyboardType: TextInputType.name,
          onSubmitted: (_) => _saveName(),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Continue',
          busy: state.busy,
          onPressed: state.canSaveName ? _saveName : null,
        ),
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

/// Shared frame for the three sheets: heading, body, error line.
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
        Text(title, style: AppText.display),
        const SizedBox(height: 6),
        Text(subtitle, style: AppText.meta),
        const SizedBox(height: 20),
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

/// Resend, its countdown, and the exhausted case.
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

    return TextButton(
      onPressed: state.canResend
          ? () {
              HapticFeedback.selectionClick();
              ref.read(onboardingViewModelProvider.notifier).resendOtp();
            }
          : null,
      child: Text(
        'Resend code',
        style: AppText.meta.copyWith(color: AppColors.brand),
      ),
    );
  }
}
