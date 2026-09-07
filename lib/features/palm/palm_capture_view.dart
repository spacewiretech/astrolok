import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/capture_frame.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/guide_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/step_indicator.dart';
import 'palm_capture_viewmodel.dart';
import 'palm_copy.dart';

/// Step one: frame a palm and send it to be read.
class PalmCaptureView extends ConsumerStatefulWidget {
  const PalmCaptureView({super.key});

  @override
  ConsumerState<PalmCaptureView> createState() => _PalmCaptureViewState();
}

class _PalmCaptureViewState extends ConsumerState<PalmCaptureView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deferred: starting the camera touches a provider, and doing that during the first build
    // throws "modified a provider while the widget tree was building".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(palmCaptureViewModelProvider.notifier).startCamera();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // Android releases the camera to whichever app is in front, so coming back from the
    // Settings app — or from any other camera — leaves a preview that never resumes.
    if (lifecycle == AppLifecycleState.resumed && mounted) {
      ref.read(palmCaptureViewModelProvider.notifier).startCamera();
    }
  }

  Future<void> _scan() async {
    final request = await ref.read(palmCaptureViewModelProvider.notifier).capture();
    if (!mounted || request == null) return;
    context.push(Routes.palmScan, extra: request);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(palmCaptureViewModelProvider);
    final model = ref.read(palmCaptureViewModelProvider.notifier);

    // The scan screen pops back here with a reason when the photo was not a palm. Shown as a
    // snackbar over a live viewfinder rather than an error panel, because the next thing the
    // user does is take another photo and the camera should already be waiting.
    ref.listen(palmRejectionProvider, (_, message) {
      if (message != null && mounted) showAppSnackBar(context, message, error: true);
    });

    // The day's allowance, reported by the scan screen. Recorded on the state so both buttons
    // close: until this existed, `PalmCaptureState.limitReached` was never set by anything, so
    // hitting the cap left the user on a "Try again" button that was certain to fail the same
    // way, for the rest of the day.
    ref.listen(palmLimitProvider, (_, message) {
      if (message != null) model.setLimitReached(message);
    });

    return Scaffold(
      body: AstralBackground(
        surface: AstralSurface.home,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppShape.gutter, 4, AppShape.gutter, 0),
                child: Row(
                  children: [
                    CircleIconButton(
                      image: PalmIcon.backCircle,
                      icon: Icons.chevron_left_rounded,
                      semanticLabel: 'Back',
                      onTap: () => context.canPop()
                          ? context.pop()
                          : context.go(Routes.home),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppShape.gutter + 12),
                child: const StepIndicator(labels: PalmCopy.steps, current: 0),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppShape.gutter,
                    24,
                    AppShape.gutter,
                    16,
                  ),
                  children: [
                    const AccentHeading(
                      lead: PalmCopy.captureTitleLead,
                      accent: PalmCopy.captureTitleAccent,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      PalmCopy.captureSubtitle,
                      style: AppText.body,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    Center(
                      child: FocusPicker(
                        focus: state.focus,
                        onChanged: model.setFocus,
                      ),
                    ),
                    const SizedBox(height: 20),

                    CaptureViewfinder(
                      cameraReady: state.cameraReady,
                      cameraFailure: state.cameraFailure,
                      previewAspectRatio: model.previewAspectRatio,
                      previewBuilder: model.preview,
                      framePrompt: PalmCopy.framePrompt,
                      copy: _cameraCopy,
                      onRetryPermission: model.startCamera,
                    ),
                    const SizedBox(height: 20),

                    if (state.limitReached != null)
                      ReadingNotice(message: state.limitReached!)
                    else if (state.error != null)
                      ReadingNotice(message: state.error!, danger: true),

                    if (state.limitReached != null || state.error != null)
                      const SizedBox(height: 16),

                    const Row(
                      children: [
                        Expanded(
                          child: GuideCard(
                            image: PalmIcon.tipLighting,
                            icon: Icons.wb_sunny_outlined,
                            label: PalmCopy.tipLighting,
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: GuideCard(
                            image: PalmIcon.tipOpenHand,
                            icon: Icons.back_hand_outlined,
                            label: PalmCopy.tipOpenHand,
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: GuideCard(
                            image: PalmIcon.tipSharpPhoto,
                            icon: Icons.photo_camera_outlined,
                            label: PalmCopy.tipSharpPhoto,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppShape.gutter,
                  0,
                  AppShape.gutter,
                  12,
                ),
                child: Column(
                  children: [
                    // Camera only. The face flow still offers a gallery upload; a palm does
                    // not, so on a device with no working camera this screen is a dead end by
                    // design rather than by oversight — which is why `cameraUnavailable` no
                    // longer offers a photo upload as the way out.
                    PrimaryButton(
                      label: PalmCopy.scanAction,
                      tone: ButtonTone.navy,
                      busy: state.busy,
                      onPressed: state.canCapture ? _scan : null,
                    ),
                    const SizedBox(height: 12),
                    const PrivacyNote(label: PalmCopy.privacyNote),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carries the "that wasn't a palm" message from the scan screen back to this one.
///
/// A one-shot provider rather than a route parameter: the message belongs to the moment, not
/// to the location, and putting it in the URL would resurrect it on a back-navigation.
final palmRejectionProvider = StateProvider<String?>((ref) => null);

/// Carries the daily allowance message back, so a second attempt is blocked here rather than
/// spending another round trip to be refused again.
final palmLimitProvider = StateProvider<String?>((ref) => null);

const _cameraCopy = CameraCopy(
  denied: PalmCopy.cameraDenied,
  deniedForever: PalmCopy.cameraDeniedForever,
  unavailable: PalmCopy.cameraUnavailable,
  allow: PalmCopy.allowCamera,
  openSettings: PalmCopy.openSettings,
);
