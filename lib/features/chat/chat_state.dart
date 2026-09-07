import 'package:flutter/foundation.dart';

import '../../data/models/astro_message.dart';

/// Where a turn ended up, when it did not end up in the transcript.
enum ChatOutcome {
  /// The subscription lapsed mid-conversation.
  notEntitled,

  /// The session went away.
  signedOut,

  /// The conversation is not there any more — deleted on another device, or aged out. Not a
  /// failure to retry: the screen opens a new conversation instead.
  threadGone,
}

/// The chat screen's state.
@immutable
class ChatState {
  const ChatState({
    this.messages = const [],
    this.loading = true,
    this.sending = false,
    this.threadId,
    this.title = '',
    this.remaining,
    this.error,
    this.pending,
    this.speakingId,
    this.revealingId,
    this.canSpeak = false,
    this.outcome,
  });

  /// Oldest first, as a transcript reads. The view reverses it for layout.
  final List<AstroMessage> messages;

  /// The server's id for this conversation, or null while it is still a draft.
  ///
  /// Set by the first reply. The screen's provider key does not change when it arrives — see
  /// [ChatThread.draftId] — so this is how a draft knows where its next turn should go.
  final String? threadId;

  /// What this conversation is called, for the header. Empty until the first reply names it.
  final String title;

  /// The first load, before anything can be painted.
  final bool loading;

  /// A turn is in flight. The composer closes and the waiting bubble appears.
  final bool sending;

  /// Questions left today. Null until the server has said.
  final int? remaining;

  /// A transient failure, shown as a snackbar. Not the same thing as the day's allowance, which
  /// is a standing condition and lives in [remaining].
  final String? error;

  /// What the user typed on a turn that failed, handed back so it can be restored to the
  /// composer rather than lost. Someone who has just written three sentences to an astrologer
  /// should not have to write them again because the network blinked.
  final String? pending;

  /// The id of the message being read aloud, or null. An id rather than a bool because only one
  /// bubble should show its stop button.
  final String? speakingId;

  /// The id of the one reply that should animate itself in, or null.
  ///
  /// Set when a reply arrives and never set for anything loaded from the cache or the server —
  /// the transcript is a `ListView.builder`, so without this every bubble would replay its
  /// entrance each time it scrolled back into view, and a cold start would look like the whole
  /// conversation was being typed at once.
  final String? revealingId;

  /// False when the device has no speech engine. The control is left out entirely rather than
  /// shown inert.
  final bool canSpeak;

  final ChatOutcome? outcome;

  /// True before the first turn — the opening screen with the four topic pills.
  bool get isEmpty => messages.isEmpty && !sending;

  /// The day's allowance is spent. Distinct from [sending]: one is a pause, the other is a wall.
  bool get exhausted => remaining != null && remaining! <= 0;

  bool get canSend => !sending && !exhausted;

  /// Quick replies, taken only from the newest Astro turn.
  ///
  /// Older ones are dropped deliberately: answering a question from six turns back would land
  /// the reply somewhere the user did not expect, and stale chips accumulating down the
  /// transcript would make the screen look like a form.
  List<String> get options {
    if (sending || messages.isEmpty) return const [];
    final last = messages.last;
    return last.isUser ? const [] : last.options;
  }

  /// What the newest Astro turn asked for, so the right control can be raised.
  AskFor get askFor {
    if (sending || messages.isEmpty) return AskFor.none;
    final last = messages.last;
    return last.isUser ? AskFor.none : last.askFor;
  }

  ChatState copyWith({
    List<AstroMessage>? messages,
    bool? loading,
    bool? sending,
    String? threadId,
    String? title,
    int? remaining,
    String? error,
    String? pending,
    String? speakingId,
    String? revealingId,
    bool? canSpeak,
    ChatOutcome? outcome,
    bool clearError = false,
    bool clearPending = false,
    bool clearSpeaking = false,
    bool clearRevealing = false,
    // Both exist because the drawer can now change conversations without leaving the screen. A
    // fresh thread starts with the day's allowance unknown again rather than inheriting the last
    // one's count, and a stale outcome left over from a lapsed-subscription reply would redirect
    // a screen the user has since navigated back into.
    bool clearRemaining = false,
    bool clearOutcome = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
      sending: sending ?? this.sending,
      threadId: threadId ?? this.threadId,
      title: title ?? this.title,
      remaining: clearRemaining ? null : (remaining ?? this.remaining),
      error: clearError ? null : (error ?? this.error),
      pending: clearPending ? null : (pending ?? this.pending),
      speakingId: clearSpeaking ? null : (speakingId ?? this.speakingId),
      revealingId: clearRevealing ? null : (revealingId ?? this.revealingId),
      canSpeak: canSpeak ?? this.canSpeak,
      outcome: clearOutcome ? null : (outcome ?? this.outcome),
    );
  }
}
