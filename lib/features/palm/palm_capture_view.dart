import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/camera/palm_camera.dart';
import '../../data/models/palm_reading.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/guide_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/safe_asset.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/step_indicator.dart';
import 'palm_capture_state.dart';
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

  Future<void> _fromGallery() async {
    final request =
        await ref.read(palmCaptureViewModelProvider.notifier).pickFromGallery();
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
                      child: _FocusPicker(
                        focus: state.focus,
                        onChanged: model.setFocus,
                      ),
                    ),
                    const SizedBox(height: 20),

                    _Viewfinder(
                      state: state,
                      model: model,
                      onRetryPermission: model.startCamera,
                    ),
                    const SizedBox(height: 20),

                    if (state.limitReached != null)
                      _Notice(message: state.limitReached!)
                    else if (state.error != null)
                      _Notice(message: state.error!, danger: true),

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
                    PrimaryButton(
                      label: PalmCopy.scanAction,
                      tone: ButtonTone.navy,
                      busy: state.busy,
                      onPressed: state.canCapture ? _scan : null,
                    ),
                    // const SizedBox(height: 10),
                    // PrimaryButton(
                    //   label: PalmCopy.galleryAction,
                    //   tone: ButtonTone.outline,
                    //   onPressed:
                    //       state.busy || state.limitReached != null ? null : _fromGallery,
                    // ),
                    const SizedBox(height: 12),
                    const _PrivacyNote(),
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

/// The square live preview, or an explanation of why there isn't one.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({
    required this.state,
    required this.model,
    required this.onRetryPermission,
  });

  final PalmCaptureState state;
  final PalmCaptureViewModel model;
  final VoidCallback onRetryPermission;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppShape.card,
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (state.cameraReady)
                  // `cover` into a square box is what makes the centre-square crop in
                  // preparePalmImage match exactly what the user framed. The SizedBox gives
                  // the preview its true aspect ratio first; FittedBox then crops it to the
                  // square, which is the same geometry the crop assumes.
                  //
                  // The preview comes from the ViewModel rather than from the provider
                  // directly, so this is guaranteed to be the same camera instance the
                  // ViewModel initialised.
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: 100.0 * model.previewAspectRatio,
                      height: 100,
                      child: model.preview(),
                    ),
                  )
                else if (state.cameraFailure != null)
                  _CameraFallback(
                    failure: state.cameraFailure!,
                    onRetry: onRetryPermission,
                  )
                else
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  ),
                const IgnorePointer(child: _CornerBrackets()),
              ],
            ),
          ),
        ),
        // Overlaps the frame's lower edge, as in the design.
        Transform.translate(
          offset: const Offset(0, -22),
          child: DetectionPill(
            detected: false,
            label: PalmCopy.framePrompt,
          ),
        ),
      ],
    );
  }

}

/// The four gold corner marks over the preview.
class _CornerBrackets extends StatelessWidget {
  const _CornerBrackets();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: const Stack(
        children: [
          Align(alignment: Alignment.topLeft, child: _Bracket(corner: Alignment.topLeft)),
          Align(alignment: Alignment.topRight, child: _Bracket(corner: Alignment.topRight)),
          Align(
            alignment: Alignment.bottomLeft,
            child: _Bracket(corner: Alignment.bottomLeft),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: _Bracket(corner: Alignment.bottomRight),
          ),
        ],
      ),
    );
  }
}

class _Bracket extends StatelessWidget {
  const _Bracket({required this.corner});

  final Alignment corner;

  @override
  Widget build(BuildContext context) {
    const side = BorderSide(color: AppColors.gold, width: 3);
    final top = corner.y < 0;
    final left = corner.x < 0;

    return SizedBox(
      width: 34,
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: top ? side : BorderSide.none,
            bottom: top ? BorderSide.none : side,
            left: left ? side : BorderSide.none,
            right: left ? BorderSide.none : side,
          ),
          borderRadius: BorderRadius.only(
            topLeft: top && left ? const Radius.circular(10) : Radius.zero,
            topRight: top && !left ? const Radius.circular(10) : Radius.zero,
            bottomLeft: !top && left ? const Radius.circular(10) : Radius.zero,
            bottomRight: !top && !left ? const Radius.circular(10) : Radius.zero,
          ),
        ),
      ),
    );
  }
}

/// Shown in the viewfinder's place when there is no preview to give.
///
/// Deliberately looks like a designed state rather than an error: this is what every simulator
/// shows, and what a user who declined the permission sees every time they come back.
class _CameraFallback extends StatelessWidget {
  const _CameraFallback({required this.failure, required this.onRetry});

  final CameraFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = switch (failure) {
      CameraFailure.denied => PalmCopy.cameraDenied,
      CameraFailure.deniedForever => PalmCopy.cameraDeniedForever,
      CameraFailure.unavailable => PalmCopy.cameraUnavailable,
    };

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_camera_outlined, size: 44, color: AppColors.gold),
          const SizedBox(height: 14),
          Text(message, style: AppText.body, textAlign: TextAlign.center),
          if (failure != CameraFailure.unavailable) ...[
            const SizedBox(height: 18),
            GoldPillButton(
              label: failure == CameraFailure.deniedForever
                  ? PalmCopy.openSettings
                  : PalmCopy.allowCamera,
              compact: true,
              onPressed: () {
                if (failure == CameraFailure.deniedForever) {
                  launchUrl(Uri.parse('app-settings:'));
                } else {
                  onRetry();
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// The white pill that chooses what the reading concentrates on.
class _FocusPicker extends StatelessWidget {
  const _FocusPicker({required this.focus, required this.onChanged});

  final PalmFocus focus;
  final ValueChanged<PalmFocus> onChanged;

  @override
  Widget build(BuildContext context) {
    // A PopupMenuButton rather than a DropdownButton: the design's menu is a rounded card with
    // its own padding and tick, which Material's dropdown cannot be talked into producing.
    return PopupMenuButton<PalmFocus>(
      initialValue: focus,
      onSelected: onChanged,
      offset: const Offset(0, 52),
      color: AppColors.surface,
      elevation: 3,
      shape: const RoundedRectangleBorder(borderRadius: AppShape.card),
      itemBuilder: (context) => [
        for (final option in PalmFocus.values)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                Icon(option.icon, size: 18, color: option.color),
                const SizedBox(width: 10),
                Expanded(child: Text(option.label, style: AppText.meta)),
                if (option == focus)
                  const Icon(Icons.check_rounded, size: 18, color: AppColors.gold),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppShape.pill,
          border: Border.all(color: AppColors.border),
          boxShadow: const [AppColors.floatingShadow],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(focus.icon, size: 20, color: focus.color),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                focus.label,
                style: AppText.title.copyWith(fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.navy),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.danger = false});

  final String message;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tint = danger ? AppColors.danger : AppColors.gold;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: danger ? AppColors.danger.withValues(alpha: 0.06) : AppColors.cardSoft,
        borderRadius: AppShape.card,
        border: Border.all(color: tint.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: tint),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: AppText.meta)),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SafeImage(
          PalmIcon.shieldCheck,
          width: 16,
          height: 16,
          fit: BoxFit.contain,
          fallback: const Icon(Icons.verified_user_outlined, size: 16, color: AppColors.gold),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            PalmCopy.privacyNote,
            style: AppText.legal,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
