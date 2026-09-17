import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/kundali_summary.dart';
import '../../data/models/kundali.dart';
import '../../widgets/reading_card.dart';
import '../kundali/kundali_copy.dart';
import '../kundali/kundali_gate_view.dart';
import '../kundali/kundali_stages.dart';

/// The fourth Explore Readings row, which tells you where your kundali is.
///
/// Not started, a countdown, "almost ready", or "Ready ✨". The countdown ticks once a minute, and
/// only while there is one to show — a timer on Home for a card that is not counting would be a
/// timer for nothing.
///
/// Deliberately not routed through `guardTrialScan`: a kundali is not a photo reading, and a trial
/// account asking for one is exactly who the reveal a day later is for.
class KundaliCard extends ConsumerStatefulWidget {
  const KundaliCard({super.key});

  @override
  ConsumerState<KundaliCard> createState() => _KundaliCardState();
}

class _KundaliCardState extends ConsumerState<KundaliCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(kundaliSummaryProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _syncTicker(KundaliSummary? summary) {
    final counting = summary != null && summary.state == KundaliState.waiting && !summary.isPastUnlock();
    if (counting && _tick == null) {
      _tick = Timer.periodic(const Duration(minutes: 1), (_) {
        if (!mounted) return;
        final current = ref.read(kundaliSummaryProvider).valueOrNull;
        if (current != null && current.isPastUnlock()) {
          // Crossed the reveal: ask the server rather than claiming it is ready.
          ref.read(kundaliSummaryProvider.notifier).refresh(force: true);
        }
        setState(() {});
      });
    } else if (!counting && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(kundaliSummaryProvider).valueOrNull;
    _syncTicker(summary);

    final (subtitle, badge) = switch (summary) {
      null => (KundaliCopy.cardSubtitle, null),
      KundaliSummary(state: KundaliState.ready) => (
          summary.viewed ? KundaliCopy.cardSubtitle : KundaliCopy.cardReadySubtitle,
          summary.viewed ? null : const _Badge(label: KundaliCopy.cardReady, filled: true),
        ),
      KundaliSummary(state: KundaliState.failed) => (KundaliCopy.cardSubtitle, const _Badge(label: KundaliCopy.cardFailed)),
      _ when summary.isWritingNow() => (KundaliCopy.cardWaitingSubtitle, const _Badge(label: KundaliCopy.cardPreparing)),
      _ when summary.isPastUnlock() => (KundaliCopy.cardWaitingSubtitle, const _Badge(label: KundaliCopy.cardAlmost)),
      _ => (
          KundaliCopy.cardWaitingSubtitle,
          _Badge(label: KundaliCopy.cardWaiting(_coarse(summary.remaining()))),
        ),
    };

    return ReadingCard(
      image: Img.readingKundali,
      title: KundaliCopy.cardTitle,
      subtitle: subtitle,
      fallbackIcon: Icons.auto_awesome_mosaic_outlined,
      badge: badge,
      onTap: () {
        analytics.track(Ev.readingCardTapped, {P.destination: ReadingFeature.kundali, P.source: 'card'});
        analytics.track(Ev.kundaliCardTapped, {
          P.kundaliState: summary?.state.name ?? 'none',
          P.hoursRemaining: summary == null ? null : double.parse((summary.remaining().inMinutes / 60).toStringAsFixed(1)),
        });
        context.push(KundaliGateView.routeFor(summary));
      },
    );
  }

  /// "14h", "35m" — the card is a glance, not the countdown.
  static String _coarse(Duration left) {
    if (left.inHours >= 1) return '${left.inHours}h';
    if (left.inMinutes >= 1) return '${left.inMinutes}m';
    return formatRemaining(left);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.filled = false});

  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? AppColors.gold : AppColors.goldWash,
        borderRadius: AppShape.pill,
      ),
      child: Text(
        label,
        style: AppText.legal.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: filled ? Colors.white : AppColors.goldDeep,
        ),
      ),
    );
  }
}
