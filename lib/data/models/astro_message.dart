import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// One turn of a conversation with Astro, as the Edge Function returns it.
///
/// Everything here parses defensively, for the same reason the reading models do: the content is
/// written by a language model against a schema, and while the server normalises it before
/// storing it, this build may also be reading a row written by a newer server. The rule
/// throughout: degrade to less, never throw.

/// Which side of the conversation a turn came from.
enum ChatRole {
  user,
  astro;

  String get wire => name;

  /// Defaults to [astro] rather than returning null.
  ///
  /// The two are told apart visually — navy right, white left — so a turn with an unreadable
  /// role is worth showing on one side or the other. Astro's side is the safer guess: an
  /// unexpected message from the sage reads as odd, whereas one attributed to the user reads as
  /// the app putting words in their mouth.
  static ChatRole parse(Object? raw) =>
      raw == 'user' ? ChatRole.user : ChatRole.astro;
}

/// What the sage still needs, so the app can raise the right control instead of hoping the user
/// types something parseable.
enum AskFor {
  none,
  birthTime,
  birthPlace,

  /// The date of birth, asked for in the chat only after they said the one on file is wrong.
  dob;

  String get wire => switch (this) {
        AskFor.none => 'none',
        AskFor.birthTime => 'birth_time',
        AskFor.birthPlace => 'birth_place',
        AskFor.dob => 'dob',
      };

  static AskFor parse(Object? raw) => switch (raw) {
        'birth_time' => AskFor.birthTime,
        'birth_place' => AskFor.birthPlace,
        'dob' => AskFor.dob,
        _ => AskFor.none,
      };
}

/// What sort of turn an Astro reply is, in the WhatsApp-style chat (v5).
enum ReplyKind {
  /// A reading, from a v4 prompt or earlier — one card's worth of text.
  reading,

  /// An answer to a question: the answer, the reason, and usually the offer of today's upay.
  answer,

  /// The upay, served when they accepted the offer.
  remedy,

  /// Astro asking for a detail it lacks — a date or an hour of birth.
  ask,

  /// A short reply to small talk or to something Astro asked.
  chat,

  /// The fixed reply to someone in distress, with helpline numbers. Never rated under.
  care;

  static ReplyKind parse(Object? raw) => switch (raw) {
        'answer' => ReplyKind.answer,
        'remedy' => ReplyKind.remedy,
        'ask' => ReplyKind.ask,
        'chat' => ReplyKind.chat,
        'care' => ReplyKind.care,
        _ => ReplyKind.reading,
      };

  /// Null for [reading], which the server never names.
  String? get wire => this == ReplyKind.reading ? null : name;
}

/// One of the labelled blocks under a reply's opening paragraph.
@immutable
class AstroSection {
  const AstroSection({
    required this.heading,
    required this.body,
    this.emoji = '',
  });

  /// May be empty — the design shows one, but a reply without it still reads.
  final String emoji;

  final String heading;
  final String body;

  static AstroSection? fromServer(Object? raw) {
    if (raw is! Map) return null;

    final heading = _text(raw['heading']);
    final body = _text(raw['body']);
    if (heading.isEmpty || body.isEmpty) return null;

    return AstroSection(
      emoji: _text(raw['emoji']),
      heading: heading,
      body: body,
    );
  }

  Map<String, dynamic> toJson() => {'emoji': emoji, 'heading': heading, 'body': body};
}

/// The four pills on the opening screen.
///
/// Their own type rather than [PalmFocus]: the readings offer five focuses tied to a scan, and
/// these are four conversation openers. Sharing them would mean every future change to one
/// list silently changing the other screen.
enum ChatTopic {
  love('Love & Relationships', Icons.favorite_border_rounded, AppColors.love),
  career('Career & Growth', Icons.work_outline_rounded, AppColors.career),
  future('Future Predictions', Icons.auto_awesome_outlined, AppColors.gold),
  guidance('Personal Guidance', Icons.spa_outlined, AppColors.money);

