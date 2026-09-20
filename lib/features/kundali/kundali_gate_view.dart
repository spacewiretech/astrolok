import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../data/kundali_summary.dart';
import '../../data/models/kundali.dart';
import '../../widgets/astral_background.dart';

/// `/kundali`: decides between the form, the wait and the reveal, then replaces itself.
///
/// What a push opens, and where anything that does not already know the kundali's state sends the
/// user. It always asks the server first — a push saying "ready" is exactly the moment the cached
/// summary is most likely to be out of date.
class KundaliGateView extends ConsumerStatefulWidget {
  const KundaliGateView({super.key});

  /// The screen for a summary, or the form when there is none.
  static String routeFor(KundaliSummary? summary) => switch (summary?.state) {
        null => Routes.kundaliNew,
        KundaliState.ready => Routes.kundaliReport,
        _ => Routes.kundaliWaiting,
      };

  @override
  ConsumerState<KundaliGateView> createState() => _KundaliGateViewState();
}

class _KundaliGateViewState extends ConsumerState<KundaliGateView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  /// How many times a refresh that could not find out is tried again, and how long between.
  ///
  /// A push is tapped on a cold start, which is exactly when the session is still resolving and a
  /// status call is most likely to come back knowing nothing. A second ask a moment later almost
  /// always has an answer.
  static const _retries = 2;
  static const _retryGap = Duration(milliseconds: 600);

  Future<void> _resolve() async {
    await ref.read(kundaliSummaryProvider.future);
    var result = await ref.read(kundaliSummaryProvider.notifier).refresh(force: true);

    for (var attempt = 0; result.isUnknown && attempt < _retries; attempt++) {
      await Future<void>.delayed(_retryGap);
      if (!mounted) return;
      result = await ref.read(kundaliSummaryProvider.notifier).refresh(force: true);
    }
    if (!mounted) return;

    // Still no answer: Home, never the form. Sending someone to the form here offers to re-cast a
    // kundali that may well exist, and a re-cast costs them one of their regenerations.
    context.replace(result.isUnknown ? Routes.home : KundaliGateView.routeFor(result.summary));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AstralBackground(
        surface: AstralSurface.onboarding,
        child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      ),
    );
  }
}
