import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../app/trial_scan_guard.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/firebase/push_messaging.dart';
import '../../data/kundali_summary.dart';
import '../../data/models/kundali.dart';
import '../../data/providers.dart';
import '../../data/repositories/app_config_repository.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/reading_card.dart';
import '../../widgets/stage_checklist.dart';
import '../../widgets/zodiac_wheel.dart';
import 'kundali_copy.dart';
import 'kundali_stages.dart';

/// The wait between asking for a kundali and its reveal.
///
/// Built to be come back to: a countdown, stages that tick off as the day passes, the Moon's sign
/// and nakshatra as a first glimpse, a way to be told when it is ready, and the other readings to
/// fill the time. Every open is counted — returning to this screen is the recurrence the wait is for.
///
/// That wait is a trial's. A paying account's kundali has none: it lands here for the few seconds
/// the reading takes to write, checks every few seconds, and opens the report the moment it is ready.
class KundaliWaitingView extends ConsumerStatefulWidget {
  const KundaliWaitingView({super.key});

  @override
  ConsumerState<KundaliWaitingView> createState() => _KundaliWaitingViewState();
}

enum _Notify { unknown, canAsk, on, blocked }

class _KundaliWaitingViewState extends ConsumerState<KundaliWaitingView> with WidgetsBindingObserver {
  Timer? _tick;
  Timer? _poll;
  DateTime _now = DateTime.now();
  _Notify _notify = _Notify.unknown;
  bool _reported = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _checkNotify();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _checkNotify();
    }
  }

  void _onTick() {
    if (!mounted) return;
    final summary = ref.read(kundaliSummaryProvider).valueOrNull;
    final wasLocked = summary != null && !summary.isPastUnlock(_now);
    setState(() => _now = DateTime.now());
    // The moment the countdown reaches zero, ask whether it is revealed rather than waiting for a
    // resume or the next poll.
    if (wasLocked && summary.isPastUnlock(_now)) _refresh();
  }

  Future<void> _refresh() async {
    final summary = await ref.read(kundaliSummaryProvider.notifier).refresh(force: true, surface: 'waiting');
    if (!mounted) return;

    if (!_reported && summary != null) {
      _reported = true;
      analytics.track(Ev.kundaliWaitingViewed, {
        P.kundaliId: summary.id,
        P.kundaliState: summary.state.name,
        P.hoursRemaining: double.parse((summary.remaining().inMinutes / 60).toStringAsFixed(1)),
        P.stage: summary.currentStage(),
        P.instant: summary.isInstant,
      });
    }

    switch (summary?.state) {
      case KundaliState.ready:
        _poll?.cancel();
        _go(Routes.kundaliReport);
      case null:
        // Nothing was ever asked for, or it was replaced from another device.
        if (ref.read(kundaliSummaryProvider).valueOrNull == null) _go(Routes.kundaliNew);
      case KundaliState.delayed:
        // Being written right now — a paying account's, which has no wait — is seconds away, so
        // look often. Past that it is late, and once a minute is plenty.
        _pollEvery(summary!.isWritingNow() ? _writingPoll : _latePoll);
      default:
        break;
    }
  }

  static const _writingPoll = Duration(seconds: 3);
  static const _latePoll = Duration(minutes: 1);
  Duration? _pollInterval;

  void _pollEvery(Duration interval) {
    if (_poll != null && _pollInterval == interval) return;
    _poll?.cancel();
    _pollInterval = interval;
    _poll = Timer.periodic(interval, (_) => _refresh());
  }

  void _go(String route) {
    if (_leaving || !mounted) return;
    _leaving = true;
    context.replace(route);
  }

  Future<void> _checkNotify() async {
    final authorized = await pushMessaging.isAuthorized();
    final canAsk = !authorized && await pushMessaging.canPrompt();
    if (!mounted) return;
    setState(() => _notify = authorized ? _Notify.on : (canAsk ? _Notify.canAsk : _Notify.blocked));
  }

  Future<void> _askToNotify() async {
    final before = _notify;
    final granted = await pushMessaging.requestFromPrimer(source: 'kundali');
    analytics.track(Ev.kundaliNotifyTapped, {
      P.permissionBefore: before.name,
      P.permissionAfter: granted ? 'on' : 'blocked',
      P.prompted: before == _Notify.canAsk,
    });
    if (!mounted) return;
    setState(() => _notify = granted ? _Notify.on : _Notify.blocked);
  }

  Future<void> _crossSell(String route, String destination) async {
    analytics.track(Ev.kundaliCrossSellTapped, {P.destination: destination});
    if (destination != ReadingFeature.chat && await guardTrialScan(context, ref, destination, source: 'kundali')) {
      return;
    }
    if (mounted) context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(kundaliSummaryProvider).valueOrNull;
    final config = ref.watch(appConfigProvider).valueOrNull ?? shippedAppConfig;

    return Scaffold(
      body: AstralBackground(
        surface: AstralSurface.home,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppShape.gutter, 8, AppShape.gutter, 0),
                child: Row(
                  children: [
                    CircleIconButton(
                      image: PalmIcon.backCircle,
                      icon: Icons.chevron_left_rounded,
                      semanticLabel: 'Back',
                      onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: summary == null
                    ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(AppShape.gutter, 4, AppShape.gutter, 32),
                        children: [
                          const AccentHeading(
                            lead: KundaliCopy.waitingTitleLead,
                            accent: KundaliCopy.waitingTitleAccent,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            summary.isInstant
                                ? KundaliCopy.instantSubtitle
                                : KundaliCopy.waitingSubtitle(formatReveal(summary.unlockAt, _now)),
                            style: AppText.body,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 22),
                          const Center(child: ZodiacWheel(size: 196)),
                          const SizedBox(height: 22),
                          if (summary.state == KundaliState.failed)
                            _StatusCard(
                              icon: Icons.refresh_rounded,
                              title: KundaliCopy.failedTitle,
                              body: KundaliCopy.failedBody,
                              action: PrimaryButton(
                                label: KundaliCopy.failedAction,
                                analyticsId: 'kundali_retry',
                                tone: ButtonTone.navy,
                                pill: true,
                                onPressed: () => context.push(Routes.kundaliNew),
                              ),
                            )
                          else if (summary.isWritingNow(_now))
                            const _StatusCard(
                              icon: Icons.auto_awesome_rounded,
                              busy: true,
                              title: KundaliCopy.writingTitle,
                              body: KundaliCopy.writingBody,
                            )
                          else if (summary.isPastUnlock(_now))
                            const _StatusCard(
                              icon: Icons.hourglass_bottom_rounded,
                              title: KundaliCopy.almostTitle,
                              body: KundaliCopy.almostBody,
                            )
                          else
                            _Countdown(left: summary.remaining(_now)),
                          if (!summary.teaser.isEmpty) ...[
                            const SizedBox(height: 16),
                            _Teaser(teaser: summary.teaser),
                          ],
                          const SizedBox(height: 16),
                          Text(KundaliCopy.stagesTitle, style: AppText.section),
                          const SizedBox(height: 10),
                          StageChecklist(items: kundaliStageItems(summary, _now)),
                          // Not while it is seconds away: it will open here before a push could arrive.
                          if (config.configFlag(pushPrimerEnabledKey) &&
                              _notify != _Notify.unknown &&
                              !summary.isWritingNow(_now)) ...[
                            const SizedBox(height: 16),
                            _NotifyCard(state: _notify, onAsk: _askToNotify),
                          ],
                          const SizedBox(height: 26),
                          Text(KundaliCopy.whileYouWait, style: AppText.section),
                          const SizedBox(height: 12),
                          ReadingCard(
                            image: Img.readingPalm,
                            title: 'Palm Reading',
                            subtitle: 'Discover what your palm reveals about your life.',
                            fallbackIcon: Icons.back_hand_outlined,
                            onTap: () => _crossSell(Routes.palmCapture, ReadingFeature.palm),
                          ),
                          const SizedBox(height: 12),
                          ReadingCard(
                            image: Img.readingFace,
                            title: 'Face Reading',
                            subtitle: 'Discover what your face reveals.',
                            fallbackIcon: Icons.face_retouching_natural_outlined,
                            onTap: () => _crossSell(Routes.faceCapture, ReadingFeature.face),
                          ),
                          const SizedBox(height: 12),
                          ReadingCard(
                            image: Img.readingChat,
                            title: 'Chat with Astro',
                            subtitle: 'Ask anything about your life, love, career or future',
                            fallbackIcon: Icons.chat_bubble_outline_rounded,
                            onTap: () => _crossSell(Routes.chat, ReadingFeature.chat),
                          ),
                          if (summary.regenerationsLeft > 0 && summary.state != KundaliState.failed) ...[
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton(
                                onPressed: () => context.push(Routes.kundaliForm(edit: true)),
                                child: Text(
                                  KundaliCopy.editDetails,
                                  style: AppText.meta.copyWith(
                                    color: AppColors.goldDeep,
                                    decoration: TextDecoration.underline,
                                    decorationColor: AppColors.goldDeep,
                                  ),
                                ),
                              ),
                            ),
                          ],
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

class _Countdown extends StatelessWidget {
  const _Countdown({required this.left});

  final Duration left;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: AppShape.card,
        boxShadow: const [AppColors.floatingShadow],
      ),
      child: Column(
        children: [
          Text(
            KundaliCopy.revealedIn,
            style: AppText.meta.copyWith(color: Colors.white.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 4),
          Semantics(
            liveRegion: false,
            label: '${KundaliCopy.revealedIn} ${formatRemaining(left)}',
            child: ExcludeSemantics(
              child: Text(
                formatCountdown(left),
                style: AppText.display.copyWith(color: AppColors.gold, fontSize: 30, letterSpacing: 1),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text('hrs      mins      secs', style: AppText.legal.copyWith(color: Colors.white.withValues(alpha: 0.55))),
        ],
      ),
    );
  }
}

class _Teaser extends StatelessWidget {
  const _Teaser({required this.teaser});

  final KundaliTeaser teaser;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFF4DE), Color(0xFFFFFBF2)]),
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surface),
            alignment: Alignment.center,
            child: const Text('☽', style: TextStyle(fontSize: 26, color: AppColors.goldDeep)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  KundaliCopy.teaserKicker,
                  style: AppText.legal.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.8, color: AppColors.goldDeep),
                ),
                const SizedBox(height: 2),
                if (teaser.moonRashi != null)
                  Text(KundaliCopy.teaser(teaser.moonRashi!, teaser.moonSign), style: AppText.title),
                if (teaser.nakshatra != null)
                  Text(KundaliCopy.teaserNakshatra(teaser.nakshatra!, teaser.pada), style: AppText.meta),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifyCard extends StatelessWidget {
  const _NotifyCard({required this.state, required this.onAsk});

  final _Notify state;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      _Notify.canAsk => PrimaryButton(
          label: KundaliCopy.notifyMe,
          analyticsId: 'kundali_notify_me',
          icon: Icons.notifications_active_outlined,
          tone: ButtonTone.gold,
          pill: true,
          onPressed: onAsk,
        ),
      _Notify.on => const _StatusCard(icon: Icons.notifications_active_rounded, title: KundaliCopy.notifyOn),
      _Notify.blocked => const _StatusCard(icon: Icons.notifications_off_outlined, body: KundaliCopy.notifyBlocked),
      _Notify.unknown => const SizedBox.shrink(),
    };
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.icon, this.title, this.body, this.action, this.busy = false});

  final IconData icon;
  final String? title;
  final String? body;
  final Widget? action;

  /// A spinner in place of the icon, for something happening now.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: Padding(
                    padding: EdgeInsets.all(2),
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.gold),
                  ),
                )
              else
                Icon(icon, color: AppColors.gold, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) Text(title!, style: AppText.title),
                    if (body != null) Text(body!, style: AppText.meta),
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}
