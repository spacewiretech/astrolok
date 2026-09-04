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
  birthPlace;

  String get wire => switch (this) {
        AskFor.none => 'none',
        AskFor.birthTime => 'birth_time',
        AskFor.birthPlace => 'birth_place',
      };

  static AskFor parse(Object? raw) => switch (raw) {
        'birth_time' => AskFor.birthTime,
        'birth_place' => AskFor.birthPlace,
        _ => AskFor.none,
      };
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
    this.titleEmoji = '',
    this.title = '',
    this.sections = const [],
    this.options = const [],
    this.askFor = AskFor.none,
  });

  final String id;
  final ChatRole role;
  final DateTime createdAt;

  /// A user turn's words, or an Astro turn's opening paragraph.
  ///
  /// One field for both because it is the same thing to every reader: the body of the message.
  /// An Astro turn decorates it with a title and sections; a user turn does not.
  final String text;

  final String titleEmoji;
  final String title;
  final List<AstroSection> sections;

  /// Quick replies offered under this turn. Only ever non-empty on the newest Astro turn — the
  /// view drops them from older ones, since answering a question from six turns ago would land
  /// somewhere confusing.
  final List<String> options;

  final AskFor askFor;

  bool get isUser => role == ChatRole.user;

  /// Null when the payload is not a turn at all, or carries nothing to show.
  static AstroMessage? fromServer(Object? raw) {
    if (raw is! Map) return null;

    final role = ChatRole.parse(raw['role']);

    // A user turn keeps its words under `text`; an Astro turn under `opening`, matching the
    // schema the model answers against.
    final text = role == ChatRole.user
        ? _text(raw['text'])
        : _text(raw['opening']);

    if (text.isEmpty) return null;

    return AstroMessage(
      // A locally-composed turn has no server id yet, so it falls back to something stable
      // enough to key a list item on.
      id: _text(raw['id']).isEmpty
          ? 'local-${_text(raw['created_at'])}'
          : _text(raw['id']),
      role: role,
      createdAt: DateTime.tryParse(_text(raw['created_at']))?.toLocal() ?? DateTime.now(),
      text: text,
      titleEmoji: _text(raw['title_emoji']),
      title: _text(raw['title']),
      sections: [
        for (final entry in (raw['sections'] is List ? raw['sections'] as List : const []))
          ?AstroSection.fromServer(entry),
      ],
      options: _stringList(raw['options']),
      askFor: AskFor.parse(raw['ask_for']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.wire,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (isUser) 'text': text else 'opening': text,
        'title_emoji': titleEmoji,
        'title': title,
        'sections': [for (final section in sections) section.toJson()],
        'options': options,
        'ask_for': askFor.wire,
      };

  /// What the listen button reads out.
  ///
  /// The title is included but the emoji is not: a device voice reads "sparkles" aloud, which is
  /// not what anyone wants to hear in the middle of a reading.
  String get spoken => [
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

/// A whole conversation, as cached on the device.
@immutable
class ChatThread {
  const ChatThread({
    required this.messages,
    this.remaining,
    this.updatedAt,
  });

  /// Oldest first, as a transcript reads.
  final List<AstroMessage> messages;

  /// Questions left today, or null when it has never been reported.
  final int? remaining;

  final DateTime? updatedAt;

  /// The one thread this app keeps.
  ///
  /// The design shows a single continuous conversation with Astro rather than a list of them, so
  /// there is one id and the cache holds one row. `ReadingStore` keys on an id and keeps ten, so
  /// this fits it unchanged — with nine slots spare should threads ever arrive.
  static const soleId = 'astro';

  bool get isEmpty => messages.isEmpty;

  ChatThread copyWith({List<AstroMessage>? messages, int? remaining}) => ChatThread(
        messages: messages ?? this.messages,
        remaining: remaining ?? this.remaining,
        updatedAt: DateTime.now(),
      );

  static ChatThread? fromServer(Object? raw) {
    if (raw is! Map) return null;

    return ChatThread(
      messages: [
        for (final entry in (raw['messages'] is List ? raw['messages'] as List : const []))
          ?AstroMessage.fromServer(entry),
      ],
      remaining: raw['remaining'] is int ? raw['remaining'] as int : null,
      updatedAt: DateTime.tryParse(_text(raw['updated_at']))?.toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': soleId,
        'messages': [for (final message in messages) message.toJson()],
        'remaining': remaining,
        'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      };
}

String _text(Object? raw) => raw?.toString().trim() ?? '';

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .map((entry) => (entry as Object?)?.toString().trim() ?? '')
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}
