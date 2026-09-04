import 'package:flutter/material.dart';

import '../../app/assets.dart';
import '../../app/theme/app_colors.dart';
import 'palm_reading.dart' show PalmFocus;
import 'reading_status.dart';

export 'reading_status.dart';

/// One reading of a face, as the Edge Function returns it.
///
/// Everything here parses defensively, for the same reason [PalmReading] does: the content is
/// written by a language model against a schema, and while the server normalises it before
/// storing it, this build may also be reading a row written by a newer server that knows about a
/// feature this one does not. The rule throughout: degrade to less, never throw.
///
/// The focus enum is shared with the palm reading rather than duplicated — the two features
/// offer the same five choices, and a user who picks "Love & Relationships" for their palm
/// should find the same words on the face screen.

/// The six features, in the order the results screen lists them.
///
/// Declaration order *is* display order — the four the design ships artwork for first, then the
/// two that round the reading out — so `FacePartKind.values` can be used directly for sorting.
enum FacePartKind {
  eyes,
  faceShape,
  nose,
  lips,
  forehead,
  eyebrows;

  /// The wire value, matching the `key` enum in the function's response schema.
  /// Not [name] — `faceShape` travels as `face_shape`.
  String get wire => switch (this) {
        FacePartKind.faceShape => 'face_shape',
        _ => name,
      };

  String get label => switch (this) {
        FacePartKind.eyes => 'Eyes',
        FacePartKind.faceShape => 'Face Shape',
        FacePartKind.nose => 'Nose',
        FacePartKind.lips => 'Lips',
        FacePartKind.forehead => 'Forehead',
        FacePartKind.eyebrows => 'Eyebrows',
      };

  /// The heading on the detail screen — "Eye Reading", not "Eyes".
  String get readingTitle => switch (this) {
        FacePartKind.eyes => 'Eye Reading',
        FacePartKind.faceShape => 'Face Shape Reading',
        FacePartKind.nose => 'Nose Reading',
        FacePartKind.lips => 'Lip Reading',
        FacePartKind.forehead => 'Forehead Reading',
        FacePartKind.eyebrows => 'Eyebrow Reading',
      };

  /// The one-line gloss under the title on the results list, before the reading's own summary.
  String get subtitle => switch (this) {
        FacePartKind.eyes => 'Emotions & Intuition',
        FacePartKind.faceShape => 'Personality & Temperament',
        FacePartKind.nose => 'Drive & Ambition',
        FacePartKind.lips => 'Communication & Relationships',
        FacePartKind.forehead => 'Thought & Reflection',
        FacePartKind.eyebrows => 'Will & Focus',
      };

  /// What the detail screen says this reading reveals, under its title.
  String get promise => switch (this) {
        FacePartKind.eyes =>
          'This reading reveals your intuition, emotional awareness & how you perceive people.',
        FacePartKind.faceShape =>
          'This reading reveals your temperament and the overall cast of your nature.',
        FacePartKind.nose =>
          'This reading reveals your drive, your initiative & how you spend your energy.',
        FacePartKind.lips =>
          'This reading reveals how you express yourself & how you are in close company.',
        FacePartKind.forehead =>
          'This reading reveals how you think, remember & take the long view.',
        FacePartKind.eyebrows =>
          'This reading reveals your will, your focus & how you meet resistance.',
      };

  /// What the "Ask Astro" button asks about, lower-cased into the sentence.
  String get possessive => switch (this) {
        FacePartKind.eyes => 'eyes',
        FacePartKind.faceShape => 'face shape',
        FacePartKind.nose => 'nose',
        FacePartKind.lips => 'lips',
        FacePartKind.forehead => 'forehead',
        FacePartKind.eyebrows => 'eyebrows',
      };

  /// The tint behind the row's icon, and the accent on its detail screen.
  ///
  /// The first four follow the supplied artwork exactly — a purple eye, a gold face, a green
  /// nose, red lips — so the flat icon and the tint behind it never disagree. The last two have
  /// no artwork and take the two remaining accents the palette already reserves for readings.
  Color get accent => switch (this) {
        FacePartKind.eyes => AppColors.career,
        FacePartKind.faceShape => AppColors.gold,
        FacePartKind.nose => AppColors.money,
        FacePartKind.lips => AppColors.love,
        FacePartKind.forehead => AppColors.insight,
        FacePartKind.eyebrows => AppColors.goldDeep,
      };

