import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// One sentence to speak, and how long to stay silent after it.
@immutable
class SpeechSegment {
  const SpeechSegment(this.text, this.pauseAfter);

  final String text;
  final Duration pauseAfter;

  @override
  bool operator ==(Object other) =>
      other is SpeechSegment && other.text == text && other.pauseAfter == pauseAfter;

  @override
  int get hashCode => Object.hash(text, pauseAfter);

  @override
  String toString() => 'SpeechSegment($text, ${pauseAfter.inMilliseconds}ms)';
}

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

  /// The breath after a sentence, and the longer rest between a reading's parts — verdict,
  /// opening, each section.
  ///
  /// Silence rather than a slower voice alone: counsel read without a pause is heard as a stream,
  /// and the listener needs a beat to take one line in before the next arrives. Spaces cannot do
  /// this — every engine collapses a run of whitespace to one.
  ///
  /// Short, because they add to the engine's own gap between utterances rather than replacing it:
  /// 350 and 800 ms, the first values tried, left the reading sounding halting.
  static const _sentencePause = Duration(milliseconds: 120);
  static const _paragraphPause = Duration(milliseconds: 350);

  /// The pause in progress, so [stop] can end it at once instead of leaving a cancelled [speak]
  /// to finish late — which would clear a "speaking" flag that a new playback has since set.
  Timer? _pauseTimer;
  Completer<void>? _pauseDone;

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

      // Unhurried on both, and the scales differ. On Android the plugin doubles the value before
      // the engine sees it, so 0.44 is 0.88× ordinary speech — 0.52 was slightly *faster* than
      // ordinary, and listeners said so. On iOS 0.5 is AVSpeech's default, so 0.40 is a calmer pace.
      await _tts.setSpeechRate(Platform.isIOS ? 0.40 : 0.44);
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
      for (final segment in segments(text)) {
        // A stop, or another speak, happened while the previous sentence was playing.
        if (generation != _generation) return;
        await _tts.speak(segment.text);

        if (generation != _generation) return;
        await _pause(segment.pauseAfter);
      }
    } catch (error) {
      debugPrint('[reading] speech failed: $error');
    }
  }

  Future<void> stop() async {
    if (!_available) return;
    _generation++;
    _endPause();
    try {
      await _tts.stop();
    } catch (error) {
      debugPrint('[reading] could not stop speech: $error');
    }
  }

  Future<void> _pause(Duration length) {
    if (length <= Duration.zero) return Future.value();

    final done = _pauseDone = Completer<void>();
    _pauseTimer = Timer(length, _endPause);
    return done.future;
  }

  void _endPause() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    final done = _pauseDone;
    _pauseDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  /// The text as sentences, each with the silence that follows it.
  ///
  /// Paragraphs are the parts every `spoken` getter joins with a blank line — a reply's verdict,
  /// title, opening and sections; a reading's invocation, trait and lines — and get the longer
  /// rest. Sentences within one get a breath. Nothing follows the last.
  ///
  /// One utterance per sentence, which also keeps each well inside what an Android engine will
  /// take in one call, and makes Stop land at once. The engine's own gap between utterances is
  /// uneven; the pause after it is what makes the rhythm deliberate rather than accidental.
  ///
  /// The danda ends a sentence too. Without it a Hindi reply in Devanagari is one long breathless
  /// utterance.
  @visibleForTesting
  static List<SpeechSegment> segments(String text) {
    final paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((paragraph) => paragraph
            .split(RegExp(r'(?<=[.!?।॥])\s+|\n+'))
            .map((sentence) => sentence.trim())
            .where((sentence) => sentence.isNotEmpty)
            .toList())
        .where((sentences) => sentences.isNotEmpty)
        .toList();

    return [
      for (final (p, sentences) in paragraphs.indexed)
        for (final (s, sentence) in sentences.indexed)
          SpeechSegment(
            sentence,
            s < sentences.length - 1
                ? _sentencePause
                : p < paragraphs.length - 1
                    ? _paragraphPause
                    : Duration.zero,
          ),
    ];
  }

  Future<void> dispose() => stop();
}
