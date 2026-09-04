import 'package:flutter/foundation.dart';

import '../../data/models/astro_message.dart';

/// Where a turn ended up, when it did not end up in the transcript.
enum ChatOutcome {
  /// The subscription lapsed mid-conversation.
  notEntitled,

  /// The session went away.
  signedOut,
}

/// The chat screen's state.
@immutable
class ChatState {
  const ChatState({
    this.messages = const [],
    this.loading = true,
    this.sending = false,
    this.remaining,
    this.error,
    this.pending,
    this.speakingId,
    this.canSpeak = false,
    this.outcome,
  });

  /// Oldest first, as a transcript reads. The view reverses it for layout.
  final List<AstroMessage> messages;

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
    int? remaining,
    String? error,
    String? pending,
    String? speakingId,
    bool? canSpeak,
    ChatOutcome? outcome,
    bool clearError = false,
    bool clearPending = false,
    bool clearSpeaking = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
      sending: sending ?? this.sending,
      remaining: remaining ?? this.remaining,
      error: clearError ? null : (error ?? this.error),
      pending: clearPending ? null : (pending ?? this.pending),
      speakingId: clearSpeaking ? null : (speakingId ?? this.speakingId),
      canSpeak: canSpeak ?? this.canSpeak,
      outcome: outcome ?? this.outcome,
    );
  }
}
