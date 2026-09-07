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

  @override
  Future<ChatReply> send(String message, {String? threadId}) async {
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

    final reply = _scripted(_turn++);
    transcript.add(reply);

    final existing = _summaries[id]!;
    final title = existing.title.isNotEmpty ? existing.title : reply.title;
    _summaries[id] = ChatThreadSummary(
      id: id,
      title: title,
      preview: reply.verdict.isNotEmpty ? reply.verdict : reply.text,
      lastMessageAt: DateTime.now(),
    );

    return ChatReply(
      message: reply,
      threadId: id,
      threadTitle: title,
      remaining: 40 - _turn,
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

  AstroMessage _scripted(int turn) {
    final id = 'fake-astro-${_nextId++}';
    final now = DateTime.now();

    // The first turn asks for the hour, as the real prompt is instructed to — so the ask_for
    // control and the time picker behind it are exercised without a model.
    if (turn == 0) {
      return AstroMessage(
        id: id,
        role: ChatRole.astro,
        createdAt: now,
        verdict: 'Patience is your inheritance — but tell me the hour, and I can say more.',
        titleEmoji: '🪔',
        title: 'Before We Begin',
        text: 'Come, sit. Your Chandra rests in Vrishabha, which is a patient sign and slow to '
            'give its trust — but the finer reading needs the hour you arrived. Tell me that, '
            'and I can name the nakshatra you were born beneath.',
        options: const ['Morning', 'Afternoon', 'Evening', 'I do not know'],
        askFor: AskFor.birthTime,
      );
    }

    if (turn == 1) {
      _facts.add(const AstroFact(key: 'birth_time', value: 'the morning'));
      return AstroMessage(
        id: id,
        role: ChatRole.astro,
        createdAt: now,
        verdict: 'You love slowly and then wholly. What is already near you matters most.',
        titleEmoji: '✨',
        title: 'Your Love Reading',
        text: 'Then your Moon sits in Rohini, the nakshatra of steady attachment. Those born '
            'beneath it tend to love slowly and then wholly, and to be more wounded by '
            'carelessness than by argument.',
        sections: const [
          AstroSection(
            emoji: '❤️',
            heading: 'Relationship Energy',
            body: 'A season for tending what already exists rather than seeking what does not.',
          ),
          AstroSection(
            emoji: '💞',
            heading: 'Love Opportunities',
            body: 'What comes is likelier to come through people who already know you.',
          ),
        ],
        options: const ['What of my career?', 'Tell me of Shani'],
      );
    }

    return AstroMessage(
      id: id,
      role: ChatRole.astro,
      createdAt: now,
      verdict: 'The season ahead asks for patience rather than courage.',
      titleEmoji: '💫',
      title: 'The Season Ahead',
      text: 'Rohini asks for patience, and the months after your next birthday will ask more of '
          'it than of your courage. What you plant quietly now tends to be what you are glad '
          'of later.',
      sections: const [
        AstroSection(
          emoji: '🌱',
          heading: 'What To Tend',
          body: 'One thing, properly. Vrishabha does not reward a scattered hand.',
        ),
      ],
      options: const ['And my family?', 'What should I avoid?'],
    );
  }
}
