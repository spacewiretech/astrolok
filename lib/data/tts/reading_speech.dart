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
class ReadingSpeech {
  ReadingSpeech([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  bool _ready = false;
  bool _available = false;

  /// Bumped on every [stop]. A chunk loop compares it against the value it started with, so a
  /// second tap cancels the first playback rather than the two interleaving.
  int _generation = 0;

  /// Some Android engines truncate long strings and become sluggish to stop mid-utterance.
  /// Speaking in sentence-sized pieces also makes stopping feel immediate.
  static const _maxChunk = 300;

  /// The language the engine is currently set to speak, so [prepare] can skip re-setting it.
  String? _language;

  /// Whether [_language] found a voice. Distinct from [_available], which is about the engine
  /// existing at all: a device can have a working engine and no Tamil.
  bool _voiced = false;

  /// Whether a voice has been chosen at all yet. See [prepare].
  bool _selected = false;

  bool get isAvailable => _available;

  /// Language name, as `chat_languages` spells it, to the BCP-47 tags worth trying for it.
  ///
  /// Wider than the three languages shipped today, on purpose: the whole point of keeping the
  /// list in `app_config` is that adding Marathi is a dashboard edit, and a new language that
  /// silently lost its Listen button would make that promise only half true. These are the
  /// languages an Indian astrology app would plausibly add, and the tags Android and iOS use.
  ///
  /// A name that is not here gets no voice rather than the wrong one. An English engine reading
  /// Tamil aloud is not a degraded experience, it is noise — and the screens already treat "no
  /// voice" as "leave the control out", which reads as a design rather than as a fault.
  static const _locales = <String, List<String>>{
    // Roman-script Hindi. Spoken by the *English* voice deliberately: a hi-IN engine expects
    // Devanagari and stumbles over "Aapka Chandra", while an Indian English voice reads it
    // roughly the way the person who typed it would say it.
    'hinglish': ['en-IN', 'en-US'],
    'english': ['en-IN', 'en-US'],
    'hindi': ['hi-IN'],
    'tamil': ['ta-IN'],
    'telugu': ['te-IN'],
    'kannada': ['kn-IN'],
    'malayalam': ['ml-IN'],
    'marathi': ['mr-IN'],
    'bengali': ['bn-IN', 'bn-BD'],
    'gujarati': ['gu-IN'],
    'punjabi': ['pa-IN'],
    'odia': ['or-IN'],
    'assamese': ['as-IN'],
    'urdu': ['ur-IN', 'ur-PK'],
  };

  static List<String> _tagsFor(String? language) {
    final name = language?.trim().toLowerCase();
    if (name == null || name.isEmpty) return const ['en-IN', 'en-US'];
    return _locales[name] ?? const [];
  }

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

      // The scales differ by platform: 0.5 is ordinary on Android and noticeably fast on iOS.
      await _tts.setSpeechRate(Platform.isIOS ? 0.45 : 0.52);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);

      // Makes `speak` complete when the utterance finishes rather than when it starts, which
      // is what lets the chunks below run in sequence instead of talking over each other.
      await _tts.awaitSpeakCompletion(true);

      _available = true;
    } catch (error) {
      debugPrint('[reading] speech unavailable: $error');
      _available = false;
    }
  }

  /// True once the device is known to have a working engine **and a voice for [language]**.
  ///
  /// Called before the speak button is drawn, so the button can be left out entirely when it
  /// would do nothing. Readings and replies are written in the user's language now, so "the
  /// device has an engine" stopped being the whole question: a handset with no Tamil voice must
  /// not offer to read a Tamil reading aloud in English.
  Future<bool> prepare({String? language}) async {
    await _init();
    if (!_available) return false;

    // Setting a language is a platform call, and this runs on every reading open. `_selected`
    // rather than a null check on `_language`: null is itself a language here — "whatever the
    // default is" — so without it the very first call would return `_voiced` before choosing.
    if (_selected && _language == language) return _voiced;

    _selected = true;
    _language = language;
    _voiced = await _selectVoice(language);
    return _voiced;
  }

  /// Points the engine at the first tag the device actually has a voice for.
  Future<bool> _selectVoice(String? language) async {
    for (final tag in _tagsFor(language)) {
      try {
        if (await _tts.isLanguageAvailable(tag) != true) continue;
        await _tts.setLanguage(tag);
        return true;
      } catch (error) {
        debugPrint('[reading] could not select $tag: $error');
      }
    }

    debugPrint('[reading] no voice for ${language ?? 'the default'}; hiding the control');
    return false;
  }

  /// Speaks [text], stopping anything already playing.
  ///
  /// Returns when the whole thing has been read, or as soon as a later call cancels it, so a
  /// caller can await it to know when to drop its "speaking" flag.
  Future<void> speak(String text) async {
    await _init();
    // `_voiced` as well as `_available`: the screens hide the control when there is no voice for
    // the language, and this is the same rule for anything that reaches here another way.
    if (!_available || !_voiced) return;

    await stop();
    final generation = _generation;

    try {
      for (final chunk in _chunk(text)) {
        // A stop, or another speak, happened while the previous chunk was playing.
        if (generation != _generation) return;
        await _tts.speak(chunk);
      }
    } catch (error) {
      debugPrint('[reading] speech failed: $error');
    }
  }

  Future<void> stop() async {
    if (!_available) return;
    _generation++;
    try {
      await _tts.stop();
    } catch (error) {
      debugPrint('[reading] could not stop speech: $error');
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
