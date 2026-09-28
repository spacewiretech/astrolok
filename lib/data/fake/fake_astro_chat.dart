import '../models/astro_message.dart';
import '../repositories/chat_repository.dart';

/// A scripted sage, for the tier with no Supabase configured.
///
/// Two jobs, the same two the other fakes have. It keeps the app walkable end to end on a
/// checkout that has never been pointed at a project, and it makes the chat screen's timing and
/// layout observable while building it — otherwise impossible without a deployed function and a
/// real model call per turn.
///
/// The replies are written in the register the prompt asks for: an answer committed to first, a
/// computed detail cited, a hedged claim, a question back, and a nakshatra that is only named
/// once a birth time is known. A fake that answered in lorem ipsum would hide exactly the layout
/// problems this exists to surface — three sections of real prose wrap very differently from
/// three short strings.
///
/// It seeds two finished conversations so the sidebar has something in it on a fresh checkout.
/// A drawer that is always empty is a drawer nobody notices is broken.
class FakeChatRepository implements ChatRepository {
  FakeChatRepository({this.latency = const Duration(milliseconds: 1400)}) {
    _seed();
  }

  /// Roughly what a text turn really costs. Long enough to see the waiting state, short enough
  /// not to make development tedious.
  final Duration latency;

  /// Transcripts by thread id, oldest turn first.
  final Map<String, List<AstroMessage>> _threads = {};
  final Map<String, ChatThreadSummary> _summaries = {};
  final List<AstroFact> _facts = [];

  int _turn = 0;
  int _nextId = 0;

  /// Once per account, like the server: answered or dismissed, the card is not raised again.
  bool _rated = false;

  /// Matches the default of `chat_rating_after_messages`, so the card shows up on a fresh
  /// checkout at the same point it would in production.
  static const _rateAfter = 5;

  /// True while the newest scripted reply is waiting for its offered upay to be accepted.
  bool _offered = false;

  @override
  Future<ChatReply> send(
    String message, {
    String? threadId,
    String entry = 'composer',
  }) async {
    await Future<void>.delayed(latency);

    // Unknown or absent means a new conversation, matching the server: a stale id must never
    // leave someone unable to talk.
    final id = threadId != null && _threads.containsKey(threadId)
        ? threadId
        : _open();

    final transcript = _threads[id]!;

    transcript.add(
      AstroMessage(
        id: 'fake-user-${_nextId++}',
        role: ChatRole.user,
        createdAt: DateTime.now(),
        text: message,
      ),
    );

    final reply = _scripted(_turn++, message);
    transcript.add(reply);

    final existing = _summaries[id]!;
    final title = existing.title.isNotEmpty
        ? existing.title
        : reply.title.isNotEmpty
            ? reply.title
            : 'Shaadi ka samay';
    _summaries[id] = ChatThreadSummary(
      id: id,
      title: title,
      preview: reply.displayBubbles.first,
      lastMessageAt: DateTime.now(),
    );

    return ChatReply(
      message: reply,
      threadId: id,
      threadTitle: title,
      remaining: 40 - _turn,
      askRating: !_rated && transcript.where((turn) => turn.isUser).length >= _rateAfter,
    );
  }

