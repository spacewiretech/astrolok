# lib/features/chat

## Purpose

The Astro conversation: one route, many threads, with a sidebar for switching between them.

## Files

- `chat_view.dart` — the screen: header, opening state, transcript. Declares: `ChatView`.
- `chat_viewmodel.dart` — one thread's turn-taking. Declares: `ChatViewModel` (an
  `AutoDisposeFamilyNotifier` keyed by thread id), `chatViewModelProvider`,
  `selectedThreadProvider` (`StateProvider<String>`, defaults to `ChatThread.draftId`).
- `chat_threads_viewmodel.dart` — the thread list behind the drawer. Declares:
  `ChatThreadsViewModel`, `chatThreadsProvider`.
- `chat_state.dart` — Declares: `ChatOutcome`, `ChatState`.
- `chat_copy.dart` — Declares: `ChatCopy`.
- `chat_composer.dart` — the input row, quick replies and the exhausted state. Declares:
  `ChatComposer`.
- `chat_drawer.dart` — the thread sidebar, with rename/delete. Declares: `ChatDrawer`.
- `chat_reveal.dart` — a staged typing animation over a non-streaming transport. Declares:
  `ChatReveal`, `RevealedPart`.

## Notes

- **The current thread is not in the URL.** `Routes.chat` is a single route; which thread is on
  screen lives in `selectedThreadProvider`, because an unsent draft has no server id yet.
- `chatThreadsProvider` is deliberately **not** `autoDispose` — the `endDrawer` unmounts when
  closed, and an auto-disposing provider would refetch the list every time it is opened.
- `chat_reveal.dart` exists because the transport is not streaming: the reply arrives whole and
  is revealed in stages, so it reads like typing without pretending to stream.
- This feature breaks the four-file convention with three extra widget files and a second
  viewmodel — the drawer and composer are large enough to own their own files.
- Backed by `astro-chat` (one metered turn) and `chat-history` (list, transcript, facts,
  rename/delete/forget). Gemini is never called from the device.
- Tests: `chat_layout_test.dart`, `chat_parse_test.dart`.
