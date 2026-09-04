import 'dart:typed_data';

import '../models/face_reading.dart';
import '../models/palm_reading.dart' show PalmFocus;
import '../repositories/face_repository.dart';

/// A canned reading, for the tier with no Supabase configured.
///
/// Two jobs, the same two `FakePalmRepository` has. It keeps the app walkable end to end on a
/// checkout that has never been pointed at a project, and it makes the scan screen's timing
/// observable while building it — otherwise impossible without a physical device, a front
/// camera and a real ten-second model call.
class FakeFaceRepository implements FaceRepository {
  const FakeFaceRepository({this.latency = const Duration(seconds: 9)});

  /// Matches what the real model actually takes, measured at ~9-11s for a full reading. A
  /// shorter delay here would make the scan screen look better than it will ever look in
  /// production, which is the opposite of useful.
  final Duration latency;

  @override
  Future<FaceReading> read({
    required Uint8List image,
    required PalmFocus focus,
  }) async {
    await Future<void>.delayed(latency);

    // A tiny image is the fake tier's stand-in for "that was not a face", so the rejection path
    // can be walked without having to find something that genuinely is not one.
    if (image.lengthInBytes < 1024) {
      throw const NoFaceDetectedException(
        "We couldn't find a face in that photo. Hold the camera at eye level and look ahead.",
      );
    }

    return fakeFaceReading(focus);
  }
}

