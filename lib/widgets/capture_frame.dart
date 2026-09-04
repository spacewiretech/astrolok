import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/assets.dart';
import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';
import '../data/camera/reading_camera.dart';
import '../data/models/palm_reading.dart' show PalmFocus;
import 'primary_button.dart';
import 'safe_asset.dart';
import 'status_chip.dart';

/// The pieces both capture screens are built from.
///
/// These began as private widgets inside the palm capture screen and were lifted here when the
/// face flow arrived. Sharing them is not only about the duplication: the square viewfinder in
/// particular carries an invariant that `prepareReadingImage` depends on — a `cover` fit into a
/// **square** box is what makes a centre-square crop equal to what the user framed — and that
/// invariant is much easier to preserve in one widget than in two that look alike.

/// The words a capture screen puts on the camera-permission fallback.
///
/// Passed in rather than read from a copy class, so this file does not have to know which
/// feature it is rendering for. The two sets differ only in whether they say palm or face, but
/// telling someone the app needs the camera "to read your palm" on the face screen is exactly
/// the kind of small wrongness that makes an app feel unfinished.
class CameraCopy {
  const CameraCopy({
    required this.denied,
    required this.deniedForever,
    required this.unavailable,
    required this.allow,
    required this.openSettings,
  });

  final String denied;
  final String deniedForever;
  final String unavailable;
  final String allow;
  final String openSettings;
}

/// The square live preview, or an explanation of why there isn't one.
class CaptureViewfinder extends StatelessWidget {
  const CaptureViewfinder({
    super.key,
    required this.cameraReady,
    required this.cameraFailure,
    required this.previewAspectRatio,
    required this.previewBuilder,
    required this.framePrompt,
    required this.copy,
    required this.onRetryPermission,
  });

  final bool cameraReady;
  final CameraFailure? cameraFailure;
  final double previewAspectRatio;

  /// Built lazily and only when the camera is ready, so a screen whose camera never started
  /// never asks the plugin for a preview.
  ///
  /// It comes from the ViewModel rather than from the camera provider directly, so this is
  /// guaranteed to be the same camera instance the ViewModel initialised.
  final Widget Function() previewBuilder;

  final String framePrompt;
  final CameraCopy copy;
  final VoidCallback onRetryPermission;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          // Square, and it has to stay square: see the note at the top of this file and the
          // crop invariant in `reading_image.dart`.
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
                if (cameraReady)
                  // The SizedBox gives the preview its true aspect ratio first; FittedBox then
                  // crops it to the square, which is the same geometry the crop assumes.
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: 100.0 * previewAspectRatio,
                      height: 100,
                      child: previewBuilder(),
                    ),
                  )
                else if (cameraFailure != null)
                  CameraFallback(
                    failure: cameraFailure!,
                    copy: copy,
                    onRetry: onRetryPermission,
                  )
                else
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  ),
                const IgnorePointer(child: CornerBrackets()),
              ],
            ),
          ),
        ),
        // Overlaps the frame's lower edge, as in the design.
        Transform.translate(
          offset: const Offset(0, -22),
          child: DetectionPill(detected: false, label: framePrompt),
        ),
      ],
    );
  }
}

/// The four gold corner marks over the preview.
class CornerBrackets extends StatelessWidget {
  const CornerBrackets({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(14),
      child: Stack(
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
class CameraFallback extends StatelessWidget {
  const CameraFallback({
    super.key,
    required this.failure,
    required this.copy,
    required this.onRetry,
  });

  final CameraFailure failure;
  final CameraCopy copy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = switch (failure) {
      CameraFailure.denied => copy.denied,
      CameraFailure.deniedForever => copy.deniedForever,
      CameraFailure.unavailable => copy.unavailable,
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
                  ? copy.openSettings
                  : copy.allow,
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
class FocusPicker extends StatelessWidget {
  const FocusPicker({super.key, required this.focus, required this.onChanged});

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

/// A quiet inline message: the daily allowance, or something that just went wrong.
class ReadingNotice extends StatelessWidget {
  const ReadingNotice({super.key, required this.message, this.danger = false});

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

/// "Your images are private and secure".
///
/// True in the strong sense, which is why it is worth saying on both screens: the photograph
/// reaches the Edge Function, goes to the model and is dropped. There is no column and no
/// bucket on the server that could hold one.
class PrivacyNote extends StatelessWidget {
  const PrivacyNote({super.key, required this.label});

  final String label;

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
          child: Text(label, style: AppText.legal, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
