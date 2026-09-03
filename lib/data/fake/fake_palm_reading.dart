import 'dart:typed_data';

import '../models/palm_reading.dart';
import '../repositories/palm_repository.dart';

/// A canned reading, for the tier with no Supabase configured.
///
/// Two jobs. It keeps the app walkable end to end on a checkout that has never been pointed at
/// a project — the same promise `FakeAuthRepository` makes for sign-in — and it makes the scan
/// screen's timing observable while building it, which is otherwise impossible without a
/// physical device and a real ten-second model call.
class FakePalmRepository implements PalmRepository {
  const FakePalmRepository({this.latency = const Duration(seconds: 9)});

  /// Matches what the real model actually takes, measured at ~9-11s for a full reading. A
  /// shorter delay here would make the scan screen look better than it will ever look in
  /// production, which is the opposite of useful.
  final Duration latency;

  @override
  Future<PalmReading> read({
    required Uint8List image,
    required PalmFocus focus,
  }) async {
    await Future<void>.delayed(latency);

    // A tiny image is the fake tier's stand-in for "that was not a palm", so the rejection
    // path can be walked without finding something that genuinely is not a hand.
    if (image.lengthInBytes < 1024) {
      throw const NoPalmDetectedException(
        "We couldn't find a palm in that photo. Hold your open hand inside the frame.",
      );
    }

    return fakePalmReading(focus);
  }
}

