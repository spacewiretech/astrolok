import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Reads a palm reading aloud, using the voice already on the device.
///
/// On-device rather than synthesised server-side: it starts speaking instantly, costs nothing
/// per play, and works with no signal — all of which matter for something a user replays.
///
/// Every method is best-effort. A device with no speech engine is not an error worth showing;
/// the screens hide the control instead, because a button that does nothing reads as a bug
/// while an absent one reads as a design.
class PalmSpeech {
  PalmSpeech([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  bool _ready = false;
  bool _available = false;

  /// Bumped on every [stop]. A chunk loop compares it against the value it started with, so a
  /// second tap cancels the first playback rather than the two interleaving.
  int _generation = 0;

  /// Some Android engines truncate long strings and become sluggish to stop mid-utterance.
  /// Speaking in sentence-sized pieces also makes stopping feel immediate.
  static const _maxChunk = 300;

  bool get isAvailable => _available;

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;

    try {
      if (Platform.isIOS) {
        // Without these, speech is silent whenever the ringer switch is on silent — which is
        // most phones, most of the time. It is the single most common way this feature ships
        // broken, and it fails quietly.
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          ],
        );
      }

      // Indian English when the device has it — the reading's voice and idiom are Indian, and
      // an American voice reading "Namaste" lands badly.
      final hasIndian = await _tts.isLanguageAvailable('en-IN');
      await _tts.setLanguage(hasIndian == true ? 'en-IN' : 'en-US');

      // The scales differ by platform: 0.5 is ordinary on Android and noticeably fast on iOS.
      await _tts.setSpeechRate(Platform.isIOS ? 0.45 : 0.52);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);

      // Makes `speak` complete when the utterance finishes rather than when it starts, which
      // is what lets the chunks below run in sequence instead of talking over each other.
      await _tts.awaitSpeakCompletion(true);

      _available = true;
    } catch (error) {
      debugPrint('[palm] speech unavailable: $error');
      _available = false;
    }
  }

  /// True once the device is known to have a working engine. Called before the speak button is
  /// drawn, so the button can be left out entirely when it would do nothing.
  Future<bool> prepare() async {
    await _init();
    return _available;
  }

  /// Speaks [text], stopping anything already playing.
  ///
  /// Returns when the whole thing has been read, or as soon as a later call cancels it, so a
  /// caller can await it to know when to drop its "speaking" flag.
  Future<void> speak(String text) async {
    await _init();
    if (!_available) return;

    await stop();
    final generation = _generation;

    try {
      for (final chunk in _chunk(text)) {
        // A stop, or another speak, happened while the previous chunk was playing.
        if (generation != _generation) return;
        await _tts.speak(chunk);
      }
    } catch (error) {
      debugPrint('[palm] speech failed: $error');
    }
  }

  Future<void> stop() async {
    if (!_available) return;
    _generation++;
    try {
      await _tts.stop();
    } catch (error) {
      debugPrint('[palm] could not stop speech: $error');
    }
  }

  /// Splits on sentence ends, then regroups into pieces under [_maxChunk].
  ///
  /// Grouping back up matters: speaking sentence by sentence leaves an audible gap at every
  /// full stop, and a reading is eight paragraphs long.
  static List<String> _chunk(String text) {
    final sentences = text
        .split(RegExp(r'(?<=[.!?])\s+|\n+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    final chunks = <String>[];
    final buffer = StringBuffer();

    for (final sentence in sentences) {
      if (buffer.isNotEmpty && buffer.length + sentence.length + 1 > _maxChunk) {
        chunks.add(buffer.toString());
        buffer.clear();
      }
      if (buffer.isNotEmpty) buffer.write(' ');

      // A single sentence longer than the cap goes out on its own rather than being cut in
      // the middle of a clause.
      buffer.write(sentence);
    }

    if (buffer.isNotEmpty) chunks.add(buffer.toString());
    return chunks;
  }

  Future<void> dispose() => stop();
}
