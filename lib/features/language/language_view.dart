import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../data/providers.dart';
import '../../data/repositories/app_config_repository.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/invite_code_row.dart';
import '../../widgets/push_primer_sheet.dart';
import '../../widgets/safe_asset.dart';
import 'language_viewmodel.dart';

/// One card on the picker.
@immutable
class LanguageOption {
  const LanguageOption({
    required this.language,
    required this.title,
    required this.subtitle,
    required this.art,
    required this.tint,
    this.artFallback,
  });

  /// What is saved, spelled exactly as `chat_languages` spells it — `update-profile` refuses
  /// anything the list does not offer.
  final String language;

  /// The language in its own script, as the design sets it.
  final String title;

  /// The English name under it.
  final String subtitle;

  final String art;

  /// Drawn when [art] is not in the bundle: the wash of the export, so the card still reads as
  /// that card.
  final List<Color> tint;

  /// Tried before [tint] when [art] is missing.
  final String? artFallback;
}

/// Which language Astro answers in — the one question between OTP and the paywall.
///
/// Tapping a card is the answer: the check lands, the choice saves, and the paywall opens. There is
/// no Continue button in the design and nothing is preselected, so every account arrives at the
/// paywall having actually chosen.
class LanguageView extends ConsumerStatefulWidget {
  const LanguageView({super.key});

  /// In the order drawn. The design's six, plus Hinglish — Hindi as it is typed on a phone, and
  /// the configured default — placed beside the Hindi it is a way of writing.
  static const options = [
    LanguageOption(
      language: 'Hinglish',
      title: 'Hinglish',
      subtitle: 'Hindi + English',
      art: Img.langHinglish,
      artFallback: Img.langHindi,
      tint: [Color(0xFFFDF3E6), Color(0xFFF4D6B0)],
    ),
    LanguageOption(
      language: 'English',
      title: 'English',
      subtitle: 'English',
      art: Img.langEnglish,
      tint: [Color(0xFFFFF7EA), Color(0xFFFBE3C2)],
    ),
    LanguageOption(
      language: 'Hindi',
      title: 'हिंदी',
      subtitle: 'Hindi',
      art: Img.langHindi,
      tint: [Color(0xFFFDF3E6), Color(0xFFF4D6B0)],
    ),
    LanguageOption(
      language: 'Telugu',
      title: 'తెలుగు',
      subtitle: 'Telugu',
      art: Img.langTelugu,
      tint: [Color(0xFFF1F7EE), Color(0xFFD3E7D0)],
    ),
    LanguageOption(
      language: 'Tamil',
      title: 'தமிழ்',
      subtitle: 'Tamil',
      art: Img.langTamil,
      tint: [Color(0xFFF9D48A), Color(0xFFE39A35)],
    ),
    LanguageOption(
      language: 'Kannada',
      title: 'ಕನ್ನಡ',
      subtitle: 'Kannada',
      art: Img.langKannada,
      tint: [Color(0xFF8CC2EC), Color(0xFFDDEFF8)],
    ),
    LanguageOption(
      language: 'Malayalam',
      title: 'മലയാളം',
      subtitle: 'Malayalam',
      art: Img.langMalayalam,
      tint: [Color(0xFFFCE8EF), Color(0xFFF3C6D6)],
    ),
  ];

  @override
  ConsumerState<LanguageView> createState() => _LanguageViewState();
}

class _LanguageViewState extends ConsumerState<LanguageView> {
  /// Measured off the 412pt-wide frame.
  static const _sideGutter = 28.0;
  static const _columnGap = 13.0;

  /// The design spaces three rows 36pt apart. Hinglish makes it four, and at that gap the last
  /// row falls below the fold on an ordinary Android phone.
  static const _rowGap = 24.0;

  /// Long enough to see the check land before the paywall replaces the screen. The save runs
  /// alongside, so a fast network costs this and nothing more.
  static const _checkDwell = Duration(milliseconds: 250);

  bool _skipping = false;

