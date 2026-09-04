import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'reading_status.dart';

export 'reading_status.dart';

/// One reading of a palm, as the Edge Function returns it.
///
/// Everything here parses defensively. The content is written by a language model against a
/// schema, and while the server normalises it before storing it, this build may also be
/// reading a row written by a newer server that knows about a line this one does not. The rule
/// throughout: degrade to less, never throw.

/// The eight lines, in the order the results screen lists them.
///
/// Declaration order *is* display order — the four best-known lines first, then the deeper
/// ones — so `PalmLineKind.values` can be used directly for sorting.
enum PalmLineKind {
  heart,
  life,
  head,
  fate,
  sun,
  mercury,
  marriage,
  mars;

  /// The wire value, matching the `key` enum in the function's response schema.
  String get wire => name;

  String get label => switch (this) {
        PalmLineKind.heart => 'Heart Line',
        PalmLineKind.life => 'Life Line',
        PalmLineKind.head => 'Head Line',
        PalmLineKind.fate => 'Fate Line',
        PalmLineKind.sun => 'Sun Line',
        // Never "Health Line". The Mercury line is read as communication and everyday
        // vitality; the health framing invites medical claims the reading must not make, and
        // the server prompt forbids them for the same reason.
        PalmLineKind.mercury => 'Mercury Line',
        PalmLineKind.marriage => 'Relationship Line',
        PalmLineKind.mars => 'Mars Line',
      };

  /// The one-line gloss under the title on the results list, before the reading's own summary.
  String get subtitle => switch (this) {
        PalmLineKind.heart => 'Your emotional world and relationships',
        PalmLineKind.life => 'Vitality, resilience and stamina',
        PalmLineKind.head => 'How you think and decide',
        PalmLineKind.fate => 'Direction, work and purpose',
        PalmLineKind.sun => 'Recognition, joy and creativity',
        PalmLineKind.mercury => 'Communication and everyday energy',
        PalmLineKind.marriage => 'Closeness and lasting bonds',
        PalmLineKind.mars => 'Courage and inner resilience',
      };

  /// The tint behind the row's icon, and the accent on its detail screen.
  ///
  /// Drawn from the four categories the theme already reserves for the reading screens. Head
  /// is the one the palette has no entry for, so it is defined beside them in [AppColors].
  Color get accent => switch (this) {
        PalmLineKind.heart => AppColors.love,
        PalmLineKind.life => AppColors.money,
        PalmLineKind.head => AppColors.insight,
        PalmLineKind.fate => AppColors.career,
        PalmLineKind.sun => AppColors.gold,
        PalmLineKind.mercury => AppColors.insight,
        PalmLineKind.marriage => AppColors.love,
        PalmLineKind.mars => AppColors.career,
      };

  IconData get icon => switch (this) {
        PalmLineKind.heart => Icons.favorite_outline_rounded,
        PalmLineKind.life => Icons.eco_outlined,
        PalmLineKind.head => Icons.psychology_outlined,
        PalmLineKind.fate => Icons.star_outline_rounded,
        PalmLineKind.sun => Icons.wb_sunny_outlined,
        PalmLineKind.mercury => Icons.forum_outlined,
        PalmLineKind.marriage => Icons.favorite_border_rounded,
        PalmLineKind.mars => Icons.shield_outlined,
      };

  /// Null for anything unrecognised.
  ///
  /// Deliberately not defaulted: a row rendered as "Heart Line" because the server sent a line
  /// this build has never heard of would be a reading about the wrong thing. The caller drops
  /// it instead, and the user sees seven rows rather than a wrong one.
  static PalmLineKind? parse(Object? raw) {
    for (final kind in PalmLineKind.values) {
      if (kind.wire == raw) return kind;
    }
    return null;
  }
}

/// The coloured chip beside a line's title.
///
/// Lifted into [ReadingStatus] when face reading arrived — the server sends the same six words
/// for a face feature — and left here as an alias so every existing call site reads unchanged.
typedef PalmLineStatus = ReadingStatus;

/// What the user asked the reading to concentrate on.
///
/// No health option, deliberately, and the server rejects one: offering it would steer the
/// model toward exactly the claims the prompt forbids.
enum PalmFocus {
  love('love', 'Love & Relationships', Icons.favorite_rounded),
  career('career', 'Career & Purpose', Icons.work_outline_rounded),
  money('money', 'Money & Abundance', Icons.savings_outlined),
  personality('personality', 'Personality & Strengths', Icons.auto_awesome_rounded),
  lifePath('life_path', 'Life Path', Icons.explore_outlined);

  const PalmFocus(this.wire, this.label, this.icon);

  /// The value the Edge Function expects. Not [name] — `lifePath` travels as `life_path`.
  final String wire;
  final String label;
  final IconData icon;

