# lib/features/profile

## Purpose

The account area: the profile menu, saved readings, and what Astro remembers about the user.

## Files

- `profile_view.dart` — the menu screen: avatar, plan card, billing notice, menu rows.
  Declares: `ProfileView`. **No viewmodel** — it reads existing providers directly.
- `downloads_view.dart` — the saved readings list. Declares: `DownloadsView`.
- `downloads_viewmodel.dart` — Declares: `SavedReading`, `SavedReadingKind` (`palm`/`face`),
  `DownloadsViewModel`, `downloadsViewModelProvider`.
- `memory_view.dart` — the facts Astro has stored, each removable. Declares: `MemoryView`.
- `memory_viewmodel.dart` — Declares: `MemoryState`, `MemoryViewModel`, `memoryViewModelProvider`.

## Notes

- Three routes: `/profile`, `/profile/downloads`, `/profile/memory`.
- Downloads reads the **local** caches in [../../data/local/](../../data/local/), not the
  server — that is what lets a saved reading be re-opened with no network.
- Memory is the other way round: `AstroFact`s come from `chat-history`, and forgetting one is a
  `forget(key:)` call. This is the user-facing half of the chat's long-term memory.
- The plan card and billing notice are where cancellation lives (`subscription-cancel`).
- `profile_view.dart` adds the `/help` link that [../../website/](../../website/) serves.
- Sub-screen state classes live inside their viewmodel files; there are no `_state.dart` files
  here.
