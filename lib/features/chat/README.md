# lib/features/chat

## Purpose

The Astro conversation, as a WhatsApp chat: one route, many threads, with a drawer for switching
between them. Familiar on purpose — the green bar, the beige wallpaper, bubbles with tails, "typing…"
— so people are at ease before a word is read.

## Files

- `chat_view.dart` — the screen: bar, wallpaper, transcript rows (notice, day chips, bubbles, typing,
  reply buttons), composer. Declares: `ChatView`, `ChatLaunch`, `pendingChatLaunchProvider`.
- `chat_viewmodel.dart` — one thread's turn-taking and the bubble-by-bubble delivery. Declares:
  `ChatViewModel` (an `AutoDisposeFamilyNotifier` keyed by thread id), `chatViewModelProvider`,
  `selectedThreadProvider`, `chatRatingDoneProvider`, `ChatPacing`, `chatPacingProvider`.
- `chat_threads_viewmodel.dart` — the thread list behind the drawer. Declares:
  `ChatThreadsViewModel`, `chatThreadsProvider`.
- `chat_state.dart` — Declares: `ChatOutcome`, `SendStage`, `ChatState`.
- `chat_copy.dart` — Declares: `ChatCopy` (English UI words).
- `chat_greeting.dart` — what Astro says before anyone has, and the composer hints, in each chat
  language. Declares: `ChatGreeting`.
- `chat_palette.dart` — WhatsApp's colours, kept apart from `AppColors`. Declares: `ChatPalette`.
- `chat_app_bar.dart` — back, Astro's picture, "online" ↔ "typing…", the ⋮ menu. Declares:
  `ChatAppBar`, `ChatMenuAction`.
- `chat_wallpaper.dart` — the beige ground with faint sky doodles, drawn. Declares: `ChatWallpaper`.
- `chat_bubble.dart` — a message, the day chip, the yellow notice and the reply buttons. Declares:
  `ChatBubble`, `ChatBubbleShape`, `BubbleStatus`, `ChatDateChip`, `ChatNotice`,
  `ChatReplyButtons`, `chatTextStyle`, `formatBubbleTime`, `dayLabel`.
- `chat_typing.dart` — the bouncing dots. Declares: `ChatTypingBubble`.
- `chat_composer.dart` — the rating card and WhatsApp's field with its green send button. Declares:
  `ChatComposer`.
- `chat_drawer.dart` — the thread sidebar, with rename/delete. Declares: `ChatDrawer`.
- `chat_rating.dart` — the five-face rating card the composer raises, once per account. Declares:
  `ChatRatingCard`.
- `chat_birth_time_sheet.dart` — the careful birth-time picker (no preset time), opened from the
  "⏰" button under Astro's ask. Declares: `askBirthTime`, `birthTimeSentence`, `formatBirthClock`.
- `chat_birth_place_sheet.dart` — the kundali form's place search in a sheet, opened from the "📍"
  button under Astro's ask; hands back the picked row with its search session, as a
  `ChatBirthPlace`. Declares: `askBirthPlace`.

## How a reply arrives

The transport is not streaming, so the chat stages it the way a person sends messages:

1. While the request is in flight, WhatsApp's ticks on the message, on timers (`SendStage`) because
   the request says nothing until it is answered: a clock, one grey tick at 300 ms, then blue ticks
   at 900 ms with `ChatTypingBubble` in the transcript and "typing…" in the bar for the rest of the
   wait.
2. The reply lands whole — in the transcript, the cache and the drawer at once, and `Chat Reply
   Received` fires with the network time. Its first bubble shows once "typing…" has been up for
   1.5 s: at once after a normal wait, a moment later for one that came back faster (a served
   upay). One that lands before 900 ms turns the ticks blue and starts the typing there.
3. Each later bubble follows about two seconds on, behind "typing…" again (`ChatPacing`: 1.5 s +
   7 ms a character, 1.8–2.6 s), so a four-message answer takes about six seconds to finish
   arriving. Reply buttons — the ⏰/📍 ones included — and the rating card wait for the last one.

Staging is display-only — leaving the screen or switching threads mid-delivery loses nothing, it just
shows whole next time. It is conversation timing, not animation: reduced motion keeps it and only
stills the dots, and a touch on the transcript does not skip it. A new send shows the rest at once
(`finishDelivery`). A failed turn stops the ticks and the typing and hands its words back to the
composer. Tests override `chatPacingProvider` with `ChatPacing.instant()`.

