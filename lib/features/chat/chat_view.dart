import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/language.dart';
import '../../data/models/astro_message.dart';
import '../../widgets/app_snackbar.dart';
import 'chat_app_bar.dart';
import 'chat_birth_time_sheet.dart';
import 'chat_bubble.dart';
import 'chat_composer.dart';
import 'chat_copy.dart';
import 'chat_drawer.dart';
import 'chat_greeting.dart';
import 'chat_palette.dart';
import 'chat_state.dart';
import 'chat_threads_viewmodel.dart';
import 'chat_typing.dart';
import 'chat_viewmodel.dart';
import 'chat_wallpaper.dart';

/// A chat screen opened with something already written.
///
/// The in-app "Ask Astro" buttons pass a bare [String] to `/chat` and it sends itself, which is right
/// there: the user tapped a button under a reading they were looking at. A push is not that. It
/// arrives unasked, up to six times a day, so it fills the composer and waits — see [autoSend], which
/// the server can turn on later through `notif_drip_chat_autosend` without another release.
@immutable
class ChatLaunch {
  const ChatLaunch({required this.question, required this.source, this.autoSend = false});

  final String question;

  /// Where the question came from, for `Chat Opened`. Carried rather than inferred from [autoSend]:
  /// the two stopped meaning the same thing the moment a push could send on arrival too, and a
  /// funnel that reports every drip push as a reading is worse than no funnel.
  final String source;

  /// Send it on arrival, or write it into the composer and wait. A reading's "Ask Astro" sends,
  /// because the user just tapped it. A push follows `notif_drip_chat_autosend`, server-side.
  final bool autoSend;

  @override
  bool operator ==(Object other) =>
      other is ChatLaunch &&
      other.question == question &&
      other.source == source &&
      other.autoSend == autoSend;

  @override
  int get hashCode => Object.hash(question, source, autoSend);

  @override
  String toString() => 'ChatLaunch(${question.length} chars, from $source, autoSend: $autoSend)';
}

/// A question a push wants asked, parked here instead of riding go_router's `extra`.
///
/// `extra` is an in-process object attached to one route entry, and it does not survive a cold
/// start: a push tapped from a *terminated* app is replayed after the splash resolves, the route is
/// built a second time, and the second build gets `extra: null`. The symptom is exact — chat opens
/// (the route string survived) with an empty composer (the object did not). Tapped from the
/// background, where the router is already up and the route is built once, the same push works.
///
/// Parking it here instead makes it independent of how many times the route is built. [ChatView]
/// takes whichever arrives and clears this the moment it has it, so a later, deliberate visit to
/// chat never inherits yesterday's question.
final pendingChatLaunchProvider = StateProvider<ChatLaunch?>((_) => null);

