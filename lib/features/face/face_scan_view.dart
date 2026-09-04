import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/capture_frame.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/safe_asset.dart';
import '../../widgets/step_indicator.dart';
import 'face_capture_view.dart';
import 'face_capture_viewmodel.dart';
import 'face_copy.dart';
import 'face_scan_state.dart';
import 'face_scan_viewmodel.dart';

/// Step two: the photo is with the model, and this screen holds the wait.
///
/// Where the palm scan draws four chips around a rotating ring, this one follows its own
/// design: the photograph under a sweeping scan line, and a checklist that ticks off. The
/// checklist earns the difference — it names what is being looked at, which makes a ten-second
/// wait feel like work being done rather than a spinner.
class FaceScanView extends ConsumerStatefulWidget {
  const FaceScanView({super.key, required this.request});

  /// Null on a deep link or a hot restart, where the bytes never existed on this screen.
  final FaceScanRequest? request;

  @override
  ConsumerState<FaceScanView> createState() => _FaceScanViewState();
}

class _FaceScanViewState extends ConsumerState<FaceScanView>
    with TickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final request = widget.request;
      if (request == null) {
        // Nothing to read. `go`, not `pop`: there may be no stack to pop to.
        context.go(Routes.faceCapture);
        return;
      }
      _sweep.repeat(reverse: true);
      ref.read(faceScanViewModelProvider.notifier).start(request);
    });
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  void _handle(FaceScanOutcome outcome, FaceScanState state) {
    if (!mounted) return;

    switch (outcome) {
      case FaceScanOutcome.ready:
        final reading = state.reading;
        if (reading == null) return;
        context.pushReplacement(Routes.faceReadingFor(reading.id));

      case FaceScanOutcome.rejected:
        // Handed to the capture screen so the message lands over a live viewfinder, which is
        // where the user has to act on it.
        ref.read(faceRejectionProvider.notifier).state = state.error;
        context.pop();

      case FaceScanOutcome.limitReached:
        // Back to the capture screen too, but as a standing notice: nothing the user does
        // today will change the answer, so it stays on screen and closes the buttons.
        ref.read(faceLimitProvider.notifier).state = state.error;
        context.pop();

      case FaceScanOutcome.notEntitled:
        context.go(Routes.subscribe);

      case FaceScanOutcome.signedOut:
        context.go(Routes.onboarding);

      case FaceScanOutcome.failed:
        // Stays put. The retry card is rendered from state.
        break;
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppShape.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(FaceCopy.cancelTitle, style: AppText.sheetTitle),
              const SizedBox(height: 10),
              Text(
                FaceCopy.cancelBody,
                style: AppText.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              PrimaryButton(
                label: FaceCopy.cancelDismiss,
                tone: ButtonTone.navy,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: FaceCopy.cancelConfirm,
                tone: ButtonTone.outline,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
    );

    if ((leave ?? false) && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(faceScanViewModelProvider);

    ref.listen(faceScanViewModelProvider.select((s) => s.outcome), (_, outcome) {
      if (outcome != null) _handle(outcome, ref.read(faceScanViewModelProvider));
    });

    final failed = state.outcome == FaceScanOutcome.failed;

    return PopScope(
      // The reading is paid for and already in flight. An accidental edge-swipe must not
      // throw away something the user has been waiting ten seconds for.
      canPop: failed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        body: AstralBackground(
          surface: AstralSurface.home,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(AppShape.gutter, 4, AppShape.gutter, 0),
                  child: Row(
                    children: [
                      CircleIconButton(
                        image: PalmIcon.backCircle,
                        icon: Icons.chevron_left_rounded,
                        semanticLabel: 'Back',
                        onTap: failed ? () => context.pop() : _confirmLeave,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppShape.gutter + 12),
                  child: StepIndicator(labels: FaceCopy.steps, current: 1),
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
                        lead: FaceCopy.scanTitleLead,
                        accent: FaceCopy.scanTitleAccent,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        FaceCopy.scanSubtitle,
                        style: AppText.body,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      _ScanPreview(
                        image: widget.request?.image,
                        sweep: _sweep,
                        scanning: !failed && !state.complete,
                      ),
                      const SizedBox(height: 24),

                      if (failed)
                        _RetryCard(
                          message: state.error ?? FaceCopy.slowBody,
                          onRetry: () =>
                              ref.read(faceScanViewModelProvider.notifier).retry(),
                          onNewPhoto: () => context.pop(),
                        )
                      else ...[
                        _StageChecklist(state: state),
                        const SizedBox(height: 16),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            state.complete ? FaceCopy.scanFooter : state.statusLine,
                            key: ValueKey(state.complete ? '' : state.statusLine),
                            style: AppText.meta,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),
                      _FactCard(fact: state.fact),
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppShape.gutter,
                    0,
                    AppShape.gutter,
                    12,
                  ),
                  child: PrivacyNote(label: FaceCopy.privacyNote),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The photograph under a sweeping scan line, framed by the same gold brackets as the capture
/// screen so the two read as one flow.
class _ScanPreview extends StatelessWidget {
  const _ScanPreview({
    required this.image,
    required this.sweep,
    required this.scanning,
  });

  final Uint8List? image;
  final AnimationController sweep;

  /// The line stops once the reading has arrived or failed. A scanner still sweeping over a
  /// finished result is the screen contradicting itself.
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: AppShape.card,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image == null)
              const ColoredBox(color: AppColors.goldWash)
            else
              Image.memory(image!, fit: BoxFit.cover),

            if (scanning)
              AnimatedBuilder(
                animation: sweep,
                builder: (context, _) => Align(
                  alignment: Alignment(0, sweep.value * 2 - 1),
                  child: Container(
                    height: 26,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.gold.withValues(alpha: 0),
                          AppColors.gold.withValues(alpha: 0.75),
                          AppColors.gold.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            const IgnorePointer(child: CornerBrackets()),
          ],
        ),
      ),
    );
  }
}

/// The four rows the design ticks off while the model works.
class _StageChecklist extends StatelessWidget {
  const _StageChecklist({required this.state});

  final FaceScanState state;

  static const _rows = [
    (FaceCopy.stageShape, Icons.face_retouching_natural_outlined),
    (FaceCopy.stageEyes, Icons.remove_red_eye_outlined),
    (FaceCopy.stageMapping, Icons.center_focus_strong_outlined),
    (FaceCopy.stagePreparing, Icons.auto_awesome_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.border),
        boxShadow: const [AppColors.floatingShadow],
      ),
      child: Column(
        children: [
          for (final entry in _rows.asMap().entries) ...[
            if (entry.key > 0)
              const Divider(height: 1, thickness: 1, color: AppColors.divider),
            _StageRow(
              label: entry.value.$1,
              icon: entry.value.$2,
              done: entry.key < state.stagesDone,
              working: entry.key == state.stageInProgress,
            ),
          ],
        ],
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.icon,
    required this.done,
    required this.working,
  });

  final String label;
  final IconData icon;
  final bool done;
  final bool working;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.goldWash,
              borderRadius: AppShape.control,
            ),
            child: Icon(icon, size: 22, color: AppColors.goldDeep),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: AppText.title.copyWith(
                // A row still waiting its turn is dimmed, so the eye lands on the one that is
                // actually happening.
                color: done || working ? AppColors.heading : AppColors.muted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (done)
            SafeImage(
              PalmIcon.checkCircle,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              fallback: const Icon(
                Icons.check_circle_rounded,
                size: 24,
                color: AppColors.gold,
              ),
            )
          else if (working)
            Text(
              FaceCopy.stageInProgress,
              style: AppText.meta.copyWith(color: AppColors.goldDeep),
            ),
        ],
      ),
    );
  }
}