  /// The exported glyph, or null where the design ships none and [icon] carries the row alone.
  String? get asset => switch (this) {
        FacePartKind.eyes => FaceIcon.eyes,
        FacePartKind.faceShape => FaceIcon.faceShape,
        FacePartKind.nose => FaceIcon.nose,
        FacePartKind.lips => FaceIcon.lips,
        FacePartKind.forehead => null,
        FacePartKind.eyebrows => null,
      };

  /// Drawn when [asset] is null, and as [SafeImage]'s fallback when a file is missing.
  IconData get icon => switch (this) {
        FacePartKind.eyes => Icons.remove_red_eye_outlined,
        FacePartKind.faceShape => Icons.sentiment_satisfied_outlined,
        FacePartKind.nose => Icons.air_rounded,
        FacePartKind.lips => Icons.favorite_border_rounded,
        FacePartKind.forehead => Icons.psychology_outlined,
        FacePartKind.eyebrows => Icons.architecture_outlined,
      };

  /// Null for anything unrecognised.
  ///
  /// Deliberately not defaulted: a row rendered as "Eyes" because the server sent a feature this
  /// build has never heard of would be a reading about the wrong thing. The caller drops it
  /// instead, and the user sees five rows rather than a wrong one.
  static FacePartKind? parse(Object? raw) {
    for (final kind in FacePartKind.values) {
      if (kind.wire == raw) return kind;
    }
    return null;
  }
}

/// The four chips under the core trait.
///
/// A closed vocabulary, matched to the server's `TRAIT_KEYS`, because each one renders as an
/// icon in a specific colour — a word with no glyph would draw an empty tile. Anything the
/// server sends that is not in this list is dropped rather than guessed at.
enum FaceTraitKind {
  independent('independent', 'Independent', Icons.person_outline_rounded, AppColors.career),
  observant('observant', 'Observant', Icons.remove_red_eye_outlined, AppColors.gold),
  warm('warm', 'Warm', Icons.favorite_border_rounded, AppColors.love),
  determined('determined', 'Determined', Icons.flag_outlined, AppColors.money),
  patient('patient', 'Patient', Icons.hourglass_empty_rounded, AppColors.insight),
  expressive('expressive', 'Expressive', Icons.forum_outlined, AppColors.love),
  grounded('grounded', 'Grounded', Icons.terrain_outlined, AppColors.money),
  curious('curious', 'Curious', Icons.travel_explore_outlined, AppColors.insight),
  loyal('loyal', 'Loyal', Icons.handshake_outlined, AppColors.career),
  generous('generous', 'Generous', Icons.volunteer_activism_outlined, AppColors.love),
  disciplined('disciplined', 'Disciplined', Icons.timeline_rounded, AppColors.goldDeep),
  intuitive('intuitive', 'Intuitive', Icons.auto_awesome_outlined, AppColors.career);

  const FaceTraitKind(this.wire, this.label, this.icon, this.color);

  final String wire;
  final String label;
  final IconData icon;
  final Color color;

  static FaceTraitKind? parse(Object? raw) {
    final wire = raw?.toString().trim().toLowerCase();
    for (final trait in FaceTraitKind.values) {
      if (trait.wire == wire) return trait;
    }
    return null;
  }
}

/// What the model could see of the face itself.
///
/// This is the personalisation hook: the reading is written to cite these, so they are carried
/// through to the app for the observations strip on the results screen.
///
/// Note what is absent, and must stay absent: complexion, skin tone, apparent age, apparent
/// gender. They are forbidden by the prompt, missing from the response schema, and there is no
/// field here that could hold them.
@immutable
class FaceObservations {
  const FaceObservations({
    this.faceShape,
    this.foreheadHeight,
    this.eyebrowThickness,
    this.eyeSet,
    this.noseBridge,
    this.lipFullness,
    this.expression,
    this.observations = const [],
  });