  const ChatTopic(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  /// What tapping the pill actually sends.
  ///
  /// The user's own words, in the first person, rather than a keyword — it becomes a real turn
  /// in the transcript, and "love" sitting in a navy bubble would read as a machine talking.
  String get opener => switch (this) {
        ChatTopic.love => 'I want to know about my love life.',
        ChatTopic.career => 'I want to know about my career.',
        ChatTopic.future => 'What does the season ahead hold for me?',
        ChatTopic.guidance => 'I could use some guidance.',
      };
}

/// A turn.
@immutable
class AstroMessage {
  const AstroMessage({
    required this.id,
    required this.role,
    required this.createdAt,
    this.text = '',
    this.verdict = '',
    this.titleEmoji = '',
    this.title = '',
    this.sections = const [],
    this.options = const [],
    this.askFor = AskFor.none,
    this.bubbles = const [],
    this.kind = ReplyKind.reading,
    this.offersRemedy = false,
    this.topic = '',
  });

  final String id;
  final ChatRole role;
  final DateTime createdAt;

  /// A user turn's words, or an Astro turn's opening paragraph.
  ///
  /// One field for both because it is the same thing to every reader: the body of the message.
  /// An Astro turn decorates it with a title and sections; a user turn does not.
  final String text;

  /// The answer itself, before the reasoning that follows it in [text].
  ///
  /// Empty on a user turn, and empty on any Astro turn stored before the field existed — the
  /// screen simply omits the block, and such a reply renders exactly as replies used to.
  final String verdict;

  final String titleEmoji;
  final String title;
  final List<AstroSection> sections;

  /// Quick replies offered under this turn. Only ever non-empty on the newest Astro turn — the
  /// view drops them from older ones, since answering a question from six turns ago would land
  /// somewhere confusing.
  final List<String> options;

  final AskFor askFor;

  /// A v5 reply's messages, in the order Astro sent them. Empty for a user turn and for every
  /// reply written before v5 — see [displayBubbles], which is what the screen shows either way.
  final List<String> bubbles;

  final ReplyKind kind;

  /// True when this reply ends by offering today's upay, and its first option is the yes.
  final bool offersRemedy;

  /// What the question was about — marriage, love, career… — as the server classified it.
  final String topic;

  bool get isUser => role == ChatRole.user;

  /// The messages this turn is shown as, one chat bubble each.
  ///
  /// A v5 reply is its [bubbles]. A reply from before v5 is broken into the same shape — the
  /// answer, then the title and the opening, then each section — so a conversation that began as
  /// cards reads as a chat when it is opened on the new screen. A user turn is its words.
  List<String> get displayBubbles {
    if (isUser) return [text];
    if (bubbles.isNotEmpty) return bubbles;
    return [
      if (verdict.isNotEmpty) verdict,
      [if (title.isNotEmpty) '$titleEmoji $title'.trim(), text]
          .where((part) => part.isNotEmpty)
          .join('\n'),
      for (final section in sections) '${section.emoji} ${section.heading}\n${section.body}'.trim(),
    ].where((bubble) => bubble.trim().isNotEmpty).toList(growable: false);
  }

