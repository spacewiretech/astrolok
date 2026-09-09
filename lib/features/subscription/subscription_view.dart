import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/models/subscription_offer.dart';
import '../../data/models/upi_app.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/att_consent.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/providers.dart';
import '../../data/repositories/app_config_repository.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/feature_pills.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/promo_video.dart';
import '../../widgets/safe_asset.dart';
import '../chat/chat_viewmodel.dart';
import 'subscription_viewmodel.dart';

/// The paywall.
///
/// Reads `appConfigProvider` directly for its display copy rather than routing it through the
/// ViewModel: none of it touches the purchase, and the ViewModel is the tested money path.
class SubscriptionView extends ConsumerStatefulWidget {
  const SubscriptionView({super.key});

  @override
  ConsumerState<SubscriptionView> createState() => _SubscriptionViewState();
}

class _SubscriptionViewState extends ConsumerState<SubscriptionView> {
  /// Starts muted. A paywall that plays sound the instant it opens is the fastest way to make
  /// someone close the app.
  bool _muted = false;

  /// So the view event fires once per visit rather than on every rebuild — and once the offer
  /// has actually loaded, because "saw the paywall" and "saw a spinner" are different things.
  bool _viewReported = false;

  static const _features = [
    Feature(
      icon: Svg.featurePersonalized,
      label: 'Personalized\nReadings',
      fallbackIcon: Icons.auto_awesome_outlined,
    ),
    Feature(
      icon: Svg.featureFacePalm,
      label: 'Face & Palm\nInsights',
      fallbackIcon: Icons.face_retouching_natural_outlined,
    ),
    Feature(
      icon: Svg.featureLove,
      label: 'Love & Career\nInsights',
      fallbackIcon: Icons.favorite_border_rounded,
    ),
    Feature(
      icon: Svg.featureUnlimited,
      label: 'Unlimited Astro\nGuidance',
      fallbackIcon: Icons.all_inclusive_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(subscriptionViewModelProvider);
    final config = ref.watch(appConfigProvider).valueOrNull ?? defaultAppConfig;
    final offer = state.offer;

    // The denominator of the whole purchase funnel.
    if (!_viewReported && !state.loading) {
      _viewReported = true;
      analytics.track(Ev.paywallViewed, {
        P.trialAvailable: state.trialAvailable,
        P.state: offer == null ? 'error' : 'loaded',
        P.upiAppCount: state.upiApps.length,
        P.paymentType: state.user?.paymentType.name,
      });

      // iOS only, and deliberately here rather than at launch: this is the last screen before a
      // purchase, so a granted IDFA still reaches the conversion event, and the user has already
      // been through onboarding rather than meeting a permission dialog cold. Not awaited — the
      // paywall must paint whether or not the user has answered.
      unawaited(ensureTrackingConsent());
    }

    return Scaffold(
      body: AstralBackground(
        surface: AstralSurface.home,
        child: SafeArea(
          // The pay bar paints its own bottom inset rather than sitting inside the safe area,
          // so it reaches the edge of the screen.
          bottom: false,
          child: state.loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
              : Column(
                  children: [
                    _topBar(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(AppShape.gutter, 8, AppShape.gutter, 16),
                        child: Column(
                          children: [
                            if (offer != null) _TrialHeadline(offer: offer),
                            const SizedBox(height: 10),
                            _RatingRow(config: config),
                            const SizedBox(height: 20),
                            PromoVideo(
                              url: config.configString('paywall_video_url'),
                              muted: _muted,
                            ),
                            const SizedBox(height: 24),
                            const FeaturePills(features: _features),
                            const SizedBox(height: 28),
                            if (offer != null) ...[
                              _PriceRow(offer: offer),
                              const SizedBox(height: 14),
                              // UPI Autopay requires the recurring amount and cadence to be
                              // stated before the mandate is authorised. Not optional, and not
                              // in the mockup.
                              Text(
                                offer.consent,
                                style: AppText.legal.copyWith(fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 18),
                            _PersonalNudge(name: state.user?.name, offer: offer),
                            if (state.error != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                state.error!,
                                style: AppText.meta.copyWith(color: AppColors.danger),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    _payBar(state),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppShape.gutter, 8, AppShape.gutter, 0),
      child: Row(
        children: [
          _CircleButton(
            onTap: () {
              analytics.track(Ev.promoVideoToggled, {P.muted: !_muted});
              setState(() => _muted = !_muted);
            },
            semanticLabel: _muted ? 'Unmute video' : 'Mute video',
            child: SafeSvg(
              _muted ? Svg.soundOff : Svg.soundOn,
              width: 22,
              height: 22,
              color: AppColors.navy,
              fallback: Icon(
                _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 22,
                color: AppColors.navy,
              ),
            ),
          ),
          const Spacer(),
          // _LogOutButton(),
        ],
      ),
    );
  }

  /// The UPI app chip and the pay button, pinned below the scroll so they are reachable on a
  /// short screen without scrolling to the bottom.
  ///
  /// No white plate behind them: in the render they sit directly on the cream ground, and the
  /// plate this used to draw cut a hard horizontal line across the background artwork.
  Widget _payBar(SubscriptionState state) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppShape.gutter,
        12,
        AppShape.gutter,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: [
          Expanded(child: _UpiChip(state: state)),
          const SizedBox(width: 12),
          GoldPillButton(
            label: 'Try Now',
            busy: state.busy,
            onPressed: state.canSubscribe ? _subscribe : null,
          ),
        ],
      ),
    );
  }

  Future<void> _subscribe() async {
    final outcome = await ref.read(subscriptionViewModelProvider.notifier).subscribe();
    // Null means the tap was ignored because one was already in flight — not an outcome, and
    // routing on it would throw a status screen over a payment that is still running.
    if (!mounted || outcome == null) return;
    context.go(Routes.paymentStatusFor(outcome));
  }
}

/// "1-Day Trial for ₹3", the price picked out in a gold pill.
///
/// The mockup badges this "FREE". It is not free — Cashfree captures the authorisation and
/// keeps it (`authorization_amount_refund: false`) — so the badge states the real amount.
class _TrialHeadline extends StatelessWidget {
  const _TrialHeadline({required this.offer});

  final SubscriptionOffer offer;

  @override
  Widget build(BuildContext context) {
    final days = offer.trialDays;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            '$days-Day Trial for',
            style: AppText.display.copyWith(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: const BoxDecoration(
            gradient: AppColors.goldFill,
            borderRadius: AppShape.pill,
          ),
          child: Text(
            offer.trialPrice,
            style: AppText.display.copyWith(color: Colors.white, fontSize: 16),
          ),
        ),
      ],
    );
  }
}

/// The star rating and subscriber count.
///
/// Both come from `app_config` and ship EMPTY, so the row is absent until someone fills them
/// in. A launch build cannot claim a score the app has not earned — Play treats a
/// misrepresented rating the way it treats a mislabelled free trial.
class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.config});

  final Map<String, String> config;

  @override
  Widget build(BuildContext context) {
    final rating = config.configString('rating_label').trim();
    final subscribers = config.configString('subscriber_label').trim();
    if (rating.isEmpty && subscribers.isEmpty) return const SizedBox.shrink();

    final score = double.tryParse(rating);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (score != null) ...[
          for (var i = 1; i <= 5; i++)
            Icon(
              i <= score.floor()
                  ? Icons.star_rounded
                  : (i - score < 1 ? Icons.star_half_rounded : Icons.star_border_rounded),
              size: 20,
              color: AppColors.gold,
            ),
          const SizedBox(width: 8),
        ],
        if (rating.isNotEmpty)
          Text(rating, style: AppText.title.copyWith(fontWeight: FontWeight.w600)),
        if (subscribers.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text('( $subscribers )', style: AppText.meta),
        ],
      ],
    );
  }
}

