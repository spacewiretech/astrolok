import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/att_consent.dart';
import '../../data/analytics/analytics_events.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/entitlement.dart';
import '../../data/providers.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/promo_carousel.dart';
import '../../widgets/reading_card.dart';
import '../../widgets/safe_asset.dart';
import '../chat/chat_threads_viewmodel.dart';

/// The signed-in, paid-for home.
///
/// Every row here now goes somewhere. The "coming soon" snackbar this screen used to answer
/// with is gone, and with it the last unbuilt thing on Home.
class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  /// So the view event fires once per visit rather than on every rebuild.
  bool _reported = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(entitlementProvider);

    // The conversations, fetched here rather than by the drawer that shows them. The list is the
    // same on every open, and loading it while the user is reading Home is the difference between
    // a drawer that opens and a drawer that loads. `read`, not `watch` — Home has nothing to
    // redraw when it lands, and the provider is kept alive, so this one read outlives the screen.
    final threads = ref.read(chatThreadsProvider);

    // Once per visit, not per rebuild. What the user already has decides what Home is for: an
    // account with three readings and a chat history is a returning user, and one with none is
    // still deciding whether the app does anything.
    if (!_reported) {
      _reported = true;
      analytics.track(Ev.homeViewed, {
        P.threadCount: threads.valueOrNull?.length,
        P.billingState: user?.billingState?.name,
        P.paymentType: user?.paymentType.name,
      });
      if (user?.billingState != null) {
        // Shown while there is still time to fix the mandate. How many people see this and how
        // many act on it is the difference between a warning and decoration.
        analytics.track(Ev.billingIssueShown, {P.billingState: user!.billingState!.name});
      }

      // The paywall asks first for anyone on the purchase path; this covers the already-entitled
      // user who lands straight here and never sees one. Idempotent — iOS only prompts while the
      // status is undetermined, and the helper guards against a second request in-process.
      unawaited(ensureTrackingConsent());

      // The paywall is behind this user, so the promo player onboarding warmed is a video
      // decoder held open for nothing. Dropping it is safe precisely because nothing is
      // listening any more: Riverpod disposes an invalidated provider without rebuilding it when
      // it has no listeners, so this frees the player rather than starting a fresh download. A
      // trial that lapses mid-session bounces back to /subscribe and opens a new one.
      //
      // After the frame rather than during it — invalidating a provider mid-build is the hazard.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(promoVideoProvider);
      });
    }

    return Scaffold(
      body: AstralBackground(
        surface: AstralSurface.home,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppShape.gutter, 8, AppShape.gutter, 32),
            children: [
              Row(
                children: [
                  const BrandLogo(size: 42),
                  const Spacer(),
                  _ProfileButton(onTap: () {
                    analytics.track(Ev.elementTapped, {P.elementId: 'profile_button'});
                    context.push(Routes.profile);
                  }),
                ],
              ),
              const SizedBox(height: 28),

              Text('Namaste🙏', style: AppText.display),
              const SizedBox(height: 6),
              Text('what would you like to discover today?', style: AppText.body),

              // A warning, never a gate: the user is still fully entitled here, and this is the
              // only notice they get while there is still time to fix the mandate.
              if (user?.billingState != null) ...[
                const SizedBox(height: 16),
                _BillingNotice(message: user!.billingState!.message),
              ],

              const SizedBox(height: 20),
              // The three cards each open the reading they advertise, in the same order as the
              // Explore rows below, so the strip and the list never disagree about what exists.
              PromoCarousel(
                slides: [
                  PromoSlide(
                    image: Img.promoChatAstro,
                    // The card's heading and button are pixels, so this is the only thing a
                    // screen reader gets. It has to say what the image says.
                    label: 'Chat with Astro. Ask anything about your life, love, career or '
                        'future. Start chat.',
                    onTap: () => _openReading(context, Routes.chat, 'chat', 'carousel'),
                  ),
                  PromoSlide(
                    image: Img.promoPalmReading,
                    label: "Palm Reading. Your palm holds a story. Let's discover yours. "
                        'Discover now.',
                    onTap: () => _openReading(context, Routes.palmCapture, 'palm', 'carousel'),
                  ),
                  PromoSlide(
                    image: Img.promoFaceReading,
                    label: "Face Reading. Your face holds a story. Let's discover yours. "
                        'Discover now.',
                    onTap: () => _openReading(context, Routes.faceCapture, 'face', 'carousel'),
                  ),
                ],
              ),

              const SizedBox(height: 32),
              Text('Explore Readings', style: AppText.section),
              const SizedBox(height: 16),

              ReadingCard(
                image: Img.readingChat,
                title: 'Chat with Astro',
                subtitle: 'Ask anything about your life, love,career or future',
                fallbackIcon: Icons.chat_bubble_outline_rounded,
                onTap: () => _openReading(context, Routes.chat, 'chat', 'card'),
              ),
              const SizedBox(height: 14),
              ReadingCard(
                image: Img.readingPalm,
                title: 'Palm Reading',
                subtitle: 'Discover what your palm reveals about your life.',
                fallbackIcon: Icons.back_hand_outlined,
                onTap: () => _openReading(context, Routes.palmCapture, 'palm', 'card'),
              ),
              const SizedBox(height: 14),
              ReadingCard(
                image: Img.readingFace,
                title: 'Face Reading',
                subtitle: 'Discover what your face reveals.',
                fallbackIcon: Icons.face_retouching_natural_outlined,
                onTap: () => _openReading(context, Routes.faceCapture, 'face', 'card'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens one of the three destinations, recording which surface sent them.
  ///
  /// The carousel and the cards below it advertise exactly the same three things, so without
  /// [surface] the two are one number and there is no way to tell whether the strip at the top
  /// of the screen earns the space it takes.
  void _openReading(
    BuildContext context,
    String route,
    String destination,
    String surface,
  ) {
    analytics.track(Ev.readingCardTapped, {
      P.destination: destination,
      P.source: surface,
    });
    context.push(route);
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Profile',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: AppShape.avatar,
          height: AppShape.avatar,
          child: Center(
            child: SafeSvg(
              Svg.profile,
              width: 30,
              height: 30,
              color: AppColors.navy,
              fallback: const Icon(
                Icons.account_circle_outlined,
                size: 32,
                color: AppColors.navy,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BillingNotice extends StatelessWidget {
  const _BillingNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSoft,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.gold),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: AppText.meta)),
        ],
      ),
    );
  }
}
