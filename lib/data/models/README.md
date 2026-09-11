# lib/data/models

## Purpose

Plain domain types mirroring what the Edge Functions and the database return. No Flutter
imports, no repository knowledge — just parsing, ordering and the enums the screens switch on.

## Files

- `app_user.dart` — the account and its billing position. Declares: `PaymentType`,
  `BillingState`, `AppUser` (note `recomputeOffline([asOf])`).
- `astro_message.dart` — everything the chat feature reads. Declares: `ChatRole`, `AskFor`,
  `AstroSection`, `ChatTopic`, `AstroMessage`, `AstroFact`, `ChatThreadSummary`, `ChatAge`
  (`today`/`yesterday`/`week`/`older`), `ChatThread`.
- `palm_reading.dart` — Declares: `PalmLineKind`, `PalmLineStatus` (typedef → `ReadingStatus`),
  `PalmFocus`, `HandTraits`, `PalmTrait`, `PalmLine`, `PalmReading`.
- `face_reading.dart` — the face mirror of the above. Declares: `FacePartKind`, `FaceTraitKind`,
  `FaceObservations`, `FaceCoreTrait`, `FacePart`, `FaceReading`.
- `reading_status.dart` — the strength vocabulary shared by palm and face. Declares:
  `ReadingStatus`.
- `subscription_offer.dart` — Declares: `SubscriptionOffer` (what the paywall renders),
  `SubscriptionStart` (what `subscription-start` returns).
- `upi_app.dart` — one installed UPI app in the payment picker. Declares: `UpiApp`.

## Notes

- **`fromServer` degrades, it never throws.** Unknown or duplicated keys are dropped, ordering
  is imposed client-side, and a newer server payload renders as less rather than crashing an
  older build. `test/palm_reading_parse_test.dart`, `face_reading_parse_test.dart` and
  `chat_parse_test.dart` exist to keep that true.
- Display ordering lives in the enums here, not in the views — the model decides what order
  lines/parts appear in, so the results screen and the PDF export cannot disagree.
- `PalmFocus` is shared: `FaceRepository.read` also takes a `PalmFocus`, not a face-specific
  enum.
- **`AppUser.recomputeOffline()` is the one place the client derives entitlement itself.**
  `SessionStore` applies it to a restored session so a trial that ended overnight does not keep
  opening the app before the server has been asked. Covered by `test/entitlement_test.dart`.
- The server-side counterparts are `supabase/functions/_shared/palm_reading.ts`,
  `face_reading.ts` and `astro_chat.ts`, which normalise the model output before it ships.
