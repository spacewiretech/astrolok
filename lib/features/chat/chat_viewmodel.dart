import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/astro_message.dart';
import '../../data/providers.dart';
import '../../data/repositories/chat_repository.dart';
import 'chat_copy.dart';
import 'chat_state.dart';

/// Runs the conversation.
///
/// Does not navigate — the view acts on [ChatState.outcome], following the convention that a
/// ViewModel never touches the router.
class ChatViewModel extends AutoDisposeNotifier<ChatState> {
  bool _disposed = false;

  @override
  ChatState build() {
    _disposed = false;

    // Resolved here, not inside onDispose: reading a provider from a container that is already
    // tearing down throws, and the dispose callback runs after this one is gone.
    final speech = ref.read(readingSpeechProvider);
    ref.onDispose(() {
      _disposed = true;
      // A reading that keeps talking after the user has left the screen is a one-star review.
      speech.stop();
    });

    _load();
    return const ChatState();
  }

  /// Paints from the cache first, then reconciles with the server.
  ///
  /// The cache is what makes reopening the app instant, and what makes yesterday's counsel
  /// readable on a train with no signal. The server is the truth, so it wins whenever it
  /// answers — but it never gets to leave the screen empty while it thinks.
  Future<void> _load() async {
    final cached = await ref.read(chatThreadStoreProvider).load();
    if (_disposed) return;

    if (cached != null && cached.messages.isNotEmpty) {
      state = state.copyWith(
        messages: cached.messages,
        remaining: cached.remaining,
        loading: false,
      );
    }

    try {
      final snapshot = await ref.read(chatRepositoryProvider).history();
      if (_disposed) return;

      state = state.copyWith(
        messages: snapshot.messages,
        remaining: snapshot.remaining,
        loading: false,
      );
      await _cache();
    } on ChatSignedOutException {
      if (_disposed) return;
      state = state.copyWith(loading: false, outcome: ChatOutcome.signedOut);
    } catch (error) {
      // A history that will not load is not worth an error screen when there is a cache to show,
      // and not worth one when there is not either — an empty chat is a chat you can start.
      debugPrint('[chat] could not load the conversation: $error');
      if (_disposed) return;
      state = state.copyWith(loading: false);
    }

    if (_disposed) return;
    final canSpeak = await ref.read(readingSpeechProvider).prepare();
    if (_disposed) return;
    state = state.copyWith(canSpeak: canSpeak);
  }

  /// Sends a message, showing it immediately.
  ///
  /// The user's turn is appended before the request goes out, so the transcript behaves the way
  /// every messaging app has taught people to expect. On failure it is taken back out and handed
  /// to the composer through [ChatState.pending] rather than left sitting in the transcript
  /// looking answered.
  Future<void> send(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || state.sending || state.exhausted) return;

    // Anything the sage is speaking is now about the previous turn.
    await stopSpeech();
    if (_disposed) return;

    final mine = AstroMessage(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      role: ChatRole.user,
      createdAt: DateTime.now(),
      text: trimmed,
    );

    state = state.copyWith(
      messages: [...state.messages, mine],
      sending: true,
      clearError: true,
      clearPending: true,
    );

    try {
      final reply = await ref.read(chatRepositoryProvider).send(trimmed);
      if (_disposed) return;

      state = state.copyWith(
        messages: [...state.messages, reply.message],
        remaining: reply.remaining,
        sending: false,
      );
      await _cache();
    } on ChatLimitReachedException catch (e) {
      // Not a failure the user can retry past, so the message comes back out and the composer
      // closes with the server's own explanation.
      _rollBack(mine, e.message, remaining: 0);
    } on ChatNotEntitledException catch (e) {
      _rollBack(mine, e.message, outcome: ChatOutcome.notEntitled);
    } on ChatSignedOutException catch (e) {
      _rollBack(mine, e.message, outcome: ChatOutcome.signedOut);
    } on ChatException catch (e) {
      _rollBack(mine, e.message);
    } catch (error) {
      debugPrint('[chat] send failed: $error');
      _rollBack(mine, ChatCopy.sendFailed);
    }
  }

  /// Takes a failed turn back out of the transcript and returns the words to the composer.
  void _rollBack(
    AstroMessage mine,
    String message, {
    int? remaining,
    ChatOutcome? outcome,
  }) {
    if (_disposed) return;

    state = state.copyWith(
      messages: state.messages.where((m) => m.id != mine.id).toList(),
      sending: false,
      error: message,
      pending: mine.text,
      remaining: remaining,
      outcome: outcome,
    );
  }

  /// Starts or stops narration of one message.
  Future<void> toggleSpeech(AstroMessage message) async {
    final speech = ref.read(readingSpeechProvider);

    if (state.speakingId == message.id) {
      await speech.stop();
      if (_disposed) return;
      state = state.copyWith(clearSpeaking: true);
      return;
    }

    state = state.copyWith(speakingId: message.id);
    await speech.speak(message.spoken);
    if (_disposed) return;

    // Only clear if nothing else has started speaking in the meantime.
    if (state.speakingId == message.id) state = state.copyWith(clearSpeaking: true);
  }

  Future<void> stopSpeech() async {
    if (state.speakingId == null) return;
    await ref.read(readingSpeechProvider).stop();
    if (_disposed) return;
    state = state.copyWith(clearSpeaking: true);
  }

  /// Clears a transient error once its snackbar has been shown, so a rebuild does not show it
  /// again.
  void errorShown() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  /// Clears the returned draft once the composer has taken it back.
  void pendingRestored() {
    if (state.pending != null) state = state.copyWith(clearPending: true);
  }

  Future<void> _cache() async {
    await ref.read(chatThreadStoreProvider).save(
          ChatThread(
            messages: state.messages,
            remaining: state.remaining,
            updatedAt: DateTime.now(),
          ),
        );
  }
}

final chatViewModelProvider =
    AutoDisposeNotifierProvider<ChatViewModel, ChatState>(ChatViewModel.new);
