import 'package:astrolok/data/local/palm_reading_store.dart';
import 'package:astrolok/data/models/palm_reading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The reading is written by a language model and normalised by a server this build may be
/// older than, so the parser has to survive a payload it has never seen. The rule under test
/// throughout: degrade to less, never throw.
void main() {
  Map<String, dynamic> line(String key) => {
        'key': key,
        'title': '${key.toUpperCase()} Line',
        'status': 'Strong',
        'summary': 'A summary.',
        'detail': 'A detailed paragraph about the line.',
        'meaning': ['One.', 'Two.', 'Three.'],
        'tip': 'A tip.',
      };

  Map<String, dynamic> payload({List<Object?>? lines}) => {
        'id': 'reading-1',
        'created_at': '2026-09-04T09:30:00Z',
        'focus': 'love',
        'headline': 'A warm hand.',
        'strongest_trait': {
          'title': 'Independent',
          'summary': 'You trust yourself.',
          'detail': 'A longer paragraph.',
        },
        'hand': {
          'which_hand': 'right',
          'skin_texture': 'smooth',
          'firmness': 'soft',
          'palm_shape': 'broad',
          'observations': ['The skin is smooth.', 'The palm is broad.'],
        },
        'lines': lines ??
            ['heart', 'life', 'head', 'fate', 'sun', 'mercury', 'marriage', 'mars']
                .map(line)
                .toList(),
      };

  group('PalmReading.fromServer', () {
    test('parses a complete payload', () {
      final reading = PalmReading.fromServer(payload())!;

      expect(reading.id, 'reading-1');
      expect(reading.focus, PalmFocus.love);
      expect(reading.lines, hasLength(8));
      expect(reading.headline, 'A warm hand.');
      expect(reading.strongestTrait.title, 'Independent');
      expect(reading.hand.observations, hasLength(2));
    });

    test('orders lines for display regardless of the order received', () {
      final shuffled = payload(
        lines: ['mars', 'sun', 'heart', 'marriage', 'life', 'mercury', 'head', 'fate']
            .map(line)
            .toList(),
      );

      final reading = PalmReading.fromServer(shuffled)!;

      expect(
        reading.lines.map((l) => l.kind).toList(),
        PalmLineKind.values,
      );
    });

    test('drops a line this build does not know', () {
      // Rendering a "Heart Line" row for something the server called girdle_of_venus would be
      // a reading about the wrong thing, so seven rows is the better answer.
      final reading = PalmReading.fromServer(
        payload(lines: [line('heart'), line('girdle_of_venus'), line('life')]),
      )!;

      expect(reading.lines, hasLength(2));
      expect(reading.lines.map((l) => l.kind),
          [PalmLineKind.heart, PalmLineKind.life]);
    });

    test('drops a duplicate, keeping the first', () {
      final duplicate = line('heart')..['title'] = 'Impostor';
      final reading = PalmReading.fromServer(
        payload(lines: [line('heart'), duplicate]),
      )!;

      expect(reading.lines, hasLength(1));
      expect(reading.lines.single.title, 'HEART Line');
    });

    test('drops a line with no reading in it', () {
      final empty = line('life')..['detail'] = '   ';
      final reading =
          PalmReading.fromServer(payload(lines: [line('heart'), empty]))!;

      expect(reading.lines, hasLength(1));
    });

    test('an unknown status falls back rather than costing the line', () {
      final odd = line('heart')..['status'] = 'Sparkling';
      final reading = PalmReading.fromServer(payload(lines: [odd]))!;

      expect(reading.lines, hasLength(1));
      expect(reading.lines.single.status, PalmLineStatus.balanced);
    });

    test('a missing title falls back to the canonical label', () {
      final untitled = line('mercury')..['title'] = '';
      final reading = PalmReading.fromServer(payload(lines: [untitled]))!;

      // Never "Health Line" — the reading must not carry a medical framing.
      expect(reading.lines.single.title, 'Mercury Line');
    });

    test('missing bullets degrade to an empty list', () {
      final bare = line('heart')..remove('meaning');
      final reading = PalmReading.fromServer(payload(lines: [bare]))!;

      expect(reading.lines.single.meaning, isEmpty);
      expect(reading.lines.single.detail, isNotEmpty);
    });

    test('an unknown focus falls back to the life path', () {
      final odd = payload()..['focus'] = 'health';
      expect(PalmReading.fromServer(odd)!.focus, PalmFocus.lifePath);
    });

    test('garbage yields null rather than throwing', () {
      for (final raw in [null, 'a string', 42, <String>[], <String, dynamic>{}]) {
        expect(PalmReading.fromServer(raw), isNull, reason: 'on $raw');
      }
    });

    test('a payload with no usable lines yields null', () {
      // Nothing to render, so the screens treat it as a missing reading rather than an empty
      // one — an empty results page would look like a bug.
      expect(PalmReading.fromServer(payload(lines: [])), isNull);
      expect(PalmReading.fromServer(payload(lines: [line('unknown')])), isNull);
    });

    test('a missing id yields null', () {
      final anonymous = payload()..remove('id');
      expect(PalmReading.fromServer(anonymous), isNull);
    });
  });

  group('HandTraits', () {
    test('"unclear" is dropped rather than shown to anyone', () {
      final reading = PalmReading.fromServer(
        payload()..['hand'] = {'firmness': 'unclear', 'skin_texture': 'smooth'},
      )!;

      expect(reading.hand.firmness, isNull);
      expect(reading.hand.skinTexture, 'smooth');
      expect(reading.hand.chips, ['Smooth skin']);
    });

    test('chips read as a sentence fragment, capitalised', () {
      final reading = PalmReading.fromServer(payload())!;
      expect(reading.hand.chips, ['Soft hands', 'Smooth skin', 'Broad palm']);
    });
  });

  group('spoken text', () {
    test('the overview covers the headline, trait and every line', () {
      final spoken = PalmReading.fromServer(payload())!.spoken;

      expect(spoken, contains('A warm hand.'));
      expect(spoken, contains('Independent'));
      expect(spoken, contains('HEART Line'));
      expect(spoken, isNot(contains('null')));
    });

    test('a line reads its detail, bullets and tip', () {
      final line = PalmReading.fromServer(payload())!.line(PalmLineKind.heart)!;

      expect(line.spoken, contains('A detailed paragraph'));
      expect(line.spoken, contains('One.'));
      expect(line.spoken, contains('A tip.'));
    });
  });

  group('round trip', () {
    test('survives toJson and back', () {
      final original = PalmReading.fromServer(payload())!;
      final restored = PalmReading.fromServer(original.toJson())!;

      expect(restored.id, original.id);
      expect(restored.lines, hasLength(original.lines.length));
      expect(restored.lines.first.meaning, original.lines.first.meaning);
      expect(restored.hand.chips, original.hand.chips);
      expect(restored.focus, original.focus);
    });
  });

  group('PalmReadingStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('saves and reads back on an empty cache', () async {
      // The first save on a fresh install: `all()` returns an unmodifiable empty list, and an
      // earlier version mutated it in place, so this path threw for every new user.
      final store = PalmReadingStore();
      final reading = PalmReading.fromServer(payload())!;

      await store.save(reading);

      expect((await store.all()), hasLength(1));
      expect((await store.byId('reading-1'))?.headline, 'A warm hand.');
    });

    test('replaces a reading rather than duplicating it', () async {
      final store = PalmReadingStore();
      final reading = PalmReading.fromServer(payload())!;

      await store.save(reading);
      await store.save(reading.copyWith(imageFileName: 'reading-1.jpg'));

      final all = await store.all();
      expect(all, hasLength(1));
      expect(all.single.imageFileName, 'reading-1.jpg');
    });

    test('keeps only the ten newest', () async {
      final store = PalmReadingStore();
      for (var i = 0; i < 14; i++) {
        await store.save(
          PalmReading.fromServer(payload()..['id'] = 'reading-$i')!,
        );
      }

      final all = await store.all();
      expect(all, hasLength(10));
      // Newest first.
      expect(all.first.id, 'reading-13');
    });

    test('a cache from an older version is discarded, not half-parsed', () async {
      SharedPreferences.setMockInitialValues({
        'astrolok.palm_readings': '{"v":0,"readings":[{"id":"old"}]}',
      });

      expect(await PalmReadingStore().all(), isEmpty);
    });

    test('a corrupt cache reads as empty rather than throwing', () async {
      SharedPreferences.setMockInitialValues({
        'astrolok.palm_readings': 'not json at all',
      });

      expect(await PalmReadingStore().all(), isEmpty);
    });
  });
}
