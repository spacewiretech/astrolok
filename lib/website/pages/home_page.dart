import 'package:flutter/material.dart';

import '../../app/assets.dart';
import '../../app/theme/app_colors.dart';
import '../../widgets/safe_asset.dart';
import '../site_copy.dart';
import '../site_shell.dart';
import '../site_theme.dart';
import '../widgets.dart';

/// The landing page: hero → readings → how it works → pricing → FAQ → download.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.anchor});

  /// Section to scroll to on arrival, from `/?to=pricing`. Set when the nav jumps here from
  /// another page.
  final String? anchor;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scroll = ScrollController();

  final _keys = <String, GlobalKey>{
    'features': GlobalKey(),
    'how': GlobalKey(),
    'pricing': GlobalKey(),
    'faq': GlobalKey(),
    'download': GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    HomeAnchors.request.addListener(_onAnchorRequest);
    if (widget.anchor != null) {
      // The keys have no context until the first frame is laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(widget.anchor!));
    }
  }

  @override
  void dispose() {
    HomeAnchors.request.removeListener(_onAnchorRequest);
    _scroll.dispose();
    super.dispose();
  }

  void _onAnchorRequest() {
    final request = HomeAnchors.request.value;
    if (request != null && mounted) _scrollTo(request.$1);
  }

  void _scrollTo(String anchor) {
    final context = _keys[anchor]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      // Clear the nav bar, which sits above the scroll view rather than over it.
      alignment: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Title(
      title: '${SiteCopy.appName} — ${SiteCopy.tagline}',
      color: AppColors.navy,
      child: SiteShell(
        controller: _scroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Hero(),
            SiteSection(
              anchorKey: _keys['features'],
              child: const _Features(),
            ),
            SiteSection(
              anchorKey: _keys['how'],
              background: SiteColors.tint,
              child: const _HowItWorks(),
            ),
            SiteSection(
              anchorKey: _keys['pricing'],
              child: const _Pricing(),
            ),
            SiteSection(
              anchorKey: _keys['faq'],
              background: SiteColors.tint,
              child: const _Faq(),
            ),
            SiteSection(
              anchorKey: _keys['download'],
              background: SiteColors.ink,
              child: const _FinalCta(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final stacked = !isDesktop(context);

    final copy = Column(
      crossAxisAlignment: stacked ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.7),
            borderRadius: SiteShape.pillRadius,
            border: Border.all(color: SiteColors.border),
          ),
          child: Text(SiteCopy.heroEyebrow.toUpperCase(), style: SiteText.eyebrow),
        ),
        const SizedBox(height: 22),
        Text(
          SiteCopy.heroHeadline,
          style: SiteText.hero(context),
          textAlign: stacked ? TextAlign.center : TextAlign.start,
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            SiteCopy.heroSub,
            style: SiteText.heroSub(context),
            textAlign: stacked ? TextAlign.center : TextAlign.start,
          ),
        ),
        const SizedBox(height: 32),
        StoreCta(alignment: stacked ? WrapAlignment.center : WrapAlignment.start),
        const SizedBox(height: 18),
        Text(
          SiteCopy.priceLine,
          style: SiteText.cardBody(context),
          textAlign: stacked ? TextAlign.center : TextAlign.start,
        ),
      ],
    );

    const art = _HeroArt();

    return SiteSection(
      gradient: AppColors.backdropWarm,
      child: stacked
          ? Column(children: [copy, const SizedBox(height: 48), art])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: copy),
                const SizedBox(width: 56),
                const Expanded(child: art),
              ],
            ),
    );
  }
}

/// The device mockups already bundled for onboarding. Two of them, overlapped, so the fold
/// shows the product rather than a single flat screenshot.
///
/// Deliberately the palm and face slides and not [Img.onboard1]: that export still carries a
/// "Bhaktilok" wordmark from whatever it was traced from, which would put the wrong brand on
/// the first thing a visitor sees. These two show no wordmark at all — and they show the two
/// readings the page is actually selling.
class _HeroArt extends StatelessWidget {
  const _HeroArt();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 460),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(top: 34, right: 8),
              child: SafeImage(
                Img.onboard3,
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
              ),
            ),
          ),
          Flexible(
            child: SafeImage(
              Img.onboard2,
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
            ),
          ),
        ],
      ),
    );
  }
}

class _Features extends StatelessWidget {
  const _Features();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SectionHeading(
          eyebrow: 'Explore readings',
          title: 'Three ways to read your future',
          subtitle: 'Each reading comes back in plain language, read aloud in a pandit’s '
              'voice, and saved as a PDF you can keep or share.',
        ),
        const SizedBox(height: 48),
        _CardGrid(
          max: 3,
          children: [
            for (final feature in SiteCopy.features) FeatureCard(feature: feature),
          ],
        ),
      ],
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SectionHeading(
          eyebrow: 'How it works',
          title: 'Three steps, about a minute',
          subtitle: 'No forms, no questionnaire, no waiting for an astrologer to be free.',
        ),
        const SizedBox(height: 48),
        _CardGrid(
          max: 3,
          children: [
            for (final (index, step) in SiteCopy.steps.indexed)
              StepCard(index: index, step: step),
          ],
        ),
      ],
    );
  }
}

class _Pricing extends StatelessWidget {
  const _Pricing();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SectionHeading(
          eyebrow: 'Pricing',
          title: 'One plan, everything included',
          subtitle: 'Start with a ${SiteCopy.trialDays}-day trial for '
              '${SiteCopy.trialPrice}. Cancel any time before it ends and nothing further is '
              'charged.',
        ),
        const SizedBox(height: 48),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: SiteShape.cardRadius,
                border: Border.all(color: AppColors.gold),
                boxShadow: const [AppColors.floatingShadow],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${SiteCopy.trialDays}-day trial',
                    style: SiteText.cardTitle(context),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        SiteCopy.planPrice,
                        style: SiteText.cardBody(context).copyWith(
                          fontSize: 20,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        SiteCopy.trialPrice,
                        style: SiteText.hero(context).copyWith(
                          fontSize: 46,
                          color: AppColors.goldDeep,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'then ${SiteCopy.planPrice}/month by UPI Autopay',
                    style: SiteText.cardBody(context),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 26),
                  const Divider(),
                  const SizedBox(height: 22),
                  for (final highlight in SiteCopy.highlights)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                            color: AppColors.gold,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(highlight, style: SiteText.cardBody(context)),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  const StoreCta(alignment: WrapAlignment.center),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SectionHeading(
          eyebrow: 'FAQ',
          title: 'Questions people ask first',
        ),
        const SizedBox(height: 40),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            children: [
              for (final faq in SiteCopy.faqs) FaqItem(faq: faq),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  Text('Still stuck? ', style: SiteText.cardBody(context)),
                  SiteLink(
                    label: 'Write to us',
                    style: SiteText.cardBody(context),
                    onTap: () => openExternal('mailto:${SitePlaceholders.supportEmail}'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FinalCta extends StatelessWidget {
  const _FinalCta();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Your reading is waiting',
          style: SiteText.section(context).copyWith(color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            SiteCopy.priceLine,
            style: SiteText.sectionSub(context).copyWith(color: SiteColors.onInkMuted),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 32),
        const StoreCta(onDark: true, alignment: WrapAlignment.center),
      ],
    );
  }
}

/// Lays cards out in 3/2/1 columns without nesting a scrollable inside the page.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.children, this.max = 3});

  final List<Widget> children;
  final int max;

  @override
  Widget build(BuildContext context) {
    final columns = gridColumns(context, max: max);
    const spacing = 24.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}
