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
import 'face_capture_viewmodel.dart';
import 'face_copy.dart';

/// Step one: frame a face and send it to be read.
class FaceCaptureView extends ConsumerStatefulWidget {
  const FaceCaptureView({super.key});

  @override
  ConsumerState<FaceCaptureView> createState() => _FaceCaptureViewState();
}

class _FaceCaptureViewState extends ConsumerState<FaceCaptureView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deferred: starting the camera touches a provider, and doing that during the first build
    // throws "modified a provider while the widget tree was building".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(faceCaptureViewModelProvider.notifier).startCamera();
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
      ref.read(faceCaptureViewModelProvider.notifier).startCamera();
    }
  }

  Future<void> _scan() async {
    final request = await ref.read(faceCaptureViewModelProvider.notifier).capture();
    if (!mounted || request == null) return;
    context.push(Routes.faceScan, extra: request);
  }

  Future<void> _fromGallery() async {
    final request =
        await ref.read(faceCaptureViewModelProvider.notifier).pickFromGallery();
    if (!mounted || request == null) return;
    context.push(Routes.faceScan, extra: request);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(faceCaptureViewModelProvider);
    final model = ref.read(faceCaptureViewModelProvider.notifier);

    // The scan screen pops back here with a reason when the photo was not a face. Shown as a
    // snackbar over a live viewfinder rather than an error panel, because the next thing the
    // user does is take another photo and the camera should already be waiting.
    ref.listen(faceRejectionProvider, (_, message) {
      if (message != null && mounted) showAppSnackBar(context, message, error: true);
    });

    // The day's allowance. A standing notice rather than a snackbar: nothing the user does
    // today will change the answer, so it stays on screen and closes both buttons.
    ref.listen(faceLimitProvider, (_, message) {
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
                      onTap: () =>
                          context.canPop() ? context.pop() : context.go(Routes.home),
                    ),
                  ],
                ),
              ),
              // const SizedBox(height: 16),

              // const Padding(
              //   padding: EdgeInsets.symmetric(horizontal: AppShape.gutter + 12),
              //   child: StepIndicator(labels: FaceCopy.steps, current: 0),
              // ),

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
                      lead: FaceCopy.captureTitleLead,
                      accent: FaceCopy.captureTitleAccent,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      FaceCopy.captureSubtitle,
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
                      framePrompt: FaceCopy.framePrompt,
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
                            label: FaceCopy.tipLighting,
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: GuideCard(
                            // No exported glyph for "look straight"; the Material icon is the
                            // one the design's outline most closely matches.
                            image: null,
                            icon: Icons.center_focus_strong_outlined,
                            label: FaceCopy.tipLookStraight,
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: GuideCard(
                            image: PalmIcon.tipSharpPhoto,
                            icon: Icons.photo_camera_outlined,
                            label: FaceCopy.tipSharpPhoto,
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
                    PrimaryButton(
                      label: FaceCopy.takePhotoAction,
                      tone: ButtonTone.navy,
                      icon: Icons.photo_camera_outlined,
                      busy: state.busy,
                      onPressed: state.canCapture ? _scan : null,
                    ),
                    const SizedBox(height: 10),
                    PrimaryButton(
                      label: FaceCopy.galleryAction,
                      tone: ButtonTone.outline,
                      icon: Icons.image_outlined,
                      onPressed: state.canPickFromGallery ? _fromGallery : null,
                    ),
                    const SizedBox(height: 12),
                    const PrivacyNote(label: FaceCopy.privacyNote),
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

/// Carries the "that wasn't a face" message from the scan screen back to this one.
///
/// A one-shot provider rather than a route parameter: the message belongs to the moment, not
/// to the location, and putting it in the URL would resurrect it on a back-navigation.
final faceRejectionProvider = StateProvider<String?>((ref) => null);

/// Carries the daily allowance message back, so a second attempt is blocked here rather than
/// spending another round trip to be refused again.
final faceLimitProvider = StateProvider<String?>((ref) => null);

const _cameraCopy = CameraCopy(
  denied: FaceCopy.cameraDenied,
  deniedForever: FaceCopy.cameraDeniedForever,
  unavailable: FaceCopy.cameraUnavailable,
  allow: FaceCopy.allowCamera,
  openSettings: FaceCopy.openSettings,
);