  final String? faceShape;
  final String? foreheadHeight;
  final String? eyebrowThickness;
  final String? eyeSet;
  final String? noseBridge;
  final String? lipFullness;
  final String? expression;

  /// Two to four plain sentences about what is visible.
  final List<String> observations;

  static FaceObservations fromServer(Object? raw) {
    if (raw is! Map) return const FaceObservations();

    return FaceObservations(
      faceShape: _trait(raw['face_shape']),
      foreheadHeight: _trait(raw['forehead_height']),
      eyebrowThickness: _trait(raw['eyebrow_thickness']),
      eyeSet: _trait(raw['eye_set']),
      noseBridge: _trait(raw['nose_bridge']),
      lipFullness: _trait(raw['lip_fullness']),
      expression: _trait(raw['expression']),
      observations: _stringList(raw['observations']),
    );
  }

  Map<String, dynamic> toJson() => {
        'face_shape': faceShape,
        'forehead_height': foreheadHeight,
        'eyebrow_thickness': eyebrowThickness,
        'eye_set': eyeSet,
        'nose_bridge': noseBridge,
        'lip_fullness': lipFullness,
        'expression': expression,
        'observations': observations,
      };

  /// Short chips for the results screen — "Oval face", "Calm expression", "Wide-set eyes".
  List<String> get chips => [
        if (faceShape != null) '${_capitalise(faceShape!)} face',
        if (expression != null) '${_capitalise(expression!)} expression',
        if (eyeSet != null) '${_capitalise(eyeSet!)}-set eyes',
        if (foreheadHeight != null) '${_capitalise(foreheadHeight!)} forehead',
      ];

  bool get isEmpty => chips.isEmpty && observations.isEmpty;
}

/// "unclear" is a real answer from the model, not a value worth showing to anyone.
String? _trait(Object? raw) {
  final value = (raw as String?)?.trim();
  if (value == null || value.isEmpty || value == 'unclear') return null;
  return value;
}