/// ₹̶2̶4̶9̶ ₹3 — the monthly price struck through beside the trial price.
class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.offer});

  final SubscriptionOffer offer;

  @override
  Widget build(BuildContext context) {
    final strike = offer.strikePrice;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (strike != null && strike != offer.trialPrice) ...[
          Text(strike, style: AppText.priceStrike),
          const SizedBox(width: 14),
        ],
        Text(offer.trialPrice, style: AppText.priceHero),
      ],
    );
  }
}

/// The gold toast above the pay bar, addressed to the person reading it.
///
/// The mockup's version is a past-tense claim — "Arjun Ji started a 1-day premium trial now" —
/// which, rendered with the viewer's own name on the screen asking them to pay, is the one
/// statement they can personally verify is false. Present tense keeps the personal touch and
/// says something true.
class _PersonalNudge extends StatelessWidget {
  const _PersonalNudge({required this.name, required this.offer});

  final String? name;
  final SubscriptionOffer? offer;

  @override
  Widget build(BuildContext context) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || offer == null) return const SizedBox.shrink();

    // First name only: the toast is a greeting, and a full legal name reads as a form field.
    final first = trimmed.split(RegExp(r'\s+')).first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSoft,
        borderRadius: AppShape.pill,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 18, color: AppColors.gold),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '$first Ji, your ${offer!.trialDays}-day trial is ready',
              style: AppText.meta.copyWith(color: AppColors.heading),
            ),
          ),
        ],
      ),
    );
  }
}

