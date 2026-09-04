import 'package:astrolok/data/local/reading_store.dart';
import 'package:astrolok/data/models/face_reading.dart';
import 'package:astrolok/data/models/palm_reading.dart' show PalmFocus;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Parsing a face reading, and caching one.
///
/// The server normalises before it stores, so most of what is guarded here is the *other*
/// direction: a row written by a newer server that knows about a feature this build does not.
/// The rule is the same one `palm_reading.dart` follows — degrade to less, never throw.

Map<String, dynamic> part(String key, [Map<String, dynamic> over = const {}]) => {
      'key': key,
      'title': '$key title',
      'sanskrit': 'Netra',
      'status': 'Strong',
      'summary': 'A short summary.',
      'detail': 'A paragraph about this feature.',
      'meaning': ['One.', 'Two.', 'Three.'],
      'tip': 'A small nudge.',
      'blessing': 'May it stay so.',
      ...over,
    };

Map<String, dynamic> payload([Map<String, dynamic> over = const {}]) => {
      'id': 'face-1',
      'created_at': '2026-09-04T10:00:00Z',
      'focus': 'love',
      'invocation': 'Come, sit a moment.',
      'headline': 'A calm face.',
      'blessing': 'May your calm keep finding you good company.',
      'core_trait': {
        'title': 'Naturally Intuitive',
        'summary': 'You sense things deeply.',
        'detail': 'A longer paragraph.',
      },
      'traits': ['independent', 'observant', 'warm', 'determined'],
      'face': {
        'face_shape': 'oval',
        'expression': 'calm',
        'eye_set': 'balanced',
        'observations': ['The gaze is steady.'],
      },
      'parts': [
        for (final key in ['eyes', 'face_shape', 'nose', 'lips', 'forehead', 'eyebrows'])
          part(key),
      ],
      ...over,
    };