/// The canned reading itself, also used by the widget tests so they render real prose rather
/// than lorem ipsum — text that is too short hides the overflow bugs the tests exist to catch.
///
/// Written in the same register the prompt asks for: one transliterated term per section with a
/// gloss, an invocation at the top, an ashirvad at the bottom, and not one deterministic verb.
FaceReading fakeFaceReading(PalmFocus focus) {
  return FaceReading(
    id: 'demo-face-reading',
    createdAt: DateTime.now(),
    focus: focus,
    invocation: 'Come, sit a moment. Let us look at what your face has been carrying.',
    headline: 'A calm face that watches before it speaks',
    coreTrait: const FaceCoreTrait(
      title: 'Naturally Intuitive',
      summary: 'You have a calm wisdom that helps you sense things deeply.',
      detail:
          'The gaze is steady and the brow sits unhurried above it, and faces held this way '
          'tend to belong to people who take a room in before they enter it. You gather more '
          'than you are given, and you are slow to be talked out of what you noticed.',
    ),
    traits: const [
      FaceTraitKind.independent,
      FaceTraitKind.observant,
      FaceTraitKind.warm,
      FaceTraitKind.determined,
    ],
    face: const FaceObservations(
      faceShape: 'oval',
      foreheadHeight: 'high',
      eyebrowThickness: 'medium',
      eyeSet: 'balanced',
      noseBridge: 'straight',
      lipFullness: 'medium',
      expression: 'calm',
      observations: [
        'The three zones of the face sit in easy proportion, with none crowding the others.',
        'The gaze is level and unhurried, and the mouth rests without tension.',
      ],
    ),
    parts: [
      const FacePart(
        kind: FacePartKind.eyes,
        title: 'Eyes',
        sanskrit: 'Netra',
        status: ReadingStatus.strong,
        summary: 'A steady gaze that reads a room before speaking.',
        detail:
            'Your Netra — the eyes — are evenly set and the gaze rests rather than darts, and '
            'eyes carried this way suggest a strong intuitive nature. You tend to notice the '
            'subtle detail, read people quickly, and understand a situation beyond what is '
            'directly said to you.',
        meaning: [
          'You often sense when something feels right or wrong before you can explain why.',
          'Changes in expression, tone and behaviour rarely get past you.',
          'You are good at understanding what people mean beyond their words.',
          'Deep connections come more naturally to you than wide, shallow ones.',
        ],
        tip: 'Keep your heart open, but remember to set healthy boundaries too.',
        blessing: 'May your sight stay clear and your heart stay soft.',
      ),
      const FacePart(
        kind: FacePartKind.faceShape,
        title: 'Face Shape',
        sanskrit: 'Mukha Akriti',
        status: ReadingStatus.balanced,
        summary: 'Even proportions, and a temperament that matches them.',
        detail:
            'The Mukha Akriti — the overall cast of the face — is oval, with the forehead, '
            'mid-face and jaw sharing the space evenly. Proportions like these lean toward '
            'people who adapt without losing their shape, who can sit with a difficult mood '
            'and come out of it much the same person who went in.',
        meaning: [
          'You adjust to new company without becoming a different person in it.',
          'Extremes of mood tend to pass through you rather than settle.',
          'People find you easy to be around before they can say quite why.',
        ],
        tip: 'Being easy to be around is a gift; make sure it is not costing you your no.',
        blessing: 'May your balance hold, and may it never be mistaken for indifference.',
      ),
      const FacePart(
        kind: FacePartKind.nose,
        title: 'Nose',
        sanskrit: 'Nasika',
        status: ReadingStatus.developing,
        summary: 'Drive that builds steadily rather than arriving all at once.',
        detail:
            'A straight Nasika — the nose — sitting in proportion to the mid-face suggests '
            'energy that is spent deliberately. Rather than chasing every opening, people with '
            'this proportion tend to pick one thing and stay with it, and to be surprised '
            'later at how far that patience carried them.',
        meaning: [
          'You would rather finish one thing well than start four things brightly.',
          'Your ambition is real but quiet, and easy for others to underestimate.',
          'You spend energy where you can see it landing.',
        ],
        tip: 'Name what you are working toward out loud; it travels further when spoken.',
        blessing: 'May your steady effort keep meeting the doors it deserves.',
      ),
      const FacePart(
        kind: FacePartKind.lips,
        title: 'Lips',
        sanskrit: 'Adhara',
        status: ReadingStatus.clear,
        summary: 'Warmth in close company, measured in a crowd.',
        detail:
            'The Adhara — the lips — rest without tension and sit at a medium fullness. Mouths '
            'held this way suggest someone whose warmth is real but unhurried: you give it to '
            'the few rather than the many, and what you do say in a difficult moment tends to '
            'be remembered.',
        meaning: [
          'You are warmer one-to-one than you are in a room of ten.',
          'You choose your words in a disagreement rather than reaching for the first ones.',
          'People trust what you say partly because you say less of it.',
        ],
        tip: 'The people close to you would like to hear the warm thing you are thinking.',
        blessing: 'May your words keep finding the people who need them.',
      ),
      const FacePart(
        kind: FacePartKind.forehead,
        title: 'Forehead',
        sanskrit: 'Lalata',
        status: ReadingStatus.deep,
        summary: 'A long view, and a memory that keeps its receipts.',
        detail:
            'Your Lalata — the forehead — is high and open, unhurried above the brow. That '
            'proportion is traditionally read as reflection: a tendency to think a thing all '
            'the way through before committing to it, and to hold on to what was learned the '
            'last time something similar came around.',
        meaning: [
          'You think in years more comfortably than most people think in weeks.',
          'You are slow to be rushed, and usually right to be.',
          'Old lessons stay available to you long after others have mislaid theirs.',
        ],
        tip: 'Not every decision deserves the long view. Some just need making.',
        blessing: 'May your patience keep being wisdom and never become delay.',
      ),
      const FacePart(
        kind: FacePartKind.eyebrows,
        title: 'Eyebrows',
        sanskrit: 'Bhru',
        status: ReadingStatus.balanced,
        summary: 'Focus that holds without hardening.',
        detail:
            'The Bhru — the brows — run evenly at a medium thickness, without a sharp break in '
            'the arch. Brows like these suggest a will that stays engaged under pressure: you '
            'tend to meet resistance by leaning in a little rather than either forcing it or '
            'walking away from it.',
        meaning: [
          'You keep your temper in exactly the moments it would be easiest to lose.',
          'Obstacles make you more attentive rather than more frantic.',
          'You finish things that other people have already put down.',
        ],
        tip: 'Leaning in is a strength. Knowing which walls are load-bearing is another.',
        blessing: 'May your resolve stay warm, and may it rest when the work is done.',
      ),
    ],
    blessing:
        'May your calm keep finding you good company, and may what you notice always be met '
        'with kindness. Shubh ho.',
  );
}
