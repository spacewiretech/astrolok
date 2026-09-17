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

  Future<void> _resolve() async {
    await ref.read(kundaliSummaryProvider.future);
    final summary = await ref.read(kundaliSummaryProvider.notifier).refresh(force: true);
    if (!mounted) return;
    context.replace(KundaliGateView.routeFor(summary ?? ref.read(kundaliSummaryProvider).valueOrNull));
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
