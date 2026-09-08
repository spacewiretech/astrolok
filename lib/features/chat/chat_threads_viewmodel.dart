import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/astro_message.dart';
import '../../data/providers.dart';
import '../../data/repositories/chat_repository.dart';

/// Every conversation, for the sidebar.
///
/// Deliberately *not* auto-disposed. A `Scaffold.endDrawer` is only mounted while it is open, so
/// an auto-disposing list would lose its last listener every time the drawer closed and go back to
/// the network on the next open — the user watching the same unchanged list reassemble itself over
/// and over. Loaded once instead, warmed on Home before the drawer is ever opened, and kept.
///
/// Nothing re-fetches this afterwards: a new turn, a rename and a delete all rewrite the list in
/// place. The one deliberate re-sync is [refresh], which the drawer's pull-to-refresh calls.
///
/// Paints from the cache first, then reconciles — the same shape as loading a transcript, for the
/// same reason. A drawer that opens onto a spinner is a drawer that feels slower than the app it
/// belongs to, even when it is not.
class ChatThreadsViewModel extends AsyncNotifier<List<ChatThreadSummary>> {
  @override
  Future<List<ChatThreadSummary>> build() async {
    // Cached first. `state` is still loading here, so this paints the drawer while the request is
    // in flight rather than after it.
    final cached = await ref.read(chatThreadStoreProvider).recent();
    if (cached.isNotEmpty) state = AsyncData(cached);

    try {
      return (await ref.read(chatRepositoryProvider).threads()).threads;
    } on ChatSignedOutException {
      rethrow;
    } catch (error) {
      // A list that will not load is not worth an error state when there is a cache to show. The
      // conversations are all still on the server; this drawer is just a little behind.
      debugPrint('[chat] could not list the conversations: $error');
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  /// Re-reads the list from the server, without taking the current one off screen.
  ///
  /// Deliberately not `ref.invalidateSelf()`: that would drop back to [AsyncLoading] and put the
  /// drawer's spinner over a list the user is looking at. What is on screen stays there until the
  /// server has something better to say, and stays there too when it has nothing to say at all.
  Future<void> refresh() async {
    try {
      final list = await ref.read(chatRepositoryProvider).threads();
      state = AsyncData(list.threads);
    } catch (error) {
      debugPrint('[chat] could not refresh the conversations: $error');
    }
  }

  /// Moves a conversation to the top of the list, adding it if it is new.
  ///
  /// What a sent message does to the sidebar, without asking the server to tell us something we
  /// already know. The summary comes from the same [ChatThread.summary] the cache is written from,
  /// so the row reads identically whether it arrived this way or from a cold start.
  void noteTurn(ChatThreadSummary row) {
    // Nothing loaded yet — `build` is either running or about to, and it will bring the server's
    // list with this turn already in it.
    final before = state.valueOrNull;
    if (before == null) return;

    state = AsyncData([
      row,
      for (final thread in before)
        if (thread.id != row.id) thread,
    ]);
  }

  /// Drops a conversation the server no longer has.
  void forget(String id) {
    final before = state.valueOrNull;
    if (before == null) return;

    state = AsyncData([
      for (final thread in before)
        if (thread.id != id) thread,
    ]);
  }

  /// Renames a conversation, showing the new name before the server has confirmed it.
  ///
  /// Optimistic because the alternative is a row that keeps its old name for a round trip after
  /// the user has typed a new one, which reads as the rename having failed.
  Future<void> rename(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;

    final before = state.valueOrNull ?? const <ChatThreadSummary>[];
    state = AsyncData([
      for (final thread in before)
        if (thread.id == id)
          ChatThreadSummary(
            id: thread.id,
            title: trimmed,
            preview: thread.preview,
            lastMessageAt: thread.lastMessageAt,
          )
        else
          thread,
    ]);

    try {
      final list = await ref.read(chatRepositoryProvider).renameThread(id, trimmed);
      state = AsyncData(list.threads);
    } catch (error) {
      debugPrint('[chat] could not rename the conversation: $error');
      // Put the old name back rather than leaving a name the server does not have.
      state = AsyncData(before);
    }
  }

  /// Removes a conversation, taking it out of the list before the server has confirmed it.
  ///
  /// Returns false when the server refused, so the caller can say so — a conversation that
  /// reappears with no explanation is worse than one that never left.
  Future<bool> remove(String id) async {
    final before = state.valueOrNull ?? const <ChatThreadSummary>[];
    state = AsyncData([
      for (final thread in before)
        if (thread.id != id) thread,
    ]);

    try {
      final list = await ref.read(chatRepositoryProvider).deleteThread(id);
      // And out of the cache, or the next cold start would paint it back into the drawer and the
      // deletion would look as though it had silently failed.
      await ref.read(chatThreadStoreProvider).remove(id);
      state = AsyncData(list.threads);
      return true;
    } catch (error) {
      debugPrint('[chat] could not delete the conversation: $error');
      state = AsyncData(before);
      return false;
    }
  }
}

final chatThreadsProvider =
    AsyncNotifierProvider<ChatThreadsViewModel, List<ChatThreadSummary>>(
  ChatThreadsViewModel.new,
);