/// Which UPI app "Try Now" will open, and a way to change it.
class _UpiChip extends ConsumerWidget {
  const _UpiChip({required this.state});

  final SubscriptionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = state.selectedApp;

    // No apps discovered means Cashfree's own checkout stands in — there is nothing to pick,
    // and a chip offering a choice that does not exist would be a lie about the next tap.
    if (state.upiApps.isEmpty) {
      return Text('Pay securely by UPI', style: AppText.meta);
    }

    return InkWell(
      onTap: state.busy ? null : () => _pick(context, ref),
      borderRadius: AppShape.pill,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _UpiAvatar(app: selected),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                selected?.displayName ?? 'Choose app',
                style: AppText.title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.navy),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    analytics.track(Ev.upiPickerOpened, {
      P.appId: state.selectedAppId,
      P.availableCount: state.upiApps.length,
    });

    final chosen = await showModalBottomSheet<UpiApp>(
      context: context,
      backgroundColor: AppColors.surface,
      barrierColor: AppColors.scrim,
      // Named so the navigator observer reports it as a real surface rather than an anonymous
      // route. Picking a UPI app is one of the more interesting things a user does here.
      routeSettings: const RouteSettings(name: 'upi-picker'),
      shape: const RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: AppShape.pill,
              ),
            ),
            const SizedBox(height: 16),
            Text('Pay with', style: AppText.section),
            const SizedBox(height: 8),
            for (final app in state.upiApps)
              ListTile(
                leading: _UpiAvatar(app: app),
                title: Text(app.displayName, style: AppText.title),
                trailing: app.id == state.selectedAppId
                    ? const Icon(Icons.check_circle_rounded, color: AppColors.gold)
                    : null,
                onTap: () => Navigator.of(context).pop(app),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (chosen != null) {
      ref.read(subscriptionViewModelProvider.notifier).selectApp(chosen.id);
    }
  }
}

/// A UPI app's icon. Arrives as base64 from the SDK and is routinely missing, so the tile has
/// to read correctly without one.
class _UpiAvatar extends StatelessWidget {
  const _UpiAvatar({required this.app});

  final UpiApp? app;

  @override
  Widget build(BuildContext context) {
    final icon = app?.icon;

    return Container(
      width: 34,
      height: 34,
      decoration: const BoxDecoration(color: AppColors.goldWash, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: icon == null
          ? const Icon(Icons.account_balance_wallet_outlined, size: 18, color: AppColors.gold)
          : Image.memory(icon, width: 34, height: 34, fit: BoxFit.cover),
    );
  }
}

class _LogOutButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppShape.pill,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          // Before the reset, or it would be attributed to the fresh anonymous identity rather
          // than to the account that actually left.
          analytics.track(Ev.signedOut, {P.source: 'paywall'});
          await ref.read(authRepositoryProvider).signOut();
          forgetConversations(ref);
          // Mints a new anonymous id and drops the identity super properties, so the next user
          // of this handset does not inherit the last one's account.
          analytics.reset();
          if (context.mounted) context.go(Routes.onboarding);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Text('Log out', style: AppText.title),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.child, required this.onTap, this.semanticLabel});

  final Widget child;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Center(child: child)),
        ),
      ),
    );
  }
}
