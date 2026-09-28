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
/// window for a "kab", the chart's reason in plain words, and a question back. A fake that
/// answered in lorem ipsum would hide exactly the layout problems this exists to surface — four
/// real messages and three buttons wrap very differently from four short strings.
///
/// It seeds three finished conversations so the sidebar has something in it on a fresh checkout.
/// A drawer that is always empty is a drawer nobody notices is broken. One of them ends on the
/// offer of an upay the way v5 replies used to, so the yes chip those rows still carry can be
/// walked too.
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

  @override
  Future<ChatReply> send(
    String message, {
    String? threadId,
    String entry = 'composer',
    ChatBirthPlace? birthPlace,
  }) async {
    await Future<void>.delayed(latency);

    // Unknown or absent means a new conversation, matching the server: a stale id must never
    // leave someone unable to talk.
    final id = threadId != null && _threads.containsKey(threadId)
        ? threadId
        : _open();

    final transcript = _threads[id]!;
    // Read before this turn is added: the script follows what the last reply asked for.
    final replies = transcript.where((turn) => !turn.isUser).toList();

    transcript.add(
      AstroMessage(
        id: 'fake-user-${_nextId++}',
        role: ChatRole.user,
        createdAt: DateTime.now(),
        text: message,
      ),
    );

    _turn++;
    final reply = _scripted(
      said: message,
      last: replies.isEmpty ? null : replies.last,
      place: birthPlace,
    );
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

  /// Three conversations already had, so the drawer has something to group.
  ///
  /// Dated deliberately across the buckets `groupThreads` sorts into — today, yesterday, last
  /// week — so the headings are visible without waiting a week to see them.
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

    // Before the upay was folded into the answer, a v5 reply ended by offering it, with the yes as
    // its first button. Rows like this are in the database and must still be answerable.
    _threads['fake-thread-seed-c'] = [
      AstroMessage(
        id: 'fake-seed-c-0',
        role: ChatRole.user,
        createdAt: now.subtract(const Duration(days: 1)),
        text: 'Meri shaadi kab hogi?',
      ),
      AstroMessage(
        id: 'fake-seed-c-1',
        role: ChatRole.astro,
        createdAt: now.subtract(const Duration(days: 1)),
        kind: ReplyKind.answer,
        topic: 'marriage',
        offersRemedy: true,
        bubbles: const [
          'Aapki kundali ke hisaab se 2027 ke middle se 2028 ke end tak shaadi ka sabse accha '
              'samay hai.',
          'Is time Shukra ki dasha chalegi, jo rishton ke liye shubh hai.',
          'Kya main aapko aaj ka upay bataun? 🙏',
        ],
        options: const ['Haan, upay batao 🙏', 'Jeevansathi kaisa hoga?'],
      ),
    ];
    _summaries['fake-thread-seed-c'] = ChatThreadSummary(
      id: 'fake-thread-seed-c',
      title: 'Shaadi ka samay',
      preview: 'Aapki kundali ke hisaab se 2027 ke middle se 2028 ke end tak shaadi ka sabse accha',
      lastMessageAt: now.subtract(const Duration(days: 1)),
    );

    _facts.add(const AstroFact(key: 'works_as', value: 'a schoolteacher in Pune'));
  }

  /// A v5 conversation, scripted in the shape the server now writes: the answer, its reason, and
  /// a question back about their real situation — asking for the hour first, then the place — and
  /// on the third answer, once there is enough to go on, the upay and the invitation to come back,
  /// together in one message before the question. Four messages at most, and the rashi only in
  /// the first.
  ///
  /// Follows what the last reply asked for rather than reading the words, so the whole arc can be
  /// walked with the buttons alone. Every thread is about marriage: the point is the shape and the
  /// pacing, not a second astrologer.
  AstroMessage _scripted({
    required String said,
    required AstroMessage? last,
    required ChatBirthPlace? place,
  }) {
    final id = 'fake-astro-${_nextId++}';
    final now = DateTime.now();

    AstroMessage astro({
      required List<String> bubbles,
      ReplyKind kind = ReplyKind.answer,
      List<String> options = const [],
      AskFor askFor = AskFor.none,
    }) {
      return AstroMessage(
        id: id,
        role: ChatRole.astro,
        createdAt: now,
        bubbles: bubbles,
        // What an older build reads, as the server fills it.
        verdict: bubbles.length > 1 ? bubbles.first : '',
        text: bubbles.length > 1 ? bubbles.skip(1).join('\n\n') : bubbles.first,
        kind: kind,
        topic: 'marriage',
        options: options,
        askFor: askFor,
      );
    }

    // A yes to an upay offered by a reply from before the offer went away — the seeded thread.
    if (last != null &&
        last.offersRemedy &&
        RegExp(r'haan|ha |yes|upay|हाँ').hasMatch('${said.toLowerCase()} ')) {
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

    // The first answer: the window, the reason, and the hour asked for. The ⏰ and "Pata nahi"
    // buttons are the view's, raised by the ask; the server sends no options beside them.
    if (last == null) {
      return astro(
        askFor: AskFor.birthTime,
        bubbles: const [
          'Aapki Vrishabha rashi ke hisaab se 2027 ke beech se 2028 ke end tak shaadi ka sabse '
              'accha samay hai.',
          'Us samay Shukra ki dasha chalegi, jo rishton ke liye shubh hai — aapki kundali is '
              'maamle mein acchi hai.',
          'Aap kis samay paida hue the? Jaise subah 7:30 ya raat 10 baje — isse mahina bhi bata '
              'paunga.',
        ],
      );
    }

    // They gave the hour (or said they do not know it): a sharper window, then the place.
    if (last.askFor == AskFor.birthTime) {
      final hour = RegExp(r'\d{1,2}(:\d{2})?\s*(am|pm)?', caseSensitive: false)
          .firstMatch(said)
          ?.group(0)
          ?.trim();
      if (hour != null) _facts.add(AstroFact(key: 'birth_time', value: hour));
      return astro(
        askFor: AskFor.birthPlace,
        bubbles: [
          hour == null
              ? 'Koi baat nahi — bina samay ke bhi saaf dikhta hai: 2027 ka doosra hissa sabse '
                  'shubh hai.'
              : 'Shukriya! $hour se dekha — March se August 2027 sabse mazboot mahine hain.',
          'Aapke saatve ghar par Guru ki nazar hai, jo accha rishta laati hai.',
          'Aapka janm kis shehar mein hua tha? Isse lagna pakka ho jayega.',
        ],
      );
    }

    // They gave the place — picked, or typed. The third answer: enough is known for the upay.
    if (last.askFor == AskFor.birthPlace) {
      final where = (place?.description ?? said).split(',').first.trim();
      _facts.add(AstroFact(key: 'birth_place', value: place?.description ?? said));
      return astro(
        bubbles: [
          '$where ke hisaab se dekha — April se June 2027 mein rishta pakka hone ke sabse acche '
              'yog hain.',
          'Us samay Guru aapke saatve ghar se guzrega, aur wahan Shukra pehle se mazboot hai.',
          'Agle 4 hafte har Shukravar Maa Katyayani ka mantra 11 baar padhiye. Kal wapas aaiye, '
              'upay ka asar dekhte hain 🙏',
          'Ek baat bataiye — rishta ghar wale dhoond rahe hain ya aap khud?',
        ],
        options: const [
          'Ghar wale dhoond rahe hain',
          'Main khud dhoond raha hoon',
          'Jeevansathi kaisa hoga?',
        ],
      );
    }

    // Everything after: answer, reason, question. The upay has been given, and is not repeated.
    return astro(
      bubbles: const [
        'Aapka jeevansathi samajhdar aur shaant swabhav ka hoga.',
        'Saatve ghar ka swami Budh hai, jo baat-cheet se judne wala rishta deta hai.',
        'Aapko kaisa jeevansathi chahiye — naukri wala ya apna kaam karne wala?',
      ],
      options: const ['Love ya arrange?', 'Ghar wale maanenge?', 'Naukri kab lagegi?'],
    );
  }
}