/// The conversation with Astro.
///
/// One of several: the drawer holds the rest. Which one is on screen lives in
/// [selectedThreadProvider] rather than in the route, because a conversation that has not been
/// sent yet has no id to put in a URL — see [ChatViewModel] for why rekeying it mid-send would
/// lose the reply in flight.
class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key, this.launch});

  /// A question to arrive with, from wherever the chat was opened.
  ///
  /// This is what makes "Ask Astro about your eyes" land in a conversation already about the
  /// eyes rather than on a blank screen. It always starts a *new* conversation: the question is
  /// about a reading the user is looking at now, and appending it to whatever they last talked
  /// about would bury it.
  ///
  /// [ChatLaunch.autoSend] decides whether it is sent or merely written. An in-app "Ask Astro"
  /// button sends, because the user just tapped it under the reading it is about. A push fills the
  /// composer and waits: it arrived unasked, and the user should see the question before it costs
  /// them a turn.
  final ChatLaunch? launch;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _scroll = ScrollController();
  final _scaffold = GlobalKey<ScaffoldState>();

  /// The composer's field, held here so an ask for a birthplace can put the cursor in it.
  final _composerFocus = FocusNode();

  /// Scrolled up far enough that a new message would arrive out of sight: the "↓" button shows.
  bool _awayFromLatest = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);

    // `extra` when chat was opened in-process; the provider when the push had to survive a cold
    // start. Reading both is what makes the two paths behave the same.
    final launch = widget.launch ?? ref.read(pendingChatLaunchProvider);
    final question = launch?.question.trim();
    final arrived = question != null && question.isNotEmpty;

    // Deferred: both of these touch providers, and doing that during the first build throws
    // "modified a provider while the widget tree was building".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Consumed — clear it before anything else can, so a question is asked once and only once.
      if (ref.read(pendingChatLaunchProvider) != null) {
        ref.read(pendingChatLaunchProvider.notifier).state = null;
      }

      final threads = ref.read(chatThreadsProvider);

      analytics.track(Ev.chatOpened, {
        P.hasOpener: arrived,
        P.source: arrived ? launch!.source : 'direct',
        P.threadCount: threads.valueOrNull?.length,
      });

      if (launch == null || question == null || question.isEmpty) return;

      ref.read(selectedThreadProvider.notifier).state = ChatThread.draftId;
      // Held until the next frame's build is watching it. With a conversation from the drawer
      // still selected, nothing watches the draft yet, so Riverpod would dispose it at the end of
      // this frame — taking the question with it, and a send already spent on the server.
      final hold = ref.listenManual(chatViewModelProvider(ChatThread.draftId), (_, _) {});
      WidgetsBinding.instance.addPostFrameCallback((_) => hold.close());
      final model = ref.read(chatViewModelProvider(ChatThread.draftId).notifier);

      if (launch.autoSend) {
        model.send(question, entry: launch.source);
      } else {
        // A push fills the composer and stops there. Sending on arrival would spend a turn and a
        // Gemini call the user never asked for, six times a day — and start six threads doing it.
        model.prefill(question);
        _composerFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  static const _scrollEase = Duration(milliseconds: 320);

  void _onScroll() {
    final away = _scroll.hasClients && _scroll.position.pixels > 320;
    if (away != _awayFromLatest) setState(() => _awayFromLatest = away);
  }

  /// Back to the newest message — when a turn starts, and when the "↓" button is tapped.
  ///
  /// The list is reversed, so the newest message is at offset 0 and stays pinned there as bubbles
  /// arrive; only someone who scrolled up to reread needs bringing back.
  void _toLatest() {
    if (!mounted || !_scroll.hasClients || _scroll.position.pixels == 0) return;
    _scroll.animateTo(0, duration: _scrollEase, curve: Curves.easeOutCubic);
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

  /// Starts a fresh conversation. The draft instance is invalidated first, so "New chat" on an
  /// unsent one still clears it.
  void _newChat() {
    analytics.track(Ev.chatThreadCreated, {P.source: 'drawer'});
    ref.invalidate(chatViewModelProvider(ChatThread.draftId));
    ref.read(selectedThreadProvider.notifier).state = ChatThread.draftId;
  }

  /// The birth-time picker, from the button under Astro's ask. Typing the time works too.
  Future<void> _pickBirthTime(ChatViewModel model) async {
    final sentence = await askBirthTime(context, source: 'reply');
    if (sentence == null || !mounted) return;
    model.send(sentence, entry: 'birth_time');
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedThreadProvider);
    final state = ref.watch(chatViewModelProvider(selected));
    final model = ref.read(chatViewModelProvider(selected).notifier);
    final greeting = ChatGreeting.of(ref.watch(languageProvider));

    ref.listen(chatViewModelProvider(selected).select((s) => s.error), (_, error) {
      if (error == null || !mounted) return;
      showAppSnackBar(context, error, error: true);
      // Cleared once shown, or a later rebuild would show it a second time.
      model.errorShown();
    });

    ref.listen(chatViewModelProvider(selected).select((s) => s.outcome), (_, outcome) {
      if (outcome != null) _handle(outcome);
    });

    ref.listen(chatViewModelProvider(selected).select((s) => s.sending), (_, sending) {
      if (sending) _toLatest();
    });

    return Scaffold(
      key: _scaffold,
      backgroundColor: ChatPalette.wallpaper,
      appBar: ChatAppBar(
        typing: state.typing,
        onBack: () {
          model.stopSpeech();
          context.canPop() ? context.pop() : context.go(Routes.home);
        },
        onMenu: (action) {
          switch (action) {
            case ChatMenuAction.conversations:
              analytics.track(Ev.chatDrawerOpened);
              _scaffold.currentState?.openEndDrawer();
            case ChatMenuAction.newChat:
              _newChat();
          }
        },
      ),
      // On the right, so the back button keeps the left corner it has on every other screen.
      endDrawer: ChatDrawer(
        // The server's id once there is one, not the provider key — a draft keeps the key
        // `draft` for the life of the visit.
        selectedId: state.threadId ?? selected,
        onNewChat: _newChat,
        onOpen: (id) {
          analytics.track(Ev.chatThreadSwitched, {P.threadId: id});
          model.stopSpeech();
          ref.read(selectedThreadProvider.notifier).state = id;
        },
      ),
      body: ChatWallpaper(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: state.loading
                    ? const Center(child: CircularProgressIndicator(color: ChatPalette.appBar))
                    : Stack(
                        children: [
                          _Conversation(
                            rows: _rows(state, greeting, model),
                            controller: _scroll,
                          ),
                          if (_awayFromLatest)
                            Positioned(
                              right: 12,
                              bottom: 10,
                              child: _JumpToLatest(onTap: _toLatest),
                            ),
                        ],
                      ),
              ),
              ChatComposer(
                state: state,
                greeting: greeting,
                focus: _composerFocus,
                onSend: (message, entry) => model.send(message, entry: entry),
                onDraftRestored: model.pendingRestored,
                onRate: (rating, comment) => model.rate(rating, comment: comment),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The conversation as rows, oldest first: the notice, a chip for each day, each message's
  /// bubbles, and at the foot either Astro typing or the buttons to answer with.
  List<Widget> _rows(ChatState state, ChatGreeting greeting, ChatViewModel model) {
    final now = DateTime.now();
    final rows = <Widget>[ChatNotice(text: greeting.note)];

    // A conversation not started yet opens the way a real one does: a message already waiting.
    if (state.isEmpty) {
      rows
        ..add(ChatDateChip(label: dayLabel(now, now)))
        ..add(ChatBubble(text: greeting.hello, outgoing: false, time: now, tail: true))
        ..add(
          ChatReplyButtons(
            options: [
              for (final (index, topic) in greeting.topics.indexed)
                (
                  topic,
                  () {
                    analytics.track(Ev.chatTopicTapped, {P.topic: _topicKeys[index]});
                    model.send(topic, entry: 'topic');
                  },
                ),
            ],
            onPick: null,
          ),
        );
      return rows;
    }

    DateTime? day;
    bool? lastOutgoing;

    for (final message in state.messages) {
      final bubbles = message.displayBubbles.take(state.visibleBubbles(message)).toList();
      // A reply held behind "typing…" has nothing on screen yet — not even its day's chip.
      if (bubbles.isEmpty) continue;

      final at = message.createdAt;
      final today = DateTime(at.year, at.month, at.day);
      if (day != today) {
        rows.add(ChatDateChip(label: dayLabel(at, now)));
        day = today;
        lastOutgoing = null;
      }

      final outgoing = message.isUser;
      for (final (index, text) in bubbles.indexed) {
        final last = index == bubbles.length - 1;
        rows.add(
          Padding(
            // Tight within a run from one side, looser where the speaker changes.
            padding: EdgeInsets.only(top: lastOutgoing == outgoing ? 2 : 8),
            child: ChatBubble(
              key: ValueKey('${message.id}:$index'),
              text: text,
              outgoing: outgoing,
              time: at,
              tail: lastOutgoing != outgoing,
              status: _ticks(state, message),
              linkPhones: message.kind == ReplyKind.care,
              // Read-aloud, on the last bubble of each of Astro's messages.
              onSpeak: !outgoing && last && state.canSpeak && !state.delivering
                  ? () => model.toggleSpeech(message)
                  : null,
              speaking: state.speakingId == message.id,
            ),
          ),
        );
        lastOutgoing = outgoing;
      }
    }

    if (state.typing) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: lastOutgoing == false ? 2 : 8),
          child: ChatTypingBubble(tail: lastOutgoing != false),
        ),
      );
      return rows;
    }

    final buttons = _answers(state, greeting, model);
    if (buttons.isNotEmpty && state.canSend) {
      rows.add(
        ChatReplyButtons(
          options: buttons,
          onPick: (index) => analytics.track(Ev.chatQuickReplyTapped, {
            P.optionIndex: index,
            P.label: buttons[index].$1,
            P.optionCount: buttons.length,
          }),
        ),
      );
    }
    return rows;
  }

  /// WhatsApp's ticks on one of the person's messages: while its turn is in flight, a clock, one
  /// grey tick, then blue as Astro starts typing — and blue from then on. Astro's carry none.
  static BubbleStatus _ticks(ChatState state, AstroMessage message) {
    if (!message.isUser) return BubbleStatus.none;
    // Only the newest can be in flight. Its local `pending-` id outlives the reply, so the id
    // alone cannot say it was answered.
    if (!state.sending || !identical(message, state.messages.last)) return BubbleStatus.read;
    return switch (state.sendStage) {
      SendStage.queued => BubbleStatus.pending,
      SendStage.sent => BubbleStatus.sent,
      SendStage.read => BubbleStatus.read,
    };
  }

  /// The buttons under Astro's newest message: a way to give the hour when it was asked for,
  /// then its suggestions — the first of which, after an offer, is the yes to today's upay.
  List<(String, VoidCallback)> _answers(
    ChatState state,
    ChatGreeting greeting,
    ChatViewModel model,
  ) {
    return [
      if (state.askFor == AskFor.birthTime) ...[
        (greeting.pickTime, () => _pickBirthTime(model)),
        (greeting.dontKnow, () => model.send(greeting.dontKnow, entry: 'birth_time')),
      ],
      if (state.askFor == AskFor.birthPlace)
        (ChatCopy.birthPlaceAction, () => _composerFocus.requestFocus()),
      for (final option in state.options) (option, () => model.send(option, entry: 'quick_reply')),
    ];
  }

  /// `Chat Topic Tapped.topic`, by the greeting's topic order — the same six in every language.
  static const _topicKeys = ['marriage', 'love', 'children', 'home', 'career', 'money'];
}

/// The transcript: reversed, so new messages land at the bottom with no scroll arithmetic and it
/// stays pinned there while the keyboard opens.
class _Conversation extends StatelessWidget {
  const _Conversation({required this.rows, required this.controller});

  final List<Widget> rows;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final reversed = rows.reversed.toList(growable: false);
    return ListView.builder(
      controller: controller,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      itemCount: reversed.length,
      itemBuilder: (context, index) => reversed[index],
    );
  }
}

/// WhatsApp's round "↓", for someone who scrolled up to reread.
class _JumpToLatest extends StatelessWidget {
  const _JumpToLatest({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: ChatCopy.latest,
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.keyboard_double_arrow_down_rounded, color: ChatPalette.meta),
          ),
        ),
      ),
    );
  }
}