void main() {
  group('FaceReading.fromServer', () {
    test('parses a complete payload', () {
      final reading = FaceReading.fromServer(payload())!;

      expect(reading.id, 'face-1');
      expect(reading.focus, PalmFocus.love);
      expect(reading.parts, hasLength(6));
      expect(reading.headline, 'A calm face.');
      expect(reading.invocation, 'Come, sit a moment.');
      expect(reading.blessing, startsWith('May your calm'));
      expect(reading.coreTrait.title, 'Naturally Intuitive');
      expect(reading.traits, hasLength(4));
      expect(reading.face.faceShape, 'oval');
    });

    test('restores display order regardless of what the server sent', () {
      final shuffled = payload({
        'parts': [
          for (final key in ['lips', 'eyebrows', 'eyes', 'nose', 'forehead', 'face_shape'])
            part(key),
        ],
      });

      expect(
        FaceReading.fromServer(shuffled)!.parts.map((p) => p.kind),
        FacePartKind.values,
      );
    });

    test('drops a feature this build does not know, rather than defaulting it', () {
      // Rendering an "Eyes" row for something the server called `cheekbones` would be a reading
      // of the wrong thing. Five right rows beat six where one lies about its subject.
      final reading = FaceReading.fromServer(payload({
        'parts': [part('eyes'), part('nose'), part('cheekbones')],
      }))!;

      expect(reading.parts, hasLength(2));
      expect(reading.parts.map((p) => p.kind), [FacePartKind.eyes, FacePartKind.nose]);
    });

    test('drops a duplicate feature', () {
      final reading = FaceReading.fromServer(payload({
        'parts': [part('eyes'), part('eyes'), part('nose')],
      }))!;

      expect(reading.parts, hasLength(2));
    });

    test('an unrecognised status defaults rather than costing the feature', () {
      final reading = FaceReading.fromServer(payload({
        'parts': [part('eyes', {'status': 'Luminous'})],
      }))!;

      expect(reading.parts.single.status, ReadingStatus.balanced);
    });

    test('a feature with no detail is dropped, and a missing title falls back', () {
      final reading = FaceReading.fromServer(payload({
        'parts': [
          part('eyes', {'detail': '   '}),
          part('nose', {'title': ''}),
        ],
      }))!;

      expect(reading.parts, hasLength(1));
      expect(reading.parts.single.title, 'Nose');
    });

    test('unknown trait words are dropped, because the app draws an icon per trait', () {
      final reading = FaceReading.fromServer(payload({
        'traits': ['warm', 'radiant', 'loyal', 'warm'],
      }))!;

      expect(reading.traits, [FaceTraitKind.warm, FaceTraitKind.loyal]);
    });

    test('a payload with no readable features is null, not an empty screen', () {
      expect(FaceReading.fromServer(payload({'parts': []})), isNull);
      expect(FaceReading.fromServer(payload({'parts': 'nonsense'})), isNull);
    });

    test('a malformed payload is null rather than a throw', () {
      for (final raw in [null, 'not a map', 42, <String, dynamic>{}]) {
        expect(FaceReading.fromServer(raw), isNull);
      }
      // An id is required; without one the screens could not route back to it.
      expect(FaceReading.fromServer(payload({'id': ''})), isNull);
    });

    test('an unknown focus falls back rather than throwing', () {
      expect(FaceReading.fromServer(payload({'focus': 'health'}))!.focus,
          PalmFocus.lifePath);
    });

    test('"unclear" observations are treated as absent', () {
      // A real answer from the model, and not one worth showing anybody.
      final reading = FaceReading.fromServer(payload({
        'face': {'face_shape': 'unclear', 'expression': 'calm'},
      }))!;

      expect(reading.face.faceShape, isNull);
      expect(reading.face.chips, ['Calm expression']);
    });

    test('a face with nothing readable in it is empty rather than a row of blanks', () {
      final reading = FaceReading.fromServer(payload({'face': {}}))!;
      expect(reading.face.isEmpty, isTrue);
    });
  });

  group('the spoken reading', () {
    test('opens on the invocation and closes on the blessing', () {
      final reading = FaceReading.fromServer(payload())!;
      final spoken = reading.spoken;

      expect(spoken, startsWith('Come, sit a moment.'));
      expect(spoken, endsWith('May your calm keep finding you good company.'));
    });

    test('leaves the Sanskrit term out, which a device voice cannot say', () {
      expect(FaceReading.fromServer(payload())!.parts.first.spoken, isNot(contains('Netra')));
    });
  });

  group('round-tripping through the cache', () {
    test('survives toJson and back', () {
      final original = FaceReading.fromServer(payload())!;
      final restored = FaceReading.fromServer(original.toJson())!;

      expect(restored.parts, hasLength(original.parts.length));
      expect(restored.traits, original.traits);
      expect(restored.invocation, original.invocation);
      expect(restored.blessing, original.blessing);
      expect(restored.parts.first.sanskrit, 'Netra');
      expect(restored.face.chips, original.face.chips);
    });
  });

  group('FaceReadingStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('saves and reads back on an empty cache', () async {
      const store = FaceReadingStore();
      await store.save(FaceReading.fromServer(payload())!);

      expect(await store.all(), hasLength(1));
      expect((await store.byId('face-1'))?.headline, 'A calm face.');
    });

    test('keeps its own key, so palm and face do not overwrite each other', () async {
      const face = FaceReadingStore();
      const palm = PalmReadingStore();

      await face.save(FaceReading.fromServer(payload())!);

      expect(await face.all(), hasLength(1));
      expect(await palm.all(), isEmpty);
    });

    test('keeps only the ten newest', () async {
      const store = FaceReadingStore();
      for (var i = 0; i < 13; i++) {
        await store.save(FaceReading.fromServer(payload({'id': 'face-$i'}))!);
      }

      final all = await store.all();
      expect(all, hasLength(10));
      expect(all.first.id, 'face-12');
    });

    test('a corrupt cache reads as empty rather than throwing', () async {
      SharedPreferences.setMockInitialValues({
        'astrolok.face_readings': 'not json at all',
      });

      expect(await const FaceReadingStore().all(), isEmpty);
    });
  });
}