/// The canned reading itself, also used by the widget tests so they render real prose rather
/// than lorem ipsum — text that is too short hides the overflow bugs the tests exist to catch.
PalmReading fakePalmReading(PalmFocus focus) {
  return PalmReading(
    id: 'demo-reading',
    createdAt: DateTime.now(),
    focus: focus,
    headline: 'A grounded, loyal hand guided by patience and quiet strength',
    strongestTrait: const PalmTrait(
      title: 'Independent & Intuitive',
      summary: 'You trust your own read of a situation before anyone else\'s.',
      detail:
          'The skin across your palm is smooth and the shape is broad, and hands built this '
          'way tend to belong to people who think a problem through rather than rush at it. '
          'You gather your own evidence, and you are slow to be talked out of a conclusion '
          'you reached honestly.',
    ),
    hand: const HandTraits(
      whichHand: 'right',
      skinTexture: 'smooth',
      firmness: 'soft',
      palmShape: 'broad',
      fingerLength: 'medium',
      visibleMarks: 'none',
      observations: [
        'The skin is smooth and unmarked, with fine, clearly drawn creases.',
        'The palm is broad and sits in easy proportion to medium-length fingers.',
      ],
    ),
    lines: [
      const PalmLine(
        kind: PalmLineKind.heart,
        title: 'Heart Line',
        status: PalmLineStatus.strong,
        summary: 'You tend to value deep emotional connections.',
        detail:
            'Running long and gently curved across the upper palm, this line keeps its depth '
            'the whole way. Read together with the softness of your hand, it suggests warmth '
            'that is offered steadily rather than in bursts, and a preference for people who '
            'stay.',
        meaning: [
          'You are affectionate and express what you feel sincerely.',
          'You seek meaningful relationships over casual connections.',
          'You are empathetic, and often put others\' needs before your own.',
        ],
        tip: 'Keep your heart open, but remember to set healthy boundaries too.',
      ),
      const PalmLine(
        kind: PalmLineKind.life,
        title: 'Life Line',
        status: PalmLineStatus.deep,
        summary: 'Steady stamina and a reassuring, grounded presence.',
        detail:
            'Sweeping in a wide arc around the base of the thumb, this line is well defined '
            'along its whole length. The cushion beneath it is full, which points to good '
            'everyday energy and a knack for recovering your balance after a difficult '
            'stretch.',
        meaning: [
          'You have consistent energy for the things that matter to you.',
          'You recover your composure quickly after stressful periods.',
          'People around you tend to find you steadying.',
        ],
        tip: 'Protect your evenings — your energy holds up best when your rest does.',
      ),
      const PalmLine(
        kind: PalmLineKind.head,
        title: 'Head Line',
        status: PalmLineStatus.balanced,
        summary: 'Practical thinking, applied calmly under pressure.',
        detail:
            'Crossing the middle of the palm cleanly and without fraying, this line runs '
            'straight for most of its length before softening. That shape leans toward '
            'realism: when something goes wrong you tend to look for the workable answer '
            'rather than the satisfying one.',
        meaning: [
          'You weigh decisions carefully before committing to them.',
          'You can tell genuine support apart from an empty promise.',
          'You prefer plain, transparent conversation to hinting.',
        ],
        tip: 'Trust a first instinct more often — yours is better than you credit it.',
      ),
      const PalmLine(
        kind: PalmLineKind.fate,
        title: 'Fate Line',
        status: PalmLineStatus.developing,
        summary: 'A path you are still shaping, and shaping deliberately.',
        detail:
            'Rising from near the base of a broad palm, this line strengthens as it climbs '
            'rather than arriving fully formed. Hands like yours often build a direction '
            'gradually, out of choices made one at a time, instead of following a route laid '
            'out by someone else.',
        meaning: [
          'Your direction is self-chosen rather than inherited.',
          'Steady habits serve you better than dramatic changes.',
          'Independence sits comfortably alongside your commitments.',
        ],
        tip: 'Mark the small milestones. They are what the line is actually made of.',
      ),
      const PalmLine(
        kind: PalmLineKind.sun,
        title: 'Sun Line',
        status: PalmLineStatus.clear,
        summary: 'Quiet contentment that others notice before you do.',
        detail:
            'Showing as fine vertical marks beneath the ring finger, this area is lightly but '
            'clearly drawn. It speaks to satisfaction found in ordinary things — work done '
            'well, a good evening — and to a warmth that puts people at ease without any '
            'effort on your part.',
        meaning: [
          'You take real pleasure in creative or domestic routines.',
          'Your warmth makes people comfortable quickly.',
          'Recognition tends to find you rather than the reverse.',
        ],
        tip: 'Let yourself celebrate something small this week, for no particular reason.',
      ),
      const PalmLine(
        kind: PalmLineKind.mercury,
        title: 'Mercury Line',
        status: PalmLineStatus.faint,
        summary: 'Direct, unadorned communication.',
        detail:
            'The outer edge below the little finger is largely clear and uncluttered. That '
            'openness suggests you say what you mean when it matters, without layering it in '
            'subtext, and that you listen properly rather than waiting for your turn.',
        meaning: [
          'You prefer plain speaking to elaborate hinting.',
          'Your listening makes people feel genuinely heard.',
          'You stay calm through sensitive conversations.',
        ],
        tip: 'Say the appreciative thing out loud rather than assuming it was obvious.',
      ),
      const PalmLine(
        kind: PalmLineKind.marriage,
        title: 'Relationship Line',
        status: PalmLineStatus.strong,
        summary: 'Depth and permanence over breadth.',
        detail:
            'Set along the side of the palm beneath the little finger, this marking is short '
            'but firmly drawn. Together with the steadiness elsewhere in your hand, it points '
            'to someone who treats closeness as something built over years rather than '
            'discovered all at once.',
        meaning: [
          'You want partnership founded on equal footing.',
          'You guard the confidences of people you love.',
          'You will invest patient effort in a bond worth keeping.',
        ],
        tip: 'Protect one unhurried, undistracted hour together each week.',
      ),
      const PalmLine(
        kind: PalmLineKind.mars,
        title: 'Mars Line',
        status: PalmLineStatus.developing,
        summary: 'Resilience that shows up for other people first.',
        detail:
            'A faint supporting crease runs inside the main life curve on the lower palm. '
            'Hands carrying this mark often hold steady for others in a crisis, becoming the '
            'calm the room borrows from — sometimes long before they admit to needing any '
            'of it themselves.',
        meaning: [
          'You stand by the people you have chosen.',
          'Difficulty tends to make you calmer, not louder.',
          'Your endurance is quiet and easy to underestimate.',
        ],
        tip: 'Leaning on someone else is its own kind of trust. Try it occasionally.',
      ),
    ],
  );
}