  @override
  Future<ChatThreadList> threads() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return ChatThreadList(
      threads: _sorted(),
      facts: List.unmodifiable(_facts),
      remaining: 40 - _turn,
    );
  }

  @override
  Future<ChatSnapshot> history(String threadId) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final transcript = _threads[threadId];
    if (transcript == null) {
      throw const ChatThreadGoneException('That conversation is no longer here.');
    }

    return ChatSnapshot(
      messages: List.unmodifiable(transcript),
      facts: List.unmodifiable(_facts),
      title: _summaries[threadId]?.title ?? '',
      remaining: 40 - _turn,
    );
  }

  @override
  Future<ChatThreadList> renameThread(String id, String title) async {
    final existing = _summaries[id];
    if (existing != null) {
      _summaries[id] = ChatThreadSummary(
        id: id,
        title: title,
        preview: existing.preview,
        lastMessageAt: existing.lastMessageAt,
      );
    }
    return threads();
  }

  @override
  Future<ChatThreadList> deleteThread(String id) async {
    _threads.remove(id);
    _summaries.remove(id);
    return threads();
  }

  @override
  Future<List<AstroFact>> forget({String? key}) async {
    if (key == null) {
      _facts.clear();
    } else {
      _facts.removeWhere((fact) => fact.key == key);
    }
    return List.unmodifiable(_facts);
  }

  @override
  Future<void> rate({required String threadId, int? rating, String? comment}) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _rated = true;
  }

  /// Newest conversation first, as the sidebar lists them.
  List<ChatThreadSummary> _sorted() {
    final rows = _summaries.values.toList()
      ..sort((a, b) {
        final left = a.lastMessageAt ?? DateTime(0);
        final right = b.lastMessageAt ?? DateTime(0);
        return right.compareTo(left);
      });
    return List.unmodifiable(rows);
  }

  String _open() {
    final id = 'fake-thread-${_nextId++}';
    _threads[id] = [];
    _summaries[id] = ChatThreadSummary(id: id, title: '', lastMessageAt: DateTime.now());
    return id;
  }

  /// Two conversations already had, so the drawer has something to group.
  ///
  /// Dated deliberately across the buckets `groupThreads` sorts into — one today, one last week —
  /// so the headings are visible without waiting a week to see them.
  void _seed() {
    final now = DateTime.now();

    _threads['fake-thread-seed-a'] = [
      AstroMessage(
        id: 'fake-seed-a-0',
        role: ChatRole.user,
        createdAt: now.subtract(const Duration(hours: 3)),
        text: 'Who was I in my previous life?',
      ),
      AstroMessage(
        id: 'fake-seed-a-1',
        role: ChatRole.astro,
        createdAt: now.subtract(const Duration(hours: 3)),
        verdict: 'You were a keeper of records — someone who counted and tended, near water.',
        titleEmoji: '🌙',
        title: 'Your Previous Birth',
        text: 'Your Chandra sits in Rohini, whose symbol is the cart and whose deity is Brahma. '
            'That is the mark of one who gathers, measures and makes things grow — a steward '
            'rather than a soldier, and rarely much thanked for it.',
        sections: const [
          AstroSection(
            emoji: '🌾',
            heading: 'What Carried Over',
            body: 'The patience for slow work, and a discomfort with being hurried.',
          ),
        ],
        options: const ['What did I leave unfinished?', 'Tell me of Shani'],
      ),
    ];
    _summaries['fake-thread-seed-a'] = ChatThreadSummary(
      id: 'fake-thread-seed-a',
      title: 'Your Previous Birth',
      preview: 'You were a keeper of records — someone who counted and tended, near water.',
      lastMessageAt: now.subtract(const Duration(hours: 3)),
    );

    _threads['fake-thread-seed-b'] = [
      AstroMessage(
        id: 'fake-seed-b-0',
        role: ChatRole.user,
        createdAt: now.subtract(const Duration(days: 4)),
        text: 'I want to know about my career.',
      ),
      AstroMessage(
        id: 'fake-seed-b-1',
        role: ChatRole.astro,
        createdAt: now.subtract(const Duration(days: 4)),
        verdict: 'Stay where you are a while longer. The change you want is already forming.',
        titleEmoji: '💼',
        title: 'What Your Chart Says Of Work',
        text: 'Guru turns toward your tenth house this season, and Guru rewards the one who is '
            'already standing where the opportunity lands. Vrishabha does not reward a scattered '
            'hand, and leaving now would scatter it.',
        sections: const [
          AstroSection(
            emoji: '🌱',
            heading: 'What To Tend',
            body: 'One thing, properly, and let the people above you see you doing it.',
          ),
        ],
        options: const ['And my family?', 'What should I avoid?'],
      ),
    ];
    _summaries['fake-thread-seed-b'] = ChatThreadSummary(
      id: 'fake-thread-seed-b',
      title: 'What Your Chart Says Of Work',
      preview: 'Stay where you are a while longer. The change you want is already forming.',
      lastMessageAt: now.subtract(const Duration(days: 4)),
    );

    _facts.add(const AstroFact(key: 'works_as', value: 'a schoolteacher in Pune'));
  }

  /// A v5 conversation, scripted: an answer that ends by offering the day's upay, the upay itself
  /// when they say yes, an ask for the hour, and a thank-you that answers with the refined window.
  ///
  /// Written in the register the v5 prompt asks for — short Hinglish messages, a window in the
  /// first one — because three real sentences wrap very differently from three short strings, and
  /// the chat screen's timing (typing between bubbles) is what this exists to make visible.
  AstroMessage _scripted(int turn, String said) {
    final id = 'fake-astro-${_nextId++}';
    final now = DateTime.now();
    final lower = said.toLowerCase();

    AstroMessage astro({
      required List<String> bubbles,
      ReplyKind kind = ReplyKind.answer,
      String topic = 'marriage',
      bool offer = false,
      List<String> options = const [],
      AskFor askFor = AskFor.none,
    }) {
      _offered = offer;
      return AstroMessage(
        id: id,
        role: ChatRole.astro,
        createdAt: now,
        bubbles: bubbles,
        // What an older build reads, as the server fills it.
        verdict: bubbles.length > 1 ? bubbles.first : '',
        text: bubbles.length > 1 ? bubbles.skip(1).join('\n\n') : bubbles.first,
        kind: kind,
        topic: topic,
        offersRemedy: offer,
        options: options,
        askFor: askFor,
      );
    }

    // They accepted the upay the last reply offered.
    if (_offered && RegExp(r'haan|ha |yes|upay|हाँ').hasMatch('$lower ')) {
      return astro(
        kind: ReplyKind.remedy,
        bubbles: const [
          'Agle 4 hafte har Shukravar Maa Katyayani ka mantra 11 baar padhiye.',
          'Kal wapas aaiye, upay ka asar dekhte hain.',
          'Ek baat bataiye — rishta ghar wale dhoond rahe hain ya aap khud?',
        ],
        options: const ['Ghar wale dhoond rahe hain', 'Main khud dhoond raha hoon'],
      );
    }

    // They answered the ask for the hour.
    if (RegExp(r'\d|pata nahi|i do not know').hasMatch(lower) && turn > 1) {
      _facts.add(const AstroFact(key: 'birth_time', value: 'the evening'));
      return astro(
        bubbles: const [
          'Shukriya! 7:30 PM note kar liya — galat ho to bata dijiye.',
          'Ab aur pakka: March se August 2027 ke beech naukri ke sabse acche chances hain.',
          'Kya main aapko aaj ka upay bataun? 🙏',
        ],
        topic: 'career',
        offer: true,
        options: const ['Haan, upay batao 🙏', 'Kis field mein?'],
      );
    }

    if (turn == 0) {
      return astro(
        bubbles: const [
          'Aapki kundali ke hisaab se 2027 ke middle se 2028 ke end tak shaadi ka sabse accha '
              'samay hai.',
          'Is time Shukra ki dasha chalegi, jo rishton ke liye shubh hai.',
          'Kya main aapko aaj ka upay bataun? 🙏',
        ],
        offer: true,
        options: const ['Haan, upay batao 🙏', 'Jeevansathi kaisa hoga?', 'Love ya arrange?'],
      );
    }

    if (turn == 2 || lower.contains('naukri') || lower.contains('career')) {
      return astro(
        kind: ReplyKind.ask,
        topic: 'career',
        bubbles: const [
          'Aap kis samay paida hue the? Jaise subah 7:30 ya raat 10 baje — isse main aur pakka '
              'bata sakta hoon.',
        ],
        askFor: AskFor.birthTime,
      );
    }

    return astro(
      kind: ReplyKind.chat,
      bubbles: const [
        'Aapka jeevansathi samajhdar aur shaant swabhav ka hoga.',
        'Rishta aapsi izzat aur dosti par tikega.',
      ],
      options: const ['Love ya arrange?', 'Ghar wale maanenge?', 'Naukri kab lagegi?'],
    );
  }
}
