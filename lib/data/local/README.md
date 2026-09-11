# lib/data/local

## Purpose

On-device persistence for readings, chat threads and captured photographs — the caches that
make deep links survive a cold start.

## Files

- `reading_store.dart` — a generic cache over `shared_preferences`, with versioning, pruning
  and corrupt-payload handling in one place. Declares: `ReadingStore<T>` (abstract base:
  `storageKey`, `version`, `logTag`, `parse`, `encode`, `idOf`, plus `save`/`all`/`byId`),
  `PalmReadingStore`, `FaceReadingStore`, `ChatThreadStore` (also `load()`, `recent()`).
- `reading_image_store.dart` — the captured photographs, kept on the device and nowhere else.
  Declares: `ReadingImageStore`.

## Notes

- **This is what makes `/palm/reading/:id` and `/face/reading/:id` survive a cold start.** Those
  screens are routed to by id; without the cache, backgrounding the app on a detail screen would
  return to an empty one. It also makes a saved reading re-readable with no network.
- `shared_preferences`, not the secure store: a reading is personal but it is not a credential,
  and the Keychain is for things that are. The session token goes to
  [../supabase/session_store.dart](../supabase/session_store.dart) instead.
- Chat threads genuinely persist through the same base class, with their own key and
  `version: 2` — a v1 payload (one thread, fixed id, no verdicts) is dropped whole rather than
  half-parsed. Nothing is lost: `chat-history` brings the transcript back.
- `version` is bumped whenever a stored shape changes, so a build that adds a field cannot
  inherit a broken record from one that did not have it.
- The server never stores an image — it goes to the model and is dropped — so `ReadingImageStore`
  is the only copy that outlives the request.
