import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/models/astro_message.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/audio_bars.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/safe_asset.dart';
import 'chat_composer.dart';
import 'chat_copy.dart';
import 'chat_drawer.dart';
import 'chat_reveal.dart';
import 'chat_state.dart';
import 'chat_threads_viewmodel.dart';
import 'chat_viewmodel.dart';

/// The conversation with Astro.
///
/// One of several: the drawer holds the rest. Which one is on screen lives in
/// [selectedThreadProvider] rather than in the route, because a conversation that has not been
/// sent yet has no id to put in a URL — see [ChatViewModel] for why rekeying it mid-send would
/// lose the reply in flight.
class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key, this.opener});

  /// A question to ask on arrival, handed over from wherever the chat was opened.
  ///
  /// This is what makes "Ask Astro about your eyes" land in a conversation already about the
  /// eyes rather than on a blank screen. It always starts a *new* conversation: the question is
  /// about a reading the user is looking at now, and appending it to whatever they last talked
  /// about would bury it.
  final String? opener;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _scroll = ScrollController();
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();

    final opener = widget.opener?.trim();

    // Deferred: both of these touch providers, and doing that during the first build throws
    // "modified a provider while the widget tree was building".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Home usually has the conversations loaded by now, but this screen is also reached straight
      // from a reading's "Ask Astro". Warmed here so the drawer never has to fetch for itself; it
      // is a no-op once the list is up.
      final threads = ref.read(chatThreadsProvider);

      analytics.track(Ev.chatOpened, {
        // An opener means the user arrived from a reading's "Ask Astro" with a question already
        // written, which is a different conversation from one started cold on Home.
        P.hasOpener: opener != null && opener.isNotEmpty,
        P.source: opener != null && opener.isNotEmpty ? 'reading' : 'direct',
        P.threadCount: threads.valueOrNull?.length,
      });

      if (opener != null && opener.isNotEmpty) {
        ref.read(selectedThreadProvider.notifier).state = ChatThread.draftId;
        ref
            .read(chatViewModelProvider(ChatThread.draftId).notifier)
            .send(opener, entry: 'opener');
      }
    });
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
      case ChatOutcome.threadGone:
        // Not a redirect off the screen — the user still wants to talk to Astro, they just
        // cannot have that conversation back.
        _newChat();
    }
  }

  /// Starts a fresh conversation.
  ///
  /// The draft instance is invalidated first: tapping "New chat" while already on an unsent one
  /// must clear it, and without this the key would not change so nothing would happen.
  void _newChat() {
    // The intent to start one, not a thread on the server — a draft only becomes real on its
    // first turn. `Chat Message Sent` with turn_index 0 is what says they went through with it,
    // and the gap between the two is people opening a blank chat and thinking better of it.
    analytics.track(Ev.chatThreadCreated, {P.source: 'drawer'});
    ref.invalidate(chatViewModelProvider(ChatThread.draftId));
    ref.read(selectedThreadProvider.notifier).state = ChatThread.draftId;
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedThreadProvider);
    final state = ref.watch(chatViewModelProvider(selected));
    final model = ref.read(chatViewModelProvider(selected).notifier);

    ref.listen(chatViewModelProvider(selected).select((s) => s.error), (_, error) {
      if (error == null || !mounted) return;
      showAppSnackBar(context, error, error: true);
      // Cleared once shown, or a later rebuild would show it a second time.
      model.errorShown();
    });

    ref.listen(chatViewModelProvider(selected).select((s) => s.outcome), (_, outcome) {
      if (outcome != null) _handle(outcome);
    });

    return Scaffold(
      key: _scaffold,
      // On the right, so the back button keeps the left corner it has on every other screen.
      endDrawer: ChatDrawer(
        // The server's id once there is one, not the provider key — a draft keeps the key
        // `draft` for the life of the visit, and without this the conversation the user is
        // actually in would sit unhighlighted in the list right after its first reply.
        selectedId: state.threadId ?? selected,
        onNewChat: _newChat,
        onOpen: (id) {
          analytics.track(Ev.chatThreadSwitched, {P.threadId: id});
          model.stopSpeech();
          ref.read(selectedThreadProvider.notifier).state = id;
        },
      ),
      body: AstralBackground(
        surface: AstralSurface.home,
        child: SafeArea(
          child: Column(
            children: [
              _Header(
                title: state.title,
                onBack: () {
                  model.stopSpeech();
                  context.canPop() ? context.pop() : context.go(Routes.home);
                },
                onHistory: () {
                  analytics.track(Ev.chatDrawerOpened);
                  _scaffold.currentState?.openEndDrawer();
                },
              ),

              Expanded(
                child: state.loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.gold),
                      )
                    : state.isEmpty
                        ? _Opening(onPick: (topic) {
                            analytics.track(Ev.chatTopicTapped, {P.topic: topic.name});
                            model.send(topic.opener, entry: 'topic');
                          })
                        : _Transcript(
                            state: state,
                            controller: _scroll,
                            onSpeak: model.toggleSpeech,
                            onRevealed: model.revealed,
                          ),
              ),

              ChatComposer(
                state: state,
                onSend: (message, entry) => model.send(message, entry: entry),
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
  const _Header({
    required this.title,
    required this.onBack,
    required this.onHistory,
  });

  /// The conversation's name, once it has one. Falls back to the screen's own title, which is
  /// what a new chat shows.
  final String title;

  final VoidCallback onBack;
  final VoidCallback onHistory;

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
          Expanded(
            child: title.isEmpty
                ? const AccentHeading(
                    lead: ChatCopy.titleLead,
                    accent: ChatCopy.titleAccent,
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppText.section,
                    ),
                  ),
          ),
          CircleIconButton(
            icon: Icons.menu_rounded,
            semanticLabel: ChatCopy.openConversations,
            onTap: onHistory,
          ),
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
    required this.onRevealed,
  });

  final ChatState state;
  final ScrollController controller;
  final ValueChanged<AstroMessage> onSpeak;
  final ValueChanged<String> onRevealed;

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
                  // Keyed by message id so the list cannot recycle one reply's half-finished
                  // reveal into the widget showing another.
                  key: ValueKey(message.id),
                  message: message,
                  canSpeak: state.canSpeak,
                  speaking: state.speakingId == message.id,
                  // Only the reply that just arrived. Everything else — history, the cache, a
                  // bubble scrolled back into view — is already finished.
                  revealing: state.revealingId == message.id,
                  onSpeak: () => onSpeak(message),
                  onRevealed: () => onRevealed(message.id),
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

/// A reply: who is speaking and how to hear them, then the answer, then the reasoning.
///
/// The listen control sits in the header rather than at the foot of the bubble. It used to be
/// last, which meant the one genuinely delightful thing this app does — a pandit's voice reading
/// your counsel — was the thing you found only after scrolling past everything else.
class _AstroBubble extends StatelessWidget {
  const _AstroBubble({
    super.key,
    required this.message,
    required this.canSpeak,
    required this.speaking,
    required this.revealing,
    required this.onSpeak,
    required this.onRevealed,
  });

  final AstroMessage message;
  final bool canSpeak;
  final bool speaking;

  /// True only for the reply that just arrived. See [ChatReveal.active].
  final bool revealing;

  final VoidCallback onSpeak;
  final VoidCallback onRevealed;

  @override
  Widget build(BuildContext context) {
    return ChatReveal(
      active: revealing,
      verdict: message.verdict,
      onFinished: onRevealed,
      builder: (context, verdict, progress) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppShape.card,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SpeakerRow(
              canSpeak: canSpeak,
              speaking: speaking,
              onSpeak: onSpeak,
            ),

            // The answer, before anything that justifies it. Absent on replies written before
            // the field existed, which then render exactly as replies used to.
            if (message.verdict.isNotEmpty) ...[
              const SizedBox(height: 10),
              _VerdictCard(emoji: message.titleEmoji, text: verdict),
            ],

            RevealedPart(
              progress: progress,
              index: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  // The title keeps its emoji only when the verdict card above has not taken it.
                  if (message.title.isNotEmpty) ...[
                    _Titled(
                      emoji: message.verdict.isEmpty ? message.titleEmoji : '',
                      text: message.title,
                      heading: true,
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(message.text, style: AppText.body.copyWith(height: 1.45)),
                ],
              ),
            ),

            for (final (index, section) in message.sections.indexed)
              RevealedPart(
                progress: progress,
                index: index + 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    _Titled(emoji: section.emoji, text: section.heading),
                    const SizedBox(height: 3),
                    Text(section.body, style: AppText.body.copyWith(height: 1.45)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Who is talking, and the control that makes them talk out loud.
class _SpeakerRow extends StatelessWidget {
  const _SpeakerRow({
    required this.canSpeak,
    required this.speaking,
    required this.onSpeak,
  });

  final bool canSpeak;
  final bool speaking;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const BrandMark(size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            ChatCopy.speaker,
            style: AppText.tileLabel.copyWith(
              color: AppColors.muted,
              letterSpacing: 0.6,
            ),
          ),
        ),
        // Left out entirely when the device has no speech engine, rather than shown inert.
        if (canSpeak) _ListenLink(speaking: speaking, onTap: onSpeak),
      ],
    );
  }
}

/// The answer, set apart from the reasoning that follows it.
///
/// A card rather than a first paragraph in bold: the whole point of the change is that someone
/// who reads one thing reads the answer, and a run of prose does not survive being skimmed.
class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.emoji, required this.text});

  final String emoji;

  /// Arrives a character at a time while the reply is being revealed.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        color: AppColors.goldWash,
        borderRadius: AppShape.control,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (emoji.isNotEmpty) ...[
            Text(emoji, style: AppText.title.copyWith(fontSize: 17)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: AppText.title.copyWith(
                fontSize: 16,
                height: 1.4,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ),
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

/// Small enough to sit inside a bubble's header without competing with it.
///
/// Not the shared `SpeakButton`, which is a pill sized for the bottom of a reading screen — one
/// of those on every reply would turn the transcript into a column of buttons. It does share
/// [AudioBars] with it, so "this is playing" looks the same everywhere in the app.
class _ListenLink extends StatelessWidget {
  const _ListenLink({required this.speaking, required this.onTap});

  final bool speaking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: speaking ? ChatCopy.stopListening : ChatCopy.listen,
      excludeSemantics: true,
      child: Material(
        color: speaking ? AppColors.goldWash : Colors.transparent,
        borderRadius: AppShape.pill,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (speaking)
                  const AudioBars(speaking: true, color: AppColors.goldDeep, size: 14)
                else
                  const Icon(
                    Icons.volume_up_rounded,
                    size: 16,
                    color: AppColors.goldDeep,
                  ),
                const SizedBox(width: 6),
                Text(
                  speaking ? ChatCopy.stopListening : ChatCopy.listen,
                  style: AppText.meta.copyWith(
                    fontSize: 13,
                    color: AppColors.goldDeep,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
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
