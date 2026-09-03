import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/assets.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/entitlement.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/promo_carousel.dart';
import '../../widgets/reading_card.dart';
import '../../widgets/safe_asset.dart';

/// The signed-in, paid-for home.
///
/// The three reading entries and the profile button are designed but not built — they need a
/// camera, an upload target and a reading backend, none of which exist yet. Each answers with
/// "Coming soon" rather than being a chevron that does nothing, which reads as a bug.
class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(entitlementProvider);

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
                  _ProfileButton(onTap: () => _soon(context, 'Your profile')),
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
              // One slide until the Palm and Face cards are exported the same way. The dot row
              // hides itself at one, so the strip does not advertise pages that do not exist.
              PromoCarousel(
                slides: [
                  PromoSlide(
                    image: Img.promoChatAstro,
                    // The card's heading and button are pixels, so this is the only thing a
                    // screen reader gets. It has to say what the image says.
                    label: 'Chat with Astro. Ask anything about your life, love, career or '
                        'future. Start chat.',
                    onTap: () => _soon(context, 'Chat with Astro'),
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
                onTap: () => _soon(context, 'Chat with Astro'),
              ),
              const SizedBox(height: 14),
              ReadingCard(
                image: Img.readingPalm,
                title: 'Palm Reading',
                subtitle: 'Discover what your palm reveals about your life.',
                fallbackIcon: Icons.back_hand_outlined,
                onTap: () => _soon(context, 'Palm Reading'),
              ),
              const SizedBox(height: 14),
              ReadingCard(
                image: Img.readingFace,
                title: 'Face Reading',
                subtitle: 'Discover what your face reveals.',
                fallbackIcon: Icons.face_retouching_natural_outlined,
                onTap: () => _soon(context, 'Face Reading'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _soon(BuildContext context, String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what is coming soon.')));
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
