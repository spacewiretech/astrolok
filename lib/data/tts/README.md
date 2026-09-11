# lib/data/tts

## Purpose

Reading a result aloud, using the text-to-speech voice already on the device.

## Files

- `reading_speech.dart` — Declares: `ReadingSpeech` (`prepare`, `speak`, `stop`, `dispose`).

## Notes

- On-device rather than synthesised server-side: free, offline, and it starts speaking
  instantly, which matters for something a user replays.
- `prepare()` is what decides whether `SpeakButton`
  ([../../widgets/speak_button.dart](../../widgets/speak_button.dart)) renders at all — a device
  with no usable voice gets no dead button.
- Long text is chunked internally; some platforms truncate a single long utterance.
- Provided as `readingSpeechProvider` in [../providers.dart](../providers.dart).

## The voice follows the reading's language

`prepare({language})` no longer answers just "does this device have a speech engine" — it answers
"does it have a voice for *this* language". Readings and chat replies are written in whatever the
user set in Profile, and a handset with no Tamil voice must not offer to read a Tamil reading
aloud in English. That is noise, not a degraded experience.

- The name-to-BCP-47 map covers well beyond the three languages shipped, because adding one is a
  dashboard edit and a new language that silently lost its Listen button would make that promise
  only half true.
- **Hinglish is spoken by the English voice on purpose.** It is Hindi in Roman letters; a `hi-IN`
  engine expects Devanagari and stumbles over "Aapka Chandra", while an Indian English voice
  reads it roughly the way the person who typed it would say it.
- A language with no entry, or with no voice installed, returns false and the screens leave the
  control out — the file's existing rule that an absent control reads as a design and a dead one
  reads as a bug.