  Color get color => switch (this) {
        PalmFocus.love => AppColors.love,
        PalmFocus.career => AppColors.career,
        PalmFocus.money => AppColors.money,
        PalmFocus.personality => AppColors.personality,
        PalmFocus.lifePath => AppColors.insight,
      };

  static PalmFocus parse(Object? raw) {
    for (final focus in PalmFocus.values) {
      if (focus.wire == raw) return focus;
    }
    return PalmFocus.lifePath;
  }
}

/// What the model could see of the hand itself.
///
/// This is the personalisation hook: the reading is written to cite these, so they are carried
/// through to the app for the "what your hand shows" strip on the results screen.
@immutable
class HandTraits {
  const HandTraits({
    this.whichHand,
    this.skinTexture,
    this.firmness,
    this.palmShape,
    this.fingerLength,
    this.visibleMarks,
    this.observations = const [],
  });

  final String? whichHand;
  final String? skinTexture;
  final String? firmness;
  final String? palmShape;
  final String? fingerLength;
  final String? visibleMarks;

  /// Two to four plain sentences about what is visible.
  final List<String> observations;

  /// "unclear" is a real answer from the model, not a value worth showing to anyone.
  static String? _trait(Object? raw) {
    final value = (raw as String?)?.trim();
    if (value == null || value.isEmpty || value == 'unclear') return null;
    return value;
  }

  static HandTraits fromServer(Object? raw) {
    if (raw is! Map) return const HandTraits();

    return HandTraits(
      whichHand: _trait(raw['which_hand']),
      skinTexture: _trait(raw['skin_texture']),
      firmness: _trait(raw['firmness']),
      palmShape: _trait(raw['palm_shape']),
      fingerLength: _trait(raw['finger_length']),
      visibleMarks: _trait(raw['visible_marks']),
      observations: _stringList(raw['observations']),
    );
  }

  Map<String, dynamic> toJson() => {
        'which_hand': whichHand,
        'skin_texture': skinTexture,
        'firmness': firmness,
        'palm_shape': palmShape,
        'finger_length': fingerLength,
        'visible_marks': visibleMarks,
        'observations': observations,
      };

  /// Short chips for the results screen — "Soft hands", "Smooth skin", "Broad palm".
  List<String> get chips => [
        if (firmness != null) '${_capitalise(firmness!)} hands',
        if (skinTexture != null) '${_capitalise(skinTexture!)} skin',
        if (palmShape != null) '${_capitalise(palmShape!)} palm',
        if (fingerLength != null) '${_capitalise(fingerLength!)} fingers',
      ];

  bool get isEmpty => chips.isEmpty && observations.isEmpty;
}

