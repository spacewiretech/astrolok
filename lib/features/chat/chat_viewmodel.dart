import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/astro_message.dart';
import '../../data/providers.dart';
import '../../data/repositories/chat_repository.dart';
import 'chat_copy.dart';
import 'chat_state.dart';
import 'chat_threads_viewmodel.dart';

/// Runs one conversation.
///
/// Keyed by thread id, or by [ChatThread.draftId] for a conversation that has not been sent yet.
/// The key deliberately does *not* change when a draft is given a real id by the server — that
/// arrives in [ChatState.threadId] instead. Rekeying mid-send would build a second, empty
/// instance and tear this one down with the reply still in flight, so the user would watch their
/// answer appear and then vanish into a spinner.
///
/// Does not navigate — the view acts on [ChatState.outcome], following the convention that a
/// ViewModel never touches the router.
class ChatViewModel extends AutoDisposeFamilyNotifier<ChatState, String> {
  bool _disposed = false;

  @override
  ChatState build(String threadId) {
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

    // A draft has nothing to fetch, so it must not open on a spinner that will never resolve.
    return ChatState(loading: threadId != ChatThread.draftId);
  }

  /// True while this instance is a conversation that exists only on the device.
  bool get _isDraft => arg == ChatThread.draftId;

  /// Where the next turn should go: the id the server gave us, else the one we were opened with.
  String? get _target => state.threadId ?? (_isDraft ? null : arg);

  /// Paints from the cache first, then reconciles with the server.
  ///
  /// The cache is what makes reopening the app instant, and what makes yesterday's counsel
  /// readable on a train with no signal. The server is the truth, so it wins whenever it
  /// answers — but it never gets to leave the screen empty while it thinks.
  Future<void> _load() async {
    if (_isDraft) {
      // Nothing to load and nothing to reconcile. Straight to the opening screen.
      await _prepareSpeech();
      return;
    }

    final cached = await ref.read(chatThreadStoreProvider).load(arg);
    if (_disposed) return;

    if (cached != null && cached.messages.isNotEmpty) {
      state = state.copyWith(
        messages: cached.messages,
        title: cached.title,
        threadId: cached.id,
        remaining: cached.remaining,
        loading: false,
      );
    }

    try {
      final snapshot = await ref.read(chatRepositoryProvider).history(arg);
      if (_disposed) return;

      state = state.copyWith(
        messages: snapshot.messages,
        title: snapshot.title,
        threadId: arg,
        remaining: snapshot.remaining,
        loading: false,
      );
      await _cache();
    } on ChatSignedOutException {
      if (_disposed) return;
      state = state.copyWith(loading: false, outcome: ChatOutcome.signedOut);
    } on ChatThreadGoneException {
      // Deleted on another device, or aged out. Nothing to retry and nothing to show, so the
      // view opens a new conversation rather than leaving the user staring at a transcript that
      // does not exist. Its own copy, not the server's: the server explains, this one also says
      // what is about to happen.
      if (_disposed) return;
      state = state.copyWith(
        loading: false,
        messages: const [],
        error: ChatCopy.threadGone,
        outcome: ChatOutcome.threadGone,
      );

      // And out of the cache and the sidebar, or it would still be listed to tap again.
      await ref.read(chatThreadStoreProvider).remove(arg);
      ref.invalidate(chatThreadsProvider);
      return;
    } catch (error) {
      // A history that will not load is not worth an error screen when there is a cache to show,
      // and not worth one when there is not either — an empty chat is a chat you can start.
      debugPrint('[chat] could not load the conversation: $error');
      if (_disposed) return;
      state = state.copyWith(loading: false);
    }

    await _prepareSpeech();
  }

  Future<void> _prepareSpeech() async {
    if (_disposed) return;
    final canSpeak = await ref.read(readingSpeechProvider).prepare();
    if (_disposed) return;
    state = state.copyWith(canSpeak: canSpeak, loading: false);
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
      clearRevealing: true,
    );

    try {
      final reply = await ref.read(chatRepositoryProvider).send(
            trimmed,
            threadId: _target,
          );
      if (_disposed) return;

      state = state.copyWith(
        messages: [...state.messages, reply.message],
        threadId: reply.threadId,
        title: state.title.isEmpty ? reply.threadTitle : state.title,
        remaining: reply.remaining,
        sending: false,
        // The one message allowed to animate itself in.
        revealingId: reply.message.id,
      );
      await _cache();

      // The sidebar has a new conversation in it, or an existing one has moved to the top and
      // changed its preview. Either way what it is showing is now stale.
      ref.invalidate(chatThreadsProvider);
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

  /// Called once a reply has finished animating in, so it does not do it again on the next
  /// rebuild — a keyboard opening should not replay the last answer.
  void revealed(String id) {
    if (state.revealingId == id) state = state.copyWith(clearRevealing: true);
  }

  Future<void> _cache() async {
    final id = state.threadId;
    // A draft that has not reached the server has no id to key a cache entry on, and caching it
    // under a fixed one would have every new conversation overwrite the last.
    if (id == null) return;

    await ref.read(chatThreadStoreProvider).save(
          ChatThread(
            id: id,
            title: state.title,
            messages: state.messages,
            remaining: state.remaining,
            updatedAt: DateTime.now(),
          ),
        );
  }
}

final chatViewModelProvider =
    AutoDisposeNotifierProviderFamily<ChatViewModel, ChatState, String>(ChatViewModel.new);

/// Which conversation the chat screen is showing.
///
/// Held in a provider rather than in the route, so a draft does not have to be given a URL it
/// does not have an id for yet. Same cross-screen-signal pattern as `palmRejectionProvider`.
final selectedThreadProvider = StateProvider<String>((_) => ChatThread.draftId);
