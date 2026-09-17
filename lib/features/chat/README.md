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
- `chat_rating.dart` — the five-face rating card the composer raises, once per account. Declares:
  `ChatRatingCard`.
- `chat_birth_time_sheet.dart` — the sheet that asks for the hour of birth. Declares:
  `askBirthTime`, `birthTimeSentence`, `formatBirthClock`.

## Asking for what the sage lacks

When a reply's `ask_for` is `birth_time` or `birth_place`, the newest reply shows a note **directly
under its verdict** saying what Astro asked and why, with the button to answer. The question itself
is written at the foot of the reply, and a reader who stops at the answer never reaches it. The
button above the composer stays too, for the reader who does read to the end. Both open the same
sheet.

The sheet has **no preset time**. It replaced a clock dialog that opened on 9:00 AM without saying
what it wanted, and a large share of birth times arrived as exactly 9:00 AM. A promoted
`users.birth_time` is never overwritten, so each of those was a wrong nakshatra for good. The user
picks a part of the day before anything can be confirmed, and the button reads back the exact time
it will send. `Chat Birth Time Chosen.adjusted` says whether the wheels were moved after that.

## The transcript scrolls itself, in exactly two places

The list is `reverse: true` and sits at offset 0, so new turns are pinned to the bottom with no
arithmetic. That is right for everything except the moment a reply lands. `RevealedPart` fades
rather than grows, so a bubble is laid out at its **full height on the first frame** — and a
reply taller than the screen therefore hangs its verdict, title and opening above the top edge,
leaving the reader watching the blank lower half of a card that looks like it never arrived.

So `ChatReveal.onEntered` fires once per new reply and `_ChatViewState._bringReplyIntoView`
scrolls the *top* of the bubble to the top of the screen, plus enough offset to leave a line of
the question showing above it. The other is `_showTheWait`, which returns to the bottom when a
turn starts so someone who had scrolled up sees `_Thinking` appear.

Do not "fix" the full-height reservation by making the reveal grow the layout: a stable height is
what keeps the computed offset correct and stops the text reflowing under the reader mid-answer.

## Notes

- **The current thread is not in the URL.** `Routes.chat` is a single route; which thread is on
  screen lives in `selectedThreadProvider`, because an unsent draft has no server id yet.
- `chatThreadsProvider` is deliberately **not** `autoDispose` — the `endDrawer` unmounts when
  closed, and an auto-disposing provider would refetch the list every time it is opened.
- `chat_reveal.dart` exists because the transport is not streaming: the reply arrives whole and
  is revealed in stages, so it reads like typing without pretending to stream.
- This feature breaks the four-file convention with four extra widget files and a second
  viewmodel — the drawer, composer and rating card are large enough to own their own files.
- Backed by `astro-chat` (one metered turn) and `chat-history` (list, transcript, facts,
  rename/delete/forget/rate). Gemini is never called from the device.
- **The reply's language is not decided here.** It is `users.language`, set from Profile, and
  resolved server-side against `app_config.chat_languages`. A message in Devanagari, or one that
  asks for a language in words, switches it and the server saves the switch — see
  `_shared/chat_language.ts`. `ChatReply.savedLanguage` is how this screen hears about it, and
  `ChatViewModel` installs it through the entitlement store so Profile's picker and the listen
  voice follow.
- **The rating card is once per account, and the server decides when.** A reply carries
  `ask_rating`; `chatRatingDoneProvider` only covers a run in which saving the answer failed. The
  card lives in the composer rather than the transcript, for the scrolling reason in
  `chat_rating.dart`.
- Tests: `chat_layout_test.dart`, `chat_parse_test.dart`.
