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