  /// Null when the payload is not a turn at all, or carries nothing to show.
  static AstroMessage? fromServer(Object? raw) {
    if (raw is! Map) return null;

    final role = ChatRole.parse(raw['role']);

    // A user turn keeps its words under `text`; an Astro turn under `opening`, matching the
    // schema the model answers against.
    final text = role == ChatRole.user
        ? _text(raw['text'])
        : _text(raw['opening']);

    // A v5 reply carries its messages as `bubbles`, with `opening` filled beside them for older
    // builds. Either is enough to show; neither is nothing to show.
    final bubbles = role == ChatRole.user ? const <String>[] : _stringList(raw['bubbles']);

    if (text.isEmpty && bubbles.isEmpty) return null;

    return AstroMessage(
      // A locally-composed turn has no server id yet, so it falls back to something stable
      // enough to key a list item on.
      id: _text(raw['id']).isEmpty
          ? 'local-${_text(raw['created_at'])}'
          : _text(raw['id']),
      role: role,
      createdAt: DateTime.tryParse(_text(raw['created_at']))?.toLocal() ?? DateTime.now(),
      text: text,
      verdict: _text(raw['verdict']),
      titleEmoji: _text(raw['title_emoji']),
      title: _text(raw['title']),
      sections: [
        for (final entry in (raw['sections'] is List ? raw['sections'] as List : const []))
          ?AstroSection.fromServer(entry),
      ],
      options: _stringList(raw['options']),
      askFor: AskFor.parse(raw['ask_for']),
      bubbles: bubbles,
      kind: ReplyKind.parse(raw['kind']),
      offersRemedy: raw['offer'] == 'remedy',
      topic: _text(raw['topic']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.wire,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (isUser) 'text': text else 'opening': text,
        'verdict': verdict,
        'title_emoji': titleEmoji,
        'title': title,
        'sections': [for (final section in sections) section.toJson()],
        'options': options,
        'ask_for': askFor.wire,
        if (bubbles.isNotEmpty) 'bubbles': bubbles,
        if (kind.wire != null) 'kind': kind.wire,
        if (offersRemedy) 'offer': 'remedy',
        if (topic.isNotEmpty) 'topic': topic,
      };

  /// What the listen button reads out.
  ///
  /// The title is included but the emoji is not: a device voice reads "sparkles" aloud, which is
  /// not what anyone wants to hear in the middle of a reading.
  ///
  /// The verdict comes first, ahead of even the title — spoken aloud, an answer that arrives
  /// after its own justification is worse than on the page, because a listener cannot skip ahead
  /// to find it.
  String get spoken => bubbles.isNotEmpty
      // Emoji out, for the same reason as the title's below.
      ? bubbles.map((b) => b.replaceAll(_emoji, '').trim()).join('\n\n')
      : [
          if (verdict.isNotEmpty) verdict,
          if (title.isNotEmpty) title,
          text,
          for (final section in sections) '${section.heading}. ${section.body}',
        ].where((part) => part.trim().isNotEmpty).join('\n\n');
}

/// One thing Astro has learned, as Profile shows it.
@immutable
class AstroFact {
  const AstroFact({required this.key, required this.value, this.updatedAt});

  /// The snake_case slug the server keys on. Shown to the user as a readable [label].
  final String key;

  final String value;
  final DateTime? updatedAt;

  /// "works_as" becomes "Works as". Not a lookup table: the keys are invented by the model, so
  /// there is no fixed set to translate, and de-slugging is the only thing that generalises.
  String get label {
    final words = key.split('_').where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return key;
    return [words.first[0].toUpperCase() + words.first.substring(1), ...words.skip(1)]
        .join(' ');
  }

  static AstroFact? fromServer(Object? raw) {
    if (raw is! Map) return null;

    final key = _text(raw['key']);
    final value = _text(raw['value']);
    if (key.isEmpty || value.isEmpty) return null;

    return AstroFact(
      key: key,
      value: value,
      updatedAt: DateTime.tryParse(_text(raw['updated_at']))?.toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'updated_at': updatedAt?.toUtc().toIso8601String(),
      };
}

/// One conversation in the sidebar: enough to list it, not enough to read it.
///
/// Separate from [ChatThread] on purpose. The drawer lists every conversation an account has and
/// must open instantly; sending each one's transcript to render a two-line row would make the
/// payload grow with how much the user has talked, which is precisely backwards.
@immutable
class ChatThreadSummary {
  const ChatThreadSummary({
    required this.id,
    required this.title,
    this.preview = '',
    this.lastMessageAt,
  });

  final String id;

  /// Written by the server from the first reply's own subject line. May be empty for a
  /// conversation whose first reply never landed; the drawer shows a placeholder.
  final String title;

  /// The newest answer, in one line.
  final String preview;

  final DateTime? lastMessageAt;

  static ChatThreadSummary? fromServer(Object? raw) {
    if (raw is! Map) return null;

    final id = _text(raw['id']);
    if (id.isEmpty) return null;

    return ChatThreadSummary(
      id: id,
      title: _text(raw['title']),
      preview: _text(raw['preview']),
      lastMessageAt: DateTime.tryParse(_text(raw['last_message_at']))?.toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'preview': preview,
        'last_message_at': lastMessageAt?.toUtc().toIso8601String(),
      };
}

/// Where a conversation sits in the sidebar.
enum ChatAge { today, yesterday, week, older }

/// Buckets conversations by when they were last spoken to, newest bucket first.
///
/// Top-level and pure — takes [now] rather than reading the clock — so the midnight and seven-day
/// boundaries can be tested without waiting for either.
///
/// Compared by calendar day rather than by elapsed hours: something said at 11pm belongs under
/// "Yesterday" at 1am, not under "Today" because twenty-three hours have not passed.
Map<ChatAge, List<ChatThreadSummary>> groupThreads(
  List<ChatThreadSummary> threads, {
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final grouped = <ChatAge, List<ChatThreadSummary>>{};

  for (final thread in threads) {
    final at = thread.lastMessageAt;
    // Undated goes last rather than first: it is almost always a locally-cached thread that has
    // never reached the server, and pinning one to the top of the list would be a lie about it.
    final days = at == null
        ? 1 << 20
        : today.difference(DateTime(at.year, at.month, at.day)).inDays;

    final age = switch (days) {
      // Negative covers a device clock behind the server's — the row is "today", not "the future".
      <= 0 => ChatAge.today,
      1 => ChatAge.yesterday,
      < 7 => ChatAge.week,
      _ => ChatAge.older,
    };

    (grouped[age] ??= []).add(thread);
  }

  // Rebuilt in enum order so the drawer never has to sort, and an empty bucket is simply absent.
  return {
    for (final age in ChatAge.values) age: ?grouped[age],
  };
}

/// A whole conversation, as cached on the device.
@immutable
class ChatThread {
  const ChatThread({
    required this.id,
    required this.messages,
    this.title = '',
    this.remaining,
    this.updatedAt,
  });

  /// The server's thread id, or [draftId] for one that has not been sent yet.
  final String id;

  final String title;

  /// Oldest first, as a transcript reads.
  final List<AstroMessage> messages;

  /// Questions left today, or null when it has never been reported.
  final int? remaining;

  final DateTime? updatedAt;

  /// A conversation that exists only on this device, because nothing has been sent yet.
  ///
  /// The screen needs a stable key from the moment it opens — before the server has said what
  /// this thread is called — and the ViewModel keeps it for the life of the visit even after the
  /// real id arrives, so the first reply does not tear the screen down and rebuild it.
  ///
  /// Never a valid server id: those are uuids.
  static const draftId = 'draft';

  bool get isDraft => id == draftId;

  bool get isEmpty => messages.isEmpty;

  ChatThread copyWith({List<AstroMessage>? messages, int? remaining}) => ChatThread(
        id: id,
        title: title,
        messages: messages ?? this.messages,
        remaining: remaining ?? this.remaining,
        updatedAt: DateTime.now(),
      );

  static ChatThread? fromServer(Object? raw) {
    if (raw is! Map) return null;

    final id = _text(raw['id']);
    // A cached thread with no id cannot be keyed, found again, or sent to. Dropped rather than
    // half-built, like everything else here.
    if (id.isEmpty) return null;

    return ChatThread(
      id: id,
      title: _text(raw['title']),
      messages: [
        for (final entry in (raw['messages'] is List ? raw['messages'] as List : const []))
          ?AstroMessage.fromServer(entry),
      ],
      remaining: raw['remaining'] is int ? raw['remaining'] as int : null,
      updatedAt: DateTime.tryParse(_text(raw['updated_at']))?.toLocal(),
    );
  }

  /// How this conversation looks in the sidebar, without a round trip.
  ///
  /// What lets the drawer paint from the cache on a cold start, before `chat-history` answers.
  ChatThreadSummary get summary => ChatThreadSummary(
        id: id,
        title: title,
        preview: messages.isEmpty ? '' : _previewOf(messages.last),
        lastMessageAt: updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': [for (final message in messages) message.toJson()],
        'remaining': remaining,
        'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      };
}

/// The same line the server denormalises onto a thread: an answer if there is one, else words.
String _previewOf(AstroMessage message) {
  final line = message.bubbles.isNotEmpty
      ? message.bubbles.first
      : message.verdict.isNotEmpty
          ? message.verdict
          : message.text;
  final flat = line.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= 100 ? flat : flat.substring(0, 100);
}

String _text(Object? raw) => raw?.toString().trim() ?? '';

/// Emoji, as a device voice would otherwise read them aloud by name.
final _emoji = RegExp(
  r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]',
  unicode: true,
);

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .map((entry) => (entry as Object?)?.toString().trim() ?? '')
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}
