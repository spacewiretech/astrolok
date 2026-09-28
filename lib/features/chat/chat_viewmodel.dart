import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_user.dart';
import '../../data/models/astro_message.dart';
import '../../data/models/birth_place.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/entitlement.dart';
import '../../data/language.dart';
import '../../data/providers.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/place_repository.dart';
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

  /// Which build of this conversation is on screen. "New chat" invalidates the draft, and
  /// Riverpod builds the same instance again rather than a new one — so [_disposed] is reset
  /// under a turn still in flight, and without this its reply would land in the new chat: an
  /// answer with no question, in a "new" chat that was the old thread all along. A turn checks
  /// the build it started in instead.
  int _generation = 0;

  /// The pause before the next bubble of the reply being delivered. Cancelled on dispose and on a
  /// new send — see [finishDelivery].
  Timer? _delivery;

  /// Moves the turn in flight from the clock to one tick to read — see [SendStage].
  Timer? _stage;

  /// Runs from the moment "typing…" goes up until it has been up for [ChatPacing.firstTyping]. A
  /// reply that lands meanwhile parks the showing of its first message in [_afterFloor].
  Timer? _typingFloor;
  VoidCallback? _afterFloor;

  /// Place-search session tokens already counted, so `Place Search Started` is one per search
  /// rather than one per keystroke — the kundali form's rule.
  final _placeSessions = <String>{};

  @override
  ChatState build(String threadId) {
    _disposed = false;
    _generation++;

    // Resolved here, not inside onDispose: reading a provider from a container that is already
    // tearing down throws, and the dispose callback runs after this one is gone.
    final speech = ref.read(readingSpeechProvider);
    ref.onDispose(() {
      _disposed = true;
      _delivery?.cancel();
      _stage?.cancel();
      _typingFloor?.cancel();
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
      ref.read(chatThreadsProvider.notifier).forget(arg);
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
    final canSpeak = await ref.read(readingSpeechProvider)
        .prepare(language: ref.read(languageProvider));
    if (_disposed) return;
    state = state.copyWith(canSpeak: canSpeak, loading: false);
  }

  /// Sends a message, showing it immediately.
  ///
  /// The user's turn is appended before the request goes out, so the transcript behaves the way
  /// every messaging app has taught people to expect. On failure it is taken back out and handed
  /// to the composer through [ChatState.pending] rather than left sitting in the transcript
  /// looking answered.
  ///
  /// [birthPlace] rides along when the message is a row picked in the place search. A turn that
  /// fails hands back only the words, and sending them again is a typed town, which the server
  /// looks up from the text — still answered, just by the likeliest match.
  Future<void> send(
    String message, {
    String entry = 'composer',
    ChatBirthPlace? birthPlace,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || state.sending || state.exhausted) return;

    final generation = _generation;
    bool gone() => _disposed || generation != _generation;

    final startedAt = DateTime.now();
    // Counted before the send, so a turn that fails still has its question counted. The two
    // together are the only way to see a conversation that ended because the app broke.
    final turnIndex = state.messages.where((m) => m.role == ChatRole.user).length;

    analytics.track(Ev.chatMessageSent, {
      P.threadId: state.threadId,
      // Which affordance produced the message. A topic pill, a quick reply and a typed sentence
      // are three different levels of intent, and the openers make the first two very cheap.
      P.entryMethod: entry,
      P.chars: trimmed.length,
      P.turnIndex: turnIndex,
    });

    // A reply still arriving bubble by bubble is shown whole the moment they answer it.
    finishDelivery();

    // Anything the sage is speaking is now about the previous turn.
    await stopSpeech();
    if (gone()) return;

    final mine = AstroMessage(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      role: ChatRole.user,
      createdAt: DateTime.now(),
      text: trimmed,
    );

    state = state.copyWith(
      messages: [...state.messages, mine],
      sending: true,
      sendStage: SendStage.queued,
      clearError: true,
      clearPending: true,
      clearRevealing: true,
    );
    _advanceStage();

    try {
      final reply = await ref.read(chatRepositoryProvider).send(
            trimmed,
            threadId: _target,
            entry: entry,
            birthPlace: birthPlace,
          );
      if (_disposed) return;

      // Before the state change below, so the language is in place by the time anything reads
      // the new reply — the listen control above all.
      final savedLanguage = reply.savedLanguage;
      if (savedLanguage != null) _adoptLanguage(savedLanguage);

      // A date or hour of birth given in the chat was saved: the account, its chart and Profile
      // move with it now rather than at the next sign-in.
      final saved = reply.user;
      if (saved != null) _adoptUser(saved);

      // Both of those are the account's, whichever chat is on screen. The rest is the chat's: a
      // "New chat" since the send has put another conversation here, and the reply belongs to the
      // one on the server, where it is saved and waiting.
      if (gone()) return;

      // An answer already given this run stands even if saving it failed; see
      // [chatRatingDoneProvider].
      final askRating = reply.askRating && !ref.read(chatRatingDoneProvider);
      if (askRating && !state.ratingDue) {
        analytics.track(Ev.chatRatingShown, {
          P.threadId: reply.threadId,
          P.turnIndex: turnIndex,
        });
      }

      _stage?.cancel();
      // Landed before Astro had "read" it: the typing starts now, with the reply held behind it.
      if (_typingFloor == null) _startTypingFloor();

      state = state.copyWith(
        messages: [...state.messages, reply.message],
        threadId: reply.threadId,
        title: state.title.isEmpty ? reply.threadTitle : state.title,
        remaining: reply.remaining,
        sending: false,
        sendStage: SendStage.queued,
        // The one message allowed to arrive bubble by bubble — none of it yet: [_deliver] decides
        // when the first shows, and paces the rest.
        revealingId: reply.message.id,
        shownBubbles: 0,
        ratingDue: askRating,
      );
      _deliver(reply.message);
      analytics.track(Ev.chatReplyReceived, {
        P.threadId: reply.threadId,
        P.turnIndex: turnIndex,
        P.ms: DateTime.now().difference(startedAt).inMilliseconds,
        // The shape of the answer. A reply with no sections and no options is a thin one, and
        // thin replies are what a conversation dies on.
        P.sectionCount: reply.message.sections.length,
        P.hasVerdict: reply.message.verdict.isNotEmpty,
        P.optionCount: reply.message.options.length,
        P.askFor: reply.message.askFor.name,
        P.bubbleCount: reply.message.displayBubbles.length,
        P.replyKind: reply.message.kind.name,
        P.offersRemedy: reply.message.offersRemedy,
        if (reply.message.topic.isNotEmpty) P.topic: reply.message.topic,
        // How much of the daily allowance is left. The turn where this hits zero is the turn a
        // conversation ends against its will.
        P.count: reply.remaining,
      });

      final cached = await _cache();

      // The sidebar has a new conversation in it, or an existing one has moved to the top and
      // changed its preview. Told rather than re-fetched: the summary written to the cache is the
      // same one the drawer would have got back from the server. Reading `.notifier` builds the
      // list if nothing has warmed it yet — one fetch, not one per drawer open.
      if (cached != null) {
        ref.read(chatThreadsProvider.notifier).noteTurn(cached.summary);
      }
    } on ChatLimitReachedException catch (e) {
      // Not a failure the user can retry past, so the message comes back out and the composer
      // closes with the server's own explanation.
      _rollBack(mine, e.message, remaining: 0, stale: gone());
    } on ChatNotEntitledException catch (e) {
      _rollBack(mine, e.message, outcome: ChatOutcome.notEntitled, stale: gone());
    } on ChatSignedOutException catch (e) {
      _rollBack(mine, e.message, outcome: ChatOutcome.signedOut, stale: gone());
    } on ChatException catch (e) {
      _rollBack(mine, e.message, stale: gone());
    } catch (error) {
      debugPrint('[chat] send failed: $error');
      _rollBack(mine, ChatCopy.sendFailed, stale: gone());
    }
  }

  /// The place search behind "📍 Jagah chunein" — `place-search`'s autocomplete, as the kundali
  /// form uses it, and no Details call after: the chat sends the picked row's id and the server
  /// resolves it (see `ChatBirthPlace`).
  Future<List<PlaceSuggestion>> searchPlaces(String query, String sessionToken) async {
    if (_placeSessions.add(sessionToken)) {
      analytics.track(Ev.placeSearchStarted, {P.source: 'chat'});
    }
    try {
      return await ref.read(placeRepositoryProvider).autocomplete(query, sessionToken: sessionToken);
    } on PlaceException catch (error) {
      analytics.track(Ev.placeSearchFailed, {
        P.code: error.runtimeType.toString(),
        P.source: 'chat',
      });
      rethrow;
    }
  }

  /// Installs a chat language the server saved from this conversation.
  ///
  /// Through the entitlement store, the same door Profile's picker uses, so the picker and the
  /// read-aloud voice both follow it at once — and into the session cache, or an offline relaunch
  /// would put the old language back. Never `invalidate`: see the note in `profile_view.dart`.
  void _adoptLanguage(String language) {
    final user = ref.read(entitlementProvider);
    if (user == null || user.chatLanguage == language) return;

    final updated = user.copyWith(chatLanguage: language);
    ref.read(entitlementProvider.notifier).set(updated);
    ref.read(sessionStoreProvider).cacheUser(updated).catchError((Object error) {
      debugPrint('[chat] could not cache the new language: $error');
    });
  }

  /// Installs the account a turn saved birth details onto — the same door Profile's birth-time
  /// picker uses, and into the session cache so an offline relaunch keeps it.
  void _adoptUser(AppUser user) {
    ref.read(entitlementProvider.notifier).set(user);
    ref.read(sessionStoreProvider).cacheUser(user).catchError((Object error) {
      debugPrint('[chat] could not cache the updated account: $error');
    });
  }

  /// Clock, then one grey tick, then read — and "typing…" with it. Cancelled when the reply lands,
  /// when the turn fails, and on dispose.
  void _advanceStage() {
    _stage?.cancel();
    _typingFloor?.cancel();
    _typingFloor = null;
    _afterFloor = null;
    final pacing = ref.read(chatPacingProvider);

    if (pacing.instant) {
      state = state.copyWith(sendStage: SendStage.read);
      return;
    }

    _stage = Timer(pacing.sentAfter, () {
      if (_disposed || !state.sending) return;
      state = state.copyWith(sendStage: SendStage.sent);
      _stage = Timer(pacing.readAfter - pacing.sentAfter, () {
        if (_disposed || !state.sending) return;
        state = state.copyWith(sendStage: SendStage.read);
        _startTypingFloor();
      });
    });
  }

  void _startTypingFloor() {
    final pacing = ref.read(chatPacingProvider);
    if (pacing.instant) return;
    _typingFloor = Timer(pacing.firstTyping, () {
      final release = _afterFloor;
      _afterFloor = null;
      release?.call();
    });
  }

  /// Sends [reply]'s bubbles one at a time, the way a person sends messages.
  ///
  /// The first shows at once if "typing…" has already been up for [ChatPacing.firstTyping] — the
  /// wait for the server was the typing — else once it has, so a reply that lands in a fraction
  /// of a second (a served upay) still reads as written rather than pasted. Each later one follows
  /// about two seconds on, behind "typing…" again.
  ///
  /// Display only: the whole reply is already in the transcript, the cache and the sidebar, so
  /// leaving the screen or switching conversations mid-delivery loses nothing — it simply shows
  /// whole the next time.
  void _deliver(AstroMessage reply) {
    _delivery?.cancel();
    final bubbles = reply.displayBubbles;
    final pacing = ref.read(chatPacingProvider);

    if (pacing.instant) {
      state = state.copyWith(shownBubbles: bubbles.length, clearRevealing: true);
      return;
    }

    void show(int count) {
      if (_disposed || state.revealingId != reply.id) return;
      if (count >= bubbles.length) {
        state = state.copyWith(shownBubbles: bubbles.length, clearRevealing: true);
        return;
      }
      state = state.copyWith(shownBubbles: count);
      _delivery = Timer(pacing.pauseBefore(bubbles[count]), () => show(count + 1));
    }

    if (_typingFloor?.isActive ?? false) {
      _afterFloor = () => show(1);
    } else {
      show(1);
    }
  }

  /// Shows the reply being delivered in full, now — when they send another message before it has
  /// finished arriving.
  void finishDelivery() {
    _delivery?.cancel();
    _delivery = null;
    if (state.revealingId != null) state = state.copyWith(clearRevealing: true);
  }

  /// Answers the rating card: 1 (worst) to 5 (best) with an optional written [comment], or null
  /// for a dismissal, which never carries one.
  ///
  /// The card goes before the request does, and does not come back this run whatever the request
  /// does. A rating is not worth an error on screen: a failure is logged and dropped, and at worst
  /// the server asks again on some later reply.
  Future<void> rate(int? rating, {String? comment}) async {
    final threadId = state.threadId;
    if (!state.ratingDue || threadId == null) return;

    final trimmed = comment?.trim() ?? '';
    final written = rating == null || trimmed.isEmpty ? null : trimmed;

    ref.read(chatRatingDoneProvider.notifier).state = true;
    state = state.copyWith(ratingDue: false);

    analytics.track(rating == null ? Ev.chatRatingDismissed : Ev.chatRated, {
      P.threadId: threadId,
      P.rating: ?rating,
      // Whether anything was written, and how much — never the words. Free text stays out of
      // Mixpanel the same way chat messages do; the comment itself is read in `chat_feedback`.
      if (rating != null) P.hasComment: written != null,
      P.commentChars: ?written?.length,
      P.turnIndex: state.messages.where((m) => m.isUser).length,
      P.chatLanguage: ref.read(languageProvider),
    });

    try {
      await ref
          .read(chatRepositoryProvider)
          .rate(threadId: threadId, rating: rating, comment: written);
    } catch (error) {
      debugPrint('[chat] could not save the rating: $error');
    }
  }

  /// Takes a failed turn back out of the transcript and returns the words to the composer.
  ///
  /// The single failure exit, so every way a turn can fail is counted with its reason —
  /// `limit_reached` and `not_entitled` are the product working as designed, and only the rest
  /// are something broken.
  ///
  /// [stale]: the screen has moved on since the send — left, or a new chat started — so the
  /// failure is counted and nothing else. The timers are a newer turn's by now, if anyone's.
  void _rollBack(
    AstroMessage mine,
    String message, {
    int? remaining,
    ChatOutcome? outcome,
    bool stale = false,
  }) {
    analytics.track(Ev.chatReplyFailed, {
      P.threadId: state.threadId,
      P.reason: outcome?.name ?? (remaining == 0 ? 'limit_reached' : 'failed'),
      P.message: message,
      P.chars: mine.text.length,
    });
    if (stale) return;

    _stage?.cancel();
    _typingFloor?.cancel();
    _afterFloor = null;

    state = state.copyWith(
      messages: state.messages.where((m) => m.id != mine.id).toList(),
      sending: false,
      sendStage: SendStage.queued,
      error: message,
      pending: mine.text,
      remaining: remaining,
      outcome: outcome,
    );
  }

  /// Starts or stops narration of one message.
  Future<void> toggleSpeech(AstroMessage message) async {
    analytics.track(
      state.speakingId == message.id
          ? Ev.readingNarrationStopped
          : Ev.readingNarrated,
      {
        P.feature: ReadingFeature.chat,
        P.surface: 'chat',
        P.threadId: state.threadId,
        P.sectionCount: message.sections.length,
      },
    );

    final speech = ref.read(readingSpeechProvider);

    if (state.speakingId == message.id) {
      await speech.stop();
      if (_disposed) return;
      state = state.copyWith(clearSpeaking: true);
      return;
    }

    // The language may have moved since the screen opened — someone wrote in Devanagari and the
    // server saved Hindi — and a Hindi reply handed to an English voice is read as silence. A
    // no-op when nothing has changed.
    final canSpeak = await speech.prepare(language: ref.read(languageProvider));
    if (_disposed) return;
    if (!canSpeak) {
      state = state.copyWith(canSpeak: false);
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

  /// Puts a question in the composer without sending it.
  ///
  /// For a push, which arrives unasked: the user sees what they are about to ask and sends it
  /// themselves. It rides the same channel a failed turn uses to hand its words back, so the
  /// composer needs no second way to be filled.
  ///
  /// Refuses if anything is already written or in flight — a push that lands while someone is
  /// mid-sentence must not overwrite them.
  void prefill(String question) {
    final text = question.trim();
    if (text.isEmpty || state.pending != null || state.sending) return;
    state = state.copyWith(pending: text);
  }


  /// Writes the conversation to the cache, and hands it back so the caller can put the same
  /// conversation in the sidebar without asking the server for it a second time.
  Future<ChatThread?> _cache() async {
    final id = state.threadId;
    // A draft that has not reached the server has no id to key a cache entry on, and caching it
    // under a fixed one would have every new conversation overwrite the last.
    if (id == null) return null;

    final thread = ChatThread(
      id: id,
      title: state.title,
      messages: state.messages,
      remaining: state.remaining,
      updatedAt: DateTime.now(),
    );

    await ref.read(chatThreadStoreProvider).save(thread);
    return thread;
  }
}

/// The rhythm of a turn: when the ticks move, when "typing…" starts, and how long Astro "types"
/// before each message.
///
/// Conversation timing, not animation, so it holds under reduced motion too. A provider so tests
/// can make it instant.
@immutable
class ChatPacing {
  const ChatPacing({
    this.sentAfter = const Duration(milliseconds: 300),
    this.readAfter = const Duration(milliseconds: 900),
    this.firstTyping = const Duration(milliseconds: 1500),
    this.base = const Duration(milliseconds: 1500),
    this.perChar = const Duration(milliseconds: 7),
    this.shortest = const Duration(milliseconds: 1800),
    this.longest = const Duration(milliseconds: 2600),
  });

  /// Every tick and every bubble at once. For tests.
  const ChatPacing.instant()
      : sentAfter = Duration.zero,
        readAfter = Duration.zero,
        firstTyping = Duration.zero,
        base = Duration.zero,
        perChar = Duration.zero,
        shortest = Duration.zero,
        longest = Duration.zero;

  /// The clock turns to one grey tick.
  final Duration sentAfter;

  /// One tick turns to two blue ones, and "typing…" starts. From the send, not from [sentAfter].
  final Duration readAfter;

  /// The least "typing…" before a reply's first message, for a reply that lands faster.
  final Duration firstTyping;

  /// The pause before each later message: [base] plus [perChar] of it, within [shortest] and
  /// [longest] — about two seconds for the ~80 characters a v5 message runs to.
  final Duration base;
  final Duration perChar;
  final Duration shortest;
  final Duration longest;

  bool get instant => longest == Duration.zero;

  Duration pauseBefore(String bubble) {
    final ms = base.inMilliseconds + perChar.inMilliseconds * bubble.length;
    return Duration(
      milliseconds: ms.clamp(shortest.inMilliseconds, longest.inMilliseconds),
    );
  }
}

final chatPacingProvider = Provider<ChatPacing>((_) => const ChatPacing());

final chatViewModelProvider =
    AutoDisposeNotifierProviderFamily<ChatViewModel, ChatState, String>(ChatViewModel.new);

/// Which conversation the chat screen is showing.
///
/// Held in a provider rather than in the route, so a draft does not have to be given a URL it
/// does not have an id for yet. Same cross-screen-signal pattern as `palmRejectionProvider`.
final selectedThreadProvider = StateProvider<String>((_) => ChatThread.draftId);

/// Whether this account has answered the rating card during this run of the app.
///
/// Apart from [ChatState] because the card is once per account, not per conversation: an answer
/// given in one conversation must not leave the card up in the next. Not auto-disposing, for the
/// same reason as [selectedThreadProvider]. The server holds the real record; this only covers the
/// run in which saving the answer failed, so the card is not raised again straight away.
final chatRatingDoneProvider = StateProvider<bool>((_) => false);

/// Drops the signed-in user's conversations, for sign-out to call.
///
/// The sidebar list is kept alive for the whole app run — that is what makes the drawer open
/// without fetching — and the selected thread is a plain [StateProvider], so neither goes away on
/// its own. Without this, the next person to sign in on this device would open the drawer onto the
/// last person's conversations.
void forgetConversations(WidgetRef ref) {
  ref.invalidate(chatThreadsProvider);
  ref.invalidate(chatRatingDoneProvider);
  ref.read(selectedThreadProvider.notifier).state = ChatThread.draftId;
}