/// Shown in the checklist's place when the reading could not be finished.
///
/// Offers to re-send the photo already in memory. Sending the user back to the camera after a
/// long wait, to retake a photograph that was perfectly good, is the cruellest way this could
/// fail — so that is the second choice here, never the first.
class _RetryCard extends StatelessWidget {
  const _RetryCard({
    required this.message,
    required this.onRetry,
    required this.onNewPhoto,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onNewPhoto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(FaceCopy.slowTitle, style: AppText.title, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(message, style: AppText.meta, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          PrimaryButton(
            label: FaceCopy.tryAgain,
            tone: ButtonTone.navy,
            onPressed: onRetry,
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: FaceCopy.useAnotherPhoto,
            tone: ButtonTone.outline,
            onPressed: onNewPhoto,
          ),
        ],
      ),
    );
  }
}

class _FactCard extends StatelessWidget {
  const _FactCard({required this.fact});

  final String fact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.border),
        boxShadow: const [AppColors.floatingShadow],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafeImage(
            PalmIcon.bulbDisc,
            width: 40,
            height: 40,
            fit: BoxFit.contain,
            fallback: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.goldWash,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lightbulb_outline_rounded,
                size: 20,
                color: AppColors.goldDeep,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(FaceCopy.didYouKnow, style: AppText.title.copyWith(fontSize: 15)),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: Text(fact, key: ValueKey(fact), style: AppText.meta),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
