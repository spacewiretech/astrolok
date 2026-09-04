import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/astro_message.dart';
import '../../data/providers.dart';
import '../../data/repositories/chat_repository.dart';
import '../chat/chat_copy.dart';

/// What Astro remembers, and the two ways to unremember it.
@immutable
class MemoryState {
  const MemoryState({
    this.facts = const [],
    this.loading = true,
    this.busy = false,
    this.error,
  });

  final List<AstroFact> facts;
  final bool loading;

  /// A deletion is in flight. Both actions close, so a double tap cannot race.
  final bool busy;

  final String? error;

  MemoryState copyWith({
    List<AstroFact>? facts,
    bool? loading,
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    return MemoryState(
      facts: facts ?? this.facts,
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class MemoryViewModel extends AutoDisposeNotifier<MemoryState> {
  bool _disposed = false;

  @override
  MemoryState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    _load();
    return const MemoryState();
  }

  Future<void> _load() async {
    try {
      final snapshot = await ref.read(chatRepositoryProvider).history();
      if (_disposed) return;
      state = state.copyWith(facts: snapshot.facts, loading: false);
    } catch (error) {
      // An empty list and an unreachable server look the same on this screen, and the way out is
      // the same either way, so a failure is not worth its own state.
      debugPrint('[chat] could not load what Astro remembers: $error');
      if (_disposed) return;
      state = state.copyWith(loading: false);
    }
  }

  /// Forgets one fact, or everything when [key] is null.
  ///
  /// The list is replaced with the server's answer rather than with a local guess at it, so what
  /// is on screen afterwards is what the server actually holds.
  Future<void> forget({String? key}) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearError: true);

    try {
      final facts = await ref.read(chatRepositoryProvider).forget(key: key);
      if (_disposed) return;
      state = state.copyWith(facts: facts, busy: false);
    } on ChatException catch (e) {
      if (_disposed) return;
      state = state.copyWith(busy: false, error: e.message);
    } catch (error) {
      debugPrint('[chat] could not forget: $error');
      if (_disposed) return;
      state = state.copyWith(busy: false, error: ChatCopy.forgetFailed);
    }
  }

  void errorShown() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }
}

final memoryViewModelProvider =
    AutoDisposeNotifierProvider<MemoryViewModel, MemoryState>(MemoryViewModel.new);
