import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/models/astro_message.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/safe_asset.dart';
import 'chat_composer.dart';
import 'chat_copy.dart';
import 'chat_state.dart';
import 'chat_viewmodel.dart';

/// The conversation with Astro.
///
/// One continuous thread rather than a list of them, as the design shows: someone consulting an
/// astrologer is having *a* conversation, and starting a second one would throw away everything
/// the first taught them.
class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key, this.opener});

  /// A question to ask on arrival, handed over from wherever the chat was opened.
  ///
  /// This is what makes "Ask Astro about your eyes" land in a conversation already about the
  /// eyes rather than on a blank screen.
  final String? opener;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();

    final opener = widget.opener?.trim();
    if (opener != null && opener.isNotEmpty) {
      // Deferred: sending touches a provider, and doing that during the first build throws
      // "modified a provider while the widget tree was building".
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(chatViewModelProvider.notifier).send(opener);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _handle(ChatOutcome outcome) {
    if (!mounted) return;

    switch (outcome) {
      case ChatOutcome.notEntitled:
        context.go(Routes.subscribe);
      case ChatOutcome.signedOut:
        context.go(Routes.onboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatViewModelProvider);
    final model = ref.read(chatViewModelProvider.notifier);

    ref.listen(chatViewModelProvider.select((s) => s.error), (_, error) {
      if (error == null || !mounted) return;
      showAppSnackBar(context, error, error: true);
      // Cleared once shown, or a later rebuild would show it a second time.
      model.errorShown();
    });

    ref.listen(chatViewModelProvider.select((s) => s.outcome), (_, outcome) {
      if (outcome != null) _handle(outcome);
    });

    return Scaffold(
      body: AstralBackground(
        surface: AstralSurface.home,
        child: SafeArea(
          child: Column(
            children: [
              _Header(
                onBack: () {
                  model.stopSpeech();
                  context.canPop() ? context.pop() : context.go(Routes.home);
                },
              ),

              Expanded(
                child: state.loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.gold),
                      )
                    : state.isEmpty
                        ? _Opening(onPick: (topic) => model.send(topic.opener))
                        : _Transcript(
                            state: state,
                            controller: _scroll,
                            onSpeak: model.toggleSpeech,
                          ),
              ),

              ChatComposer(
                state: state,
                onSend: model.send,
                onDraftRestored: model.pendingRestored,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppShape.gutter, 4, AppShape.gutter, 8),
      child: Row(
        children: [
          CircleIconButton(
            image: PalmIcon.backCircle,
            icon: Icons.chevron_left_rounded,
            semanticLabel: 'Back',
            onTap: onBack,
          ),
          const Expanded(
            child: AccentHeading(
              lead: ChatCopy.titleLead,
              accent: ChatCopy.titleAccent,
            ),
          ),
          // Balances the back button so the title sits centred.
          const SizedBox(width: AppShape.avatar),
        ],
      ),
    );
  }
}

/// The four topic pills, over a faint zodiac ring.
class _Opening extends StatelessWidget {
  const _Opening({required this.onPick});

  final ValueChanged<ChatTopic> onPick;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Drawn, not exported, and deliberately faint — atmosphere behind the pills rather than
        // anything to read.
        const Positioned(top: 40, child: ZodiacRing(diameter: 300)),

        ListView(
          padding: const EdgeInsets.fromLTRB(AppShape.gutter, 28, AppShape.gutter, 24),
          children: [
            Text(
              ChatCopy.openingGreeting,
              style: AppText.section,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              ChatCopy.openingSubtitle,
              style: AppText.meta,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            for (final topic in ChatTopic.values) ...[
              _TopicPill(topic: topic, onTap: () => onPick(topic)),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ],
    );
  }
}

class _TopicPill extends StatelessWidget {
  const _TopicPill({required this.topic, required this.onTap});

  final ChatTopic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppShape.pill,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: AppShape.pill,
            border: Border.all(color: AppColors.navy),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(topic.icon, size: 22, color: AppColors.gold),
              const SizedBox(width: 14),
              Expanded(child: Text(topic.label, style: AppText.title)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The conversation.
class _Transcript extends StatelessWidget {
  const _Transcript({
    required this.state,
    required this.controller,
    required this.onSpeak,
  });

  final ChatState state;
  final ScrollController controller;
  final ValueChanged<AstroMessage> onSpeak;

  @override
  Widget build(BuildContext context) {
    // Reversed, so a new turn appears at the bottom with no scroll arithmetic and the list stays
    // pinned there while the keyboard opens.
    final items = state.messages.reversed.toList();

    return ListView.builder(
      controller: controller,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(AppShape.gutter, 16, AppShape.gutter, 8),
      // One extra row at the visual bottom for the waiting bubble.
      itemCount: items.length + (state.sending ? 1 : 0),
      itemBuilder: (context, index) {
        if (state.sending && index == 0) return const _Thinking();

        final message = items[index - (state.sending ? 1 : 0)];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: message.isUser
              ? _UserBubble(text: message.text)
              : _AstroBubble(
                  message: message,
                  canSpeak: state.canSpeak,
                  speaking: state.speakingId == message.id,
                  onSpeak: () => onSpeak(message),
                ),
        );
      },
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        // Never the full width: a bubble that reaches both edges stops reading as a bubble.
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: AppShape.card,
          ),
          child: Text(
            text,
            style: AppText.body.copyWith(color: Colors.white, height: 1.4),
          ),
        ),
      ),
    );
  }
}

/// A reply: the oṃ disc, then the title, the opening and its labelled sections.
class _AstroBubble extends StatelessWidget {
  const _AstroBubble({
    required this.message,
    required this.canSpeak,
    required this.speaking,
    required this.onSpeak,
  });

  final AstroMessage message;
  final bool canSpeak;
  final bool speaking;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BrandMark(size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppShape.card,
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.title.isNotEmpty) ...[
                  _Titled(emoji: message.titleEmoji, text: message.title, heading: true),
                  const SizedBox(height: 6),
                ],
                Text(message.text, style: AppText.body.copyWith(height: 1.45)),

                for (final section in message.sections) ...[
                  const SizedBox(height: 12),
                  _Titled(emoji: section.emoji, text: section.heading),
                  const SizedBox(height: 3),
                  Text(section.body, style: AppText.body.copyWith(height: 1.45)),
                ],

                if (canSpeak) ...[
                  const SizedBox(height: 12),
                  _ListenLink(speaking: speaking, onTap: onSpeak),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// An emoji beside a heading, aligned so the two share a baseline.
class _Titled extends StatelessWidget {
  const _Titled({required this.emoji, required this.text, this.heading = false});

  final String emoji;
  final String text;
  final bool heading;

  @override
  Widget build(BuildContext context) {
    final style = AppText.title.copyWith(fontSize: heading ? 16 : 15);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (emoji.isNotEmpty) ...[
          Text(emoji, style: style),
          const SizedBox(width: 6),
        ],
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

/// Small enough to sit inside a bubble without competing with it.
///
/// Not the shared [SpeakButton], which is a pill sized for the bottom of a reading screen — one
/// of those under every reply would turn the transcript into a column of buttons.
class _ListenLink extends StatelessWidget {
  const _ListenLink({required this.speaking, required this.onTap});

  final bool speaking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppShape.pill,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              speaking ? Icons.stop_circle_outlined : Icons.volume_up_rounded,
              size: 17,
              color: AppColors.goldDeep,
            ),
            const SizedBox(width: 6),
            Text(
              speaking ? ChatCopy.stopListening : ChatCopy.listen,
              style: AppText.meta.copyWith(
                color: AppColors.goldDeep,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The wait, in character.
class _Thinking extends StatefulWidget {
  const _Thinking();

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandMark(size: 34),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppShape.card,
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SafeImage(
                  ChatIcon.spark,
                  width: 16,
                  height: 16,
                  fit: BoxFit.contain,
                  fallback: const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(width: 9),
                Text(ChatCopy.thinking, style: AppText.meta),
                const SizedBox(width: 9),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Opacity(
                          // Three dots a third of a cycle apart, so the group reads as thought
                          // rather than as a progress bar that has stalled.
                          opacity: 0.3 +
                              0.7 * (((_pulse.value + i / 3) % 1) < 0.5 ? 1 : 0),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: AppColors.gold,
                              shape: BoxShape.circle,
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
        ],
      ),
    );
  }
}