  Future<void> _choose(String language) async {
    if (ref.read(languageViewModelProvider).busy) return;
    HapticFeedback.selectionClick();

    final (next, _) = await (
      ref.read(languageViewModelProvider.notifier).choose(language),
      Future<void>.delayed(_checkDwell),
    ).wait;
    if (!mounted || next == null) return;

    // The one moment before the paywall to explain notifications. Asked here rather than on Home
    // so that someone who leaves at the paywall has still been asked — the paywall and onboarding
    // reminders cannot reach a device that never granted permission.
    final config = ref.read(appConfigProvider).valueOrNull ?? shippedAppConfig;
    if (next.route == Routes.subscribe && config.configFlag(pushPrimerEnabledKey)) {
      await showPushPrimer(context, source: 'language');
      if (!mounted) return;
    }

    context.go(next.route);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(languageViewModelProvider);
    final config = ref.watch(appConfigProvider).valueOrNull ?? shippedAppConfig;

    // Only what the server will accept. A language retired from the dashboard disappears here
    // rather than failing on tap.
    final offered = {
      for (final name in config.configList(chatLanguagesKey)) name.toLowerCase(),
    };
    final options = [
      for (final option in LanguageView.options)
        if (offered.contains(option.language.toLowerCase())) option,
    ];

    // An empty list is the documented off switch for the whole feature, so there is nothing to
    // ask. Straight on to the paywall.
    if (options.isEmpty && !_skipping) {
      _skipping = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(Routes.subscribe);
      });
    }

    return Scaffold(
      body: AstralBackground(
        surface: AstralSurface.onboarding,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(_sideGutter, 44, _sideGutter, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrandLogo(size: 40)),
                const SizedBox(height: 56),
                for (var i = 0; i < options.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: _rowGap),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _card(options[i], state)),
                      const SizedBox(width: _columnGap),
                      Expanded(
                        child: i + 1 < options.length
                            ? _card(options[i + 1], state)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ],
                if (state.error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    state.error!,
                    style: AppText.meta.copyWith(color: AppColors.danger),
                    textAlign: TextAlign.center,
                  ),
                ],
                // Here rather than after payment: `referral-claim` refuses any account that has
                // had a trial, so this is the last screen a code can still be applied from.
                if (config.configFlag(referralEnabledKey)) ...[
                  const SizedBox(height: 16),
                  const InviteCodeRow(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(LanguageOption option, LanguageState state) {
    final selected = state.selected == option.language;
    return _LanguageCard(
      option: option,
      selected: selected,
      // The rest recede while a choice saves, which is the only progress this screen shows.
      dimmed: state.busy && !selected,
      onTap: state.busy ? null : () => _choose(option.language),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.option,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  final LanguageOption option;
  final bool selected;
  final bool dimmed;
  final VoidCallback? onTap;

  /// The exports are 343x244.
  static const _aspect = 343 / 244;
  static const _radius = BorderRadius.all(Radius.circular(13));
  static const _checkSize = 20.0;

  @override
  Widget build(BuildContext context) {
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: option.tint,
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: option.subtitle,
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: dimmed ? 0.55 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          // Drawn over the art rather than around it, so selecting a card never nudges the grid.
          foregroundDecoration: BoxDecoration(
            borderRadius: _radius,
            border: Border.all(
              color: selected ? AppColors.gold : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: ClipRRect(
            borderRadius: _radius,
            child: AspectRatio(
              aspectRatio: _aspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SafeImage(
                    option.art,
                    fit: BoxFit.cover,
                    fallback: option.artFallback == null
                        ? gradient
                        : SafeImage(option.artFallback!, fit: BoxFit.cover, fallback: gradient),
                  ),
                  Positioned(
                    left: 14,
                    top: 12,
                    right: _checkSize + 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.title,
                          style: AppText.title.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.heading,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          option.subtitle,
                          style: AppText.meta.copyWith(
                            fontSize: 12,
                            color: AppColors.heading,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 13,
                    right: 12,
                    child: _Check(selected: selected, size: _checkSize),
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(onTap: onTap),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The gold tick on the chosen card, an empty ring on the rest.
class _Check extends StatelessWidget {
  const _Check({required this.selected, required this.size});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.gold : Colors.transparent,
        border: selected
            ? null
            : Border.all(color: AppColors.navy.withValues(alpha: 0.8), width: 1.5),
      ),
      alignment: Alignment.center,
      child: selected
          ? Icon(Icons.check_rounded, size: size * 0.7, color: AppColors.surface)
          : null,
    );
  }
}
