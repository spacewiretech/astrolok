import 'dart:math' as math;
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
import '../../widgets/circle_icon_button.dart';
import '../../widgets/guide_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/safe_asset.dart';
import '../../widgets/step_indicator.dart';
import 'palm_capture_view.dart';
import 'palm_capture_viewmodel.dart';
import 'palm_copy.dart';
import 'palm_scan_state.dart';
import 'palm_scan_viewmodel.dart';

/// Step two: the wait.
///
/// The reading takes ten seconds or so and there is nothing to report while it does, so this
/// screen's whole job is to make that time legible — a bar that moves honestly, four stages
/// that light in turn, and copy that changes often enough to be worth looking at.
class PalmScanView extends ConsumerStatefulWidget {
  const PalmScanView({super.key, required this.request});

  final PalmScanRequest? request;

  @override
  ConsumerState<PalmScanView> createState() => _PalmScanViewState();
}

class _PalmScanViewState extends ConsumerState<PalmScanView>
    with TickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();

    final request = widget.request;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (request == null) {
        // Deep-linked here with nothing to read, or hot-restarted mid-scan. There is nothing
        // to wait for, so go back and let them take a photo.
        if (mounted) context.go(Routes.palmCapture);
        return;
      }
      ref.read(palmScanViewModelProvider.notifier).start(request);
    });
  }

  @override
  void dispose() {
    _ring.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _handle(PalmScanOutcome outcome, PalmScanState state) {
    if (!mounted) return;

    switch (outcome) {
      case PalmScanOutcome.ready:
        final reading = state.reading;
        if (reading == null) return;
        context.pushReplacement(Routes.palmReadingFor(reading.id));

      case PalmScanOutcome.rejected:
        // Handed to the capture screen so the message lands over a live viewfinder, which is
        // where the user has to act on it.
        ref.read(palmRejectionProvider.notifier).state = state.error;
        context.pop();

      case PalmScanOutcome.limitReached:
        // Back to the capture screen too, but as a standing notice rather than a snackbar:
        // nothing the user does today will change the answer, so it has to stay on screen and
        // close the buttons rather than fade away and let them try again.
        ref.read(palmLimitProvider.notifier).state = state.error;
        context.pop();

      case PalmScanOutcome.notEntitled:
        context.go(Routes.subscribe);

      case PalmScanOutcome.signedOut:
        context.go(Routes.onboarding);

      case PalmScanOutcome.failed:
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
              Text(PalmCopy.cancelTitle, style: AppText.sheetTitle),
              const SizedBox(height: 10),
              Text(
                PalmCopy.cancelBody,
                style: AppText.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              PrimaryButton(
                label: PalmCopy.cancelDismiss,
                tone: ButtonTone.navy,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: PalmCopy.cancelConfirm,
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
    final state = ref.watch(palmScanViewModelProvider);

    ref.listen(palmScanViewModelProvider.select((s) => s.outcome), (_, outcome) {
      if (outcome != null) _handle(outcome, ref.read(palmScanViewModelProvider));
    });

    final failed = state.outcome == PalmScanOutcome.failed;

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

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppShape.gutter + 12),
                  child: const StepIndicator(labels: PalmCopy.steps, current: 1),
                ),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppShape.gutter,
                      24,
                      AppShape.gutter,
                      24,
                    ),
                    children: [
                      const AccentHeading(
                        lead: PalmCopy.scanTitleLead,
                        accent: PalmCopy.scanTitleAccent,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        PalmCopy.scanSubtitle,
                        style: AppText.body,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      _ScanStage(
                        state: state,
                        image: widget.request?.image,
                        ring: _ring,
                        pulse: _pulse,
                      ),
                      const SizedBox(height: 24),

                      if (failed)
                        _RetryCard(
                          message: state.error ?? PalmCopy.slowBody,
                          onRetry: () =>
                              ref.read(palmScanViewModelProvider.notifier).retry(),
                          onNewPhoto: () => context.pop(),
                        )
                      else
                        _Progress(state: state),

                      const SizedBox(height: 24),
                      _FactCard(fact: state.fact),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The hand, the rotating dashed ring, and the four stage chips at its corners.
class _ScanStage extends StatelessWidget {
  const _ScanStage({
    required this.state,
    required this.image,
    required this.ring,
    required this.pulse,
  });

  final PalmScanState state;
  final Uint8List? image;
  final AnimationController ring;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    final stage = state.stageIndex;
    final done = state.complete;

    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: AnimatedBuilder(
                animation: ring,
                builder: (context, child) => CustomPaint(
                  painter: _DashedRingPainter(turns: ring.value),
                  child: child,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: ClipOval(
                    child: image == null
                        ? const ColoredBox(color: AppColors.goldWash)
                        : Image.memory(image!, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          ),

          // The four chips, one per corner, matching the design's layout.
          for (final entry in _stages.asMap().entries)
            Align(
              alignment: switch (entry.key) {
                0 => Alignment.topLeft,
                1 => Alignment.topRight,
                2 => Alignment.bottomLeft,
                _ => Alignment.bottomRight,
              },
              child: FadeTransition(
                // Only the running stage breathes; the others sit still, so the eye is drawn
                // to what is actually happening.
                opacity: entry.key == stage && !done
                    ? Tween<double>(begin: 0.72, end: 1).animate(pulse)
                    : const AlwaysStoppedAnimation(1),
                child: SizedBox(
                  width: 104,
                  child: GuideCard(
                    image: entry.value.image,
                    icon: entry.value.icon,
                    label: entry.value.label,
                    tint: AppColors.gold,
                    active: entry.key == stage && !done,
                    done: done || entry.key < stage,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stage {
  const _Stage(this.label, this.icon, [this.image]);

  final String label;
  final IconData icon;
  final String? image;
}

const _stages = [
  _Stage(PalmCopy.stageDetecting, Icons.search_rounded, PalmIcon.scanDetect),
  _Stage(PalmCopy.stageTraits, Icons.psychology_outlined, PalmIcon.scanTraits),
  // No export for this one — the design uses a plain grid glyph.
  _Stage(PalmCopy.stagePatterns, Icons.grid_view_rounded),
  _Stage(PalmCopy.stageInsights, Icons.auto_awesome_rounded, PalmIcon.scanInsights),
];

/// The percentage, the bar, and the line that keeps changing.
class _Progress extends StatelessWidget {
  const _Progress({required this.state});

  final PalmScanState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '${state.percent}%',
          style: AppText.title.copyWith(fontSize: 18, color: AppColors.gold),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: AppShape.pill,
          child: TweenAnimationBuilder<double>(
            // Smooths the 100ms steps into a continuous crawl rather than a twitch.
            tween: Tween(begin: 0, end: state.progress),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: AppColors.goldWash,
              valueColor: const AlwaysStoppedAnimation(AppColors.gold),
            ),
          ),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            state.complete ? PalmCopy.scanFooter : state.statusLine,
            key: ValueKey(state.complete ? '' : state.statusLine),
            style: AppText.title.copyWith(fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// Shown in the bar's place when the reading could not be finished.
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
          Text(
            PalmCopy.slowTitle,
            style: AppText.title,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(message, style: AppText.meta, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          PrimaryButton(
            label: PalmCopy.tryAgain,
            tone: ButtonTone.navy,
            onPressed: onRetry,
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: PalmCopy.useAnotherPhoto,
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
                color: AppColors.gold,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(PalmCopy.didYouKnow, style: AppText.title.copyWith(fontSize: 15)),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Text(
                    fact,
                    key: ValueKey(fact),
                    style: AppText.meta,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The gold dashed circle behind the hand, turning slowly.
class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter({required this.turns});

  /// 0 to 1, one full revolution.
  final double turns;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    final paint = Paint()
      ..color = AppColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const dashes = 44;
    const sweep = 2 * math.pi / dashes;
    final offset = turns * 2 * math.pi;

    for (var i = 0; i < dashes; i++) {
      final start = offset + i * sweep;
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        start,
        // Slightly over half of each slot, so the gaps read as dashes rather than dots.
        sweep * 0.55,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => old.turns != turns;
}
