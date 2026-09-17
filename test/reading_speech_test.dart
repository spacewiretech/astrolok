import 'dart:async';

import 'package:astrolok/data/tts/reading_speech.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Narration was too quick to follow: a slightly-faster-than-ordinary rate, and every sentence and
/// section run together into one stream. These pin the rests that fixed it — and that a rest never
/// outlives a Stop, which is what keeps the Listen/Stop label honest.
void main() {
  const breath = Duration(milliseconds: 120);
  const rest = Duration(milliseconds: 350);

  group('segments', () {
    test('a breath inside a paragraph, a longer rest between them, nothing after the last', () {
      expect(ReadingSpeech.segments('Patience, not courage.\n\nThe Season Ahead\n\nOne. Two!'), [
        const SpeechSegment('Patience, not courage.', rest),
        const SpeechSegment('The Season Ahead', rest),
        const SpeechSegment('One.', breath),
        const SpeechSegment('Two!', Duration.zero),
      ]);
    });

    test('the danda ends a sentence, so Hindi is not one breathless utterance', () {
      expect(ReadingSpeech.segments('आपका चंद्र वृषभ में है। धैर्य रखें।'), [
        const SpeechSegment('आपका चंद्र वृषभ में है।', breath),
        const SpeechSegment('धैर्य रखें।', Duration.zero),
      ]);
    });

    test('blank text has nothing to say', () {
      expect(ReadingSpeech.segments(''), isEmpty);
      expect(ReadingSpeech.segments('  \n\n  \n '), isEmpty);
    });

    test('a heading with no full stop is still its own sentence', () {
      expect(ReadingSpeech.segments('Relationship Energy. A season for tending.\n\nA tip'), [
        const SpeechSegment('Relationship Energy.', breath),
        const SpeechSegment('A season for tending.', rest),
        const SpeechSegment('A tip', Duration.zero),
      ]);
    });
  });

  group('playback', () {
    Future<(ReadingSpeech, _FakeTts)> ready() async {
      final tts = _FakeTts();
      final speech = ReadingSpeech(tts);
      expect(await speech.prepare(language: 'english'), isTrue);
      return (speech, tts);
    }

    testWidgets('waits out the breath before the next sentence', (tester) async {
      final (speech, tts) = await ready();

      var finished = false;
      unawaited(speech.speak('One. Two.').then((_) => finished = true));
      await tester.pump();
      expect(tts.spoken, ['One.']);

      await tester.pump(breath - const Duration(milliseconds: 50));
      expect(tts.spoken, ['One.']);

      await tester.pump(const Duration(milliseconds: 60));
      expect(tts.spoken, ['One.', 'Two.']);
      expect(finished, isTrue);
    });

    testWidgets('Stop during a rest ends it at once, and nothing more is said', (tester) async {
      final (speech, tts) = await ready();

      var finished = false;
      unawaited(speech.speak('One.\n\nTwo.').then((_) => finished = true));
      await tester.pump();
      expect(tts.spoken, ['One.']);

      await speech.stop();
      await tester.pump();
      // Not left to finish when the rest runs out, when a new playback may have set the "speaking" flag this
      // one would then clear.
      expect(finished, isTrue);

      await tester.pump(const Duration(seconds: 1));
      expect(tts.spoken, ['One.']);
    });
  });
}

/// An engine that speaks instantly and remembers what it was given.
class _FakeTts extends FlutterTts {
  final spoken = <String>[];

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
    return 1;
  }

  @override
  Future<dynamic> stop() async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  @override
  Future<dynamic> setVolume(double volume) async => 1;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;

  @override
  Future<dynamic> isLanguageAvailable(String language) async => true;

  @override
  Future<dynamic> setLanguage(String language) async => 1;
}