String _capitalise(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .map((entry) => (entry as Object?)?.toString().trim() ?? '')
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

/// The headline trait, shown in the hero card.
@immutable
class PalmTrait {
  const PalmTrait({this.title = '', this.summary = '', this.detail = ''});

  final String title;
  final String summary;
  final String detail;

  static PalmTrait fromServer(Object? raw) {
    if (raw is! Map) return const PalmTrait();
    return PalmTrait(
      title: _text(raw['title']),
      summary: _text(raw['summary']),
      detail: _text(raw['detail']),
    );
  }

  Map<String, dynamic> toJson() =>
      {'title': title, 'summary': summary, 'detail': detail};

  bool get isEmpty => title.isEmpty && summary.isEmpty && detail.isEmpty;
}

String _text(Object? raw) => raw?.toString().trim() ?? '';

/// One line of the reading.
@immutable
class PalmLine {
  const PalmLine({
    required this.kind,
    required this.title,
    required this.status,
    required this.summary,
    required this.detail,
    this.sanskrit = '',
    this.meaning = const [],
    this.tip = '',
    this.blessing = '',
  });

  final PalmLineKind kind;
  final String title;

  /// The tradition's name for this line, transliterated — "Hridaya Rekha". Shown once beside
  /// the title and never again in the section, which is what keeps the register light enough to
  /// read. Empty on a reading written before the pandit voice landed, so every use site checks.
  final String sanskrit;

  final PalmLineStatus status;

  /// The one-liner on the results row.
  final String summary;

  /// The paragraph on the detail screen.
  final String detail;

  /// "What it means for you" — three bullets, usually.
  final List<String> meaning;

  final String tip;

  /// The line's closing ashirvad. A wish, never a promise — the prompt is explicit about the
  /// difference, and the detail screen renders it as the last thing on the page.
  final String blessing;

  /// Null when the entry names a line this build does not know, or carries no reading at all.
  static PalmLine? fromServer(Object? raw) {
    if (raw is! Map) return null;

    final kind = PalmLineKind.parse(raw['key']);
    if (kind == null) return null;

    final detail = _text(raw['detail']);
    if (detail.isEmpty) return null;

    final title = _text(raw['title']);

    return PalmLine(
      kind: kind,
      title: title.isEmpty ? kind.label : title,
      sanskrit: _text(raw['sanskrit']),
      status: PalmLineStatus.parse(raw['status']),
      summary: _text(raw['summary']),
      detail: detail,
      meaning: _stringList(raw['meaning']),
      tip: _text(raw['tip']),
      blessing: _text(raw['blessing']),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': kind.wire,
        'title': title,
        'sanskrit': sanskrit,
        'status': status.label,
        'summary': summary,
        'detail': detail,
        'meaning': meaning,
        'tip': tip,
        'blessing': blessing,
      };

  /// What the speak button reads out on the detail screen.
  ///
  /// The Sanskrit term is deliberately left out. It is a visual flourish beside the title; read
  /// aloud by a device voice that has never seen the word, it comes out as noise.
  String get spoken => [
        title,
        detail,
        ...meaning,
        if (tip.isNotEmpty) 'A tip. $tip',
        if (blessing.isNotEmpty) blessing,
      ].join('\n\n');
}

/// A whole reading.
@immutable
class PalmReading {
  const PalmReading({
    required this.id,
    required this.createdAt,
    required this.focus,
    required this.lines,
    this.invocation = '',
    this.headline = '',
    this.blessing = '',
    this.strongestTrait = const PalmTrait(),
    this.hand = const HandTraits(),
    this.imageFileName,
  });

  final String id;
  final DateTime createdAt;
  final PalmFocus focus;
  final List<PalmLine> lines;

  /// The reading's opening line, written after the model has looked at the hand so that it is
  /// about this hand. Empty on readings cached before the pandit voice landed.
  final String invocation;

  final String headline;

  /// The closing ashirvad. Read aloud last, and printed last in the export.
  final String blessing;

  final PalmTrait strongestTrait;
  final HandTraits hand;

  /// The captured photograph's file *name* under the app's palm directory — never an absolute
  /// path. iOS rewrites the application container path on reinstall and on restore from
  /// backup, so a stored absolute path is a broken image on every restored device.
  ///
  /// Null once the photo is gone: the reading text outlives it, and the screens fall back.
  final String? imageFileName;

  /// Null when the payload is not a reading at all. A reading that parses to zero lines is
  /// also null — there would be nothing to show.
  static PalmReading? fromServer(Object? raw) {
    if (raw is! Map) return null;

    final id = _text(raw['id']);
    if (id.isEmpty) return null;

    final lines = <PalmLine>[];
    final seen = <PalmLineKind>{};
    for (final entry in (raw['lines'] is List ? raw['lines'] as List : const [])) {
      final line = PalmLine.fromServer(entry);
      if (line == null || !seen.add(line.kind)) continue;
      lines.add(line);
    }

    if (lines.isEmpty) return null;

    // Declaration order is display order, so this restores the intended order even if a
    // future server sends them in another one.
    lines.sort((a, b) => a.kind.index.compareTo(b.kind.index));

    return PalmReading(
      id: id,
      createdAt: DateTime.tryParse(_text(raw['created_at']))?.toLocal() ?? DateTime.now(),
      focus: PalmFocus.parse(raw['focus']),
      lines: lines,
      invocation: _text(raw['invocation']),
      headline: _text(raw['headline']),
      blessing: _text(raw['blessing']),
      strongestTrait: PalmTrait.fromServer(raw['strongest_trait']),
      hand: HandTraits.fromServer(raw['hand']),
      imageFileName: _text(raw['image_file_name']).isEmpty
          ? null
          : _text(raw['image_file_name']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'focus': focus.wire,
        'invocation': invocation,
        'headline': headline,
        'blessing': blessing,
        'strongest_trait': strongestTrait.toJson(),
        'hand': hand.toJson(),
        'lines': [for (final line in lines) line.toJson()],
        'image_file_name': imageFileName,
      };

  PalmReading copyWith({String? imageFileName}) => PalmReading(
        id: id,
        createdAt: createdAt,
        focus: focus,
        lines: lines,
        invocation: invocation,
        headline: headline,
        blessing: blessing,
        strongestTrait: strongestTrait,
        hand: hand,
        imageFileName: imageFileName ?? this.imageFileName,
      );

  PalmLine? line(PalmLineKind kind) {
    for (final line in lines) {
      if (line.kind == kind) return line;
    }
    return null;
  }

  /// What the speak button reads out on the results screen: the overview, not every paragraph.
  ///
  /// Opens on the invocation and closes on the blessing, so the spoken reading is framed the way
  /// the written one is — it is the version most people will actually take in.
  String get spoken => [
        if (invocation.isNotEmpty) invocation,
        if (headline.isNotEmpty) headline,
        if (!strongestTrait.isEmpty) ...[
          'Your strongest trait. ${strongestTrait.title}.',
          strongestTrait.summary,
          strongestTrait.detail,
        ],
        'Here is what your palm lines show.',
        for (final line in lines) '${line.title}. ${line.summary}',
        if (blessing.isNotEmpty) blessing,
      ].where((part) => part.trim().isNotEmpty).join('\n\n');
}