## v5 and older replies

The app sends `chat_ui: 2` with every turn; only such a client is answered with prompt v5. A v5
answer is up to four bubbles, in order: the answer (with a time window for every "kab"), the
chart's reason, the upay with an invitation to come back — once Astro knows enough, usually the
third answer, and not again in the thread — and a question about their situation, which is where
the hour and the place of birth are asked for. The server decides all of it; the screen only
shows the bubbles in order. Older builds keep v4. `AstroMessage.displayBubbles` turns any
older card (verdict, title + opening, sections) into bubbles, so a conversation started before v5
reads as a chat too.

**Replies from before the upay was folded in** ended by offering it: `offer: "remedy"`, with "Haan,
upay batao 🙏" as the first reply button, served on a yes as a `remedy` turn without using a
question. New replies no longer offer, but those rows are in the database and cache, so the yes
still works and the rating card still holds back over an unanswered offer.

When Astro asks for the hour, "⏰ Samay chunein" opens the picker and "Pata nahi" answers; typing
the time works as well — the server reads it (`_shared/birth_details.ts`), saves it, and answers the
earlier question in the same turn. A saved detail comes back as `ChatReply.user`, installed the way
Profile's birth-time picker installs it.

When it asks for the place (`ask_for: "birth_place"`), "📍 Jagah chunein" opens the place search
(`place-search` autocomplete, the kundali form's `PlaceSearchField`). A pick is sent as the row's
description for the transcript, plus `birth_place: {place_id, description, session_token}` so the
server saves that exact place; entry `birth_place`. The app makes no Details call — the server
resolves the id, under the search's own session token, so Google bills the typing and the lookup
as one session the way it bills the kundali form's.
Typing the town works too (the hint says "Jaise: Jaipur, Rajasthan" in each language), and the
server looks the words up. With `place_search_enabled` off there is no button, only the hint. A
picked place whose turn fails comes back to the composer as words, and resending it is a typed
town.

The chat never makes or changes a kundali. The Kundali screens still ask for the details
themselves and still take their 24 hours; the only kundali row a chat turn touches is the existing
recast when someone corrects a date or hour of birth.

## Care replies

A message about wanting to die is answered by the server with fixed text and helplines, before any
model or paywall (`_shared/crisis.ts`); a v5 reply in which the model gave a helpline to words the
lists missed is marked `care` too. `ReplyKind.care` bubbles make 14416 / 9152987821 / 112
tappable to call, and the rating card never appears under one. The exhausted state keeps a
Tele-MANAS line, because the field is gone there.

## Notes

- **The current thread is not in the URL.** `Routes.chat` is a single route; which thread is on
  screen lives in `selectedThreadProvider`, because an unsent draft has no server id yet.
- **"New chat" rebuilds the draft in place.** `ref.invalidate` keeps the same `ChatViewModel`
  instance, so a turn in flight checks the build it started in (`_generation`), not `_disposed`:
  its reply stays in its own thread on the server instead of landing in the new chat. A question
  arriving from a reading or a push, with a drawer thread still selected, holds the draft alive
  (`listenManual`) until the screen watches it — otherwise it was disposed before the next frame
  with the question in it.
- `chatThreadsProvider` is deliberately **not** `autoDispose` — the `endDrawer` unmounts when
  closed, and an auto-disposing provider would refetch the list every time it is opened.
- The transcript is `reverse: true`, pinned at offset 0 as bubbles arrive. It scrolls itself only
  when a turn starts, and through the "↓" button for someone who scrolled up.
- **The reply's language is not decided here.** It is `users.language`, resolved server-side; a
  message in another script, or one that asks for a language, switches it and the server saves the
  switch — see `_shared/chat_language.ts`. `ChatReply.savedLanguage` is how this screen hears about
  it. The greeting and hints follow `languageProvider`.
- **The rating card is once per account, and the server decides when.** A reply carries
  `ask_rating`; the card lives in the composer rather than the transcript.
- This feature breaks the four-file convention with extra widget files and a second viewmodel —
  the bar, bubbles, composer, drawer and rating card are large enough to own their own files.
- Backed by `astro-chat` (one metered turn) and `chat-history` (list, transcript, facts,
  rename/delete/forget/rate). Gemini is never called from the device.
- Tests: `chat_layout_test.dart`, `chat_parse_test.dart`.