String _capitalise(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

String _text(Object? raw) => raw?.toString().trim() ?? '';

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .map((entry) => (entry as Object?)?.toString().trim() ?? '')
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

/// The headline trait, shown in the hero card.
@immutable
class FaceCoreTrait {
  const FaceCoreTrait({this.title = '', this.summary = '', this.detail = ''});

  final String title;
  final String summary;
  final String detail;

  static FaceCoreTrait fromServer(Object? raw) {
    if (raw is! Map) return const FaceCoreTrait();
    return FaceCoreTrait(
      title: _text(raw['title']),
      summary: _text(raw['summary']),
      detail: _text(raw['detail']),
    );
  }

  Map<String, dynamic> toJson() =>
      {'title': title, 'summary': summary, 'detail': detail};

  bool get isEmpty => title.isEmpty && summary.isEmpty && detail.isEmpty;
}

/// One feature of the reading.
@immutable
class FacePart {
  const FacePart({
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

  final FacePartKind kind;
  final String title;

  /// The tradition's name for this feature, transliterated — "Netra" for the eyes. Shown once
  /// beside the title and never again in the section.
  final String sanskrit;

  final ReadingStatus status;

  /// The one-liner on the results row.
  final String summary;

  /// The paragraph on the detail screen.
  final String detail;

  /// "What it means for you" — three or four bullets.
  final List<String> meaning;

  final String tip;

  /// The section's closing ashirvad. A wish, never a promise.
  final String blessing;

  /// Null when the entry names a feature this build does not know, or carries no reading at all.
  static FacePart? fromServer(Object? raw) {
    if (raw is! Map) return null;

    final kind = FacePartKind.parse(raw['key']);
    if (kind == null) return null;

    final detail = _text(raw['detail']);
    if (detail.isEmpty) return null;

    final title = _text(raw['title']);

    return FacePart(
      kind: kind,
      title: title.isEmpty ? kind.label : title,
      sanskrit: _text(raw['sanskrit']),
      status: ReadingStatus.parse(raw['status']),
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
  /// The Sanskrit term is left out on purpose: it is a visual flourish beside the title, and a
  /// device voice that has never seen the word turns it into noise.
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
class FaceReading {
  const FaceReading({
    required this.id,
    required this.createdAt,
    required this.focus,
    required this.parts,
    this.invocation = '',
    this.headline = '',
    this.blessing = '',
    this.coreTrait = const FaceCoreTrait(),
    this.traits = const [],
    this.face = const FaceObservations(),
    this.imageFileName,
  });

  final String id;
  final DateTime createdAt;
  final PalmFocus focus;
  final List<FacePart> parts;
  final String invocation;
  final String headline;
  final String blessing;
  final FaceCoreTrait coreTrait;
  final List<FaceTraitKind> traits;
  final FaceObservations face;

  /// The captured photograph's file *name* under the app's face directory — never an absolute
  /// path. iOS rewrites the application container path on reinstall and on restore from backup,
  /// so a stored absolute path is a broken image on every restored device.
  ///
  /// Null once the photo is gone: the reading text outlives it, and the screens fall back.
  final String? imageFileName;

  /// Null when the payload is not a reading at all. A reading that parses to zero features is
  /// also null — there would be nothing to show.
  static FaceReading? fromServer(Object? raw) {
    if (raw is! Map) return null;

    final id = _text(raw['id']);
    if (id.isEmpty) return null;

    final parts = <FacePart>[];
    final seen = <FacePartKind>{};
    for (final entry in (raw['parts'] is List ? raw['parts'] as List : const [])) {
      final part = FacePart.fromServer(entry);
      if (part == null || !seen.add(part.kind)) continue;
      parts.add(part);
    }

    if (parts.isEmpty) return null;

    // Declaration order is display order, so this restores the intended order even if a future
    // server sends them in another one.
    parts.sort((a, b) => a.kind.index.compareTo(b.kind.index));

    final traits = <FaceTraitKind>[];
    for (final entry in (raw['traits'] is List ? raw['traits'] as List : const [])) {
      final trait = FaceTraitKind.parse(entry);
      if (trait != null && !traits.contains(trait)) traits.add(trait);
    }

    return FaceReading(
      id: id,
      createdAt: DateTime.tryParse(_text(raw['created_at']))?.toLocal() ?? DateTime.now(),
      focus: PalmFocus.parse(raw['focus']),
      parts: parts,
      invocation: _text(raw['invocation']),
      headline: _text(raw['headline']),
      blessing: _text(raw['blessing']),
      coreTrait: FaceCoreTrait.fromServer(raw['core_trait']),
      traits: traits,
      face: FaceObservations.fromServer(raw['face']),
      imageFileName:
          _text(raw['image_file_name']).isEmpty ? null : _text(raw['image_file_name']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'focus': focus.wire,
        'invocation': invocation,
        'headline': headline,
        'blessing': blessing,
        'core_trait': coreTrait.toJson(),
        'traits': [for (final trait in traits) trait.wire],
        'face': face.toJson(),
        'parts': [for (final part in parts) part.toJson()],
        'image_file_name': imageFileName,
      };

  FaceReading copyWith({String? imageFileName}) => FaceReading(
        id: id,
        createdAt: createdAt,
        focus: focus,
        parts: parts,
        invocation: invocation,
        headline: headline,
        blessing: blessing,
        coreTrait: coreTrait,
        traits: traits,
        face: face,
        imageFileName: imageFileName ?? this.imageFileName,
      );

  FacePart? part(FacePartKind kind) {
    for (final part in parts) {
      if (part.kind == kind) return part;
    }
    return null;
  }

  /// What the speak button reads out on the results screen: the overview, not every paragraph.
  String get spoken => [
        if (invocation.isNotEmpty) invocation,
        if (headline.isNotEmpty) headline,
        if (!coreTrait.isEmpty) ...[
          'Your core trait. ${coreTrait.title}.',
          coreTrait.summary,
          coreTrait.detail,
        ],
        'Here is what your face reveals.',
        for (final part in parts) '${part.title}. ${part.summary}',
        if (blessing.isNotEmpty) blessing,
      ].where((line) => line.trim().isNotEmpty).join('\n\n');
}
