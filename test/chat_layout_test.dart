import 'package:astrolok/app/theme/app_theme.dart';
import 'package:astrolok/data/language.dart';
import 'package:astrolok/data/models/astro_message.dart';
import 'package:astrolok/data/models/birth_place.dart';
import 'package:astrolok/data/providers.dart';
import 'package:astrolok/data/repositories/app_config_repository.dart';
import 'package:astrolok/data/repositories/chat_repository.dart';
import 'package:astrolok/data/repositories/place_repository.dart';
import 'package:astrolok/features/chat/chat_birth_time_sheet.dart';
import 'package:astrolok/features/chat/chat_bubble.dart';
import 'package:astrolok/features/chat/chat_composer.dart';
import 'package:astrolok/features/chat/chat_copy.dart';
import 'package:astrolok/features/chat/chat_greeting.dart';
import 'package:astrolok/features/chat/chat_rating.dart';
import 'package:astrolok/features/chat/chat_state.dart';
import 'package:astrolok/features/chat/chat_typing.dart';
import 'package:astrolok/features/chat/chat_view.dart';
import 'package:astrolok/features/chat/chat_viewmodel.dart';
import 'package:astrolok/features/profile/memory_view.dart';
import 'package:astrolok/widgets/date_wheel.dart';
import 'package:astrolok/widgets/place_search_field.dart';
import 'package:astrolok/widgets/primary_button.dart';
import 'package:astrolok/widgets/safe_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The WhatsApp-style chat: a column of bubbles, a typing indicator, reply buttons under the
/// newest message, and a composer that grows with what is typed — exactly the kind of screen that
/// overflows on a small phone without anyone noticing until a user reports it.
///
/// A RenderFlex overflow throws in a test, so pumping at a small size and asserting no exception
/// is most of each check. The rest pins down how a reply arrives: whole in the transcript, shown
/// one bubble at a time behind "typing…".
void main() {
  /// Roughly the smallest Android still in wide use.
  const small = Size(360, 640);
  const tall = Size(430, 932);

  /// Every screen below speaks Hinglish, so the greeting's words are known.
  final greeting = ChatGreeting.of('Hinglish');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SafeSvg.resetProbeCache();
  });

  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    Widget child, {
    List<Override> overrides = const [],
    bool instant = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          languageProvider.overrideWithValue('Hinglish'),
          // Bubbles all at once unless a test is about their pacing.
          if (instant) chatPacingProvider.overrideWithValue(const ChatPacing.instant()),
          ...overrides,
        ],
        child: MaterialApp(theme: buildAppTheme(), home: child),
      ),
    );

    // Fixed pumps rather than pumpAndSettle: the typing dots repeat forever, so pumpAndSettle
    // would never return.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Opens the screen on a real conversation rather than on an unsent one.
  ///
  /// A draft has nothing to fetch, so it never calls the repository and shows the greeting —
  /// correct, and it would make every transcript test below pass vacuously against an empty screen.
  List<Override> onThread(ChatRepository repository) => [
        chatRepositoryProvider.overrideWithValue(repository),
        selectedThreadProvider.overrideWith((_) => 'thread-1'),
      ];

  /// Opens the conversations drawer the way a person does: ⋮, then the menu item.
  Future<void> openDrawer(WidgetTester tester) async {
    await tester.tap(find.byTooltip(ChatCopy.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(ChatCopy.openConversations).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// A long v4-era conversation: every row already in the database looks like this.
  ChatThread longThread() {
    final messages = <AstroMessage>[];
    for (var i = 0; i < 12; i++) {
      messages.add(
        AstroMessage(
          id: 'u$i',
          role: ChatRole.user,
          createdAt: DateTime(2026, 9, 4, 10, i),
          text: 'I have been turning something over for a while now and I am not sure '
              'whether it is the work or the people around it that is wearing me down.',
        ),
      );
      messages.add(
        AstroMessage(
          id: 'a$i',
          role: ChatRole.astro,
          createdAt: DateTime(2026, 9, 4, 10, i, 30),
          titleEmoji: '✨',
          title: 'What Your Chart Says of Work',
          text: 'Your Chandra sits in Rohini, a nakshatra of steady attachment, and those born '
              'beneath it tend to stay in a difficult place long after the difficulty has '
              'made itself plain.',
          sections: const [
            AstroSection(
              emoji: '💼',
              heading: 'Career Strengths',
              body: 'Patience, and a tolerance for detail that other people give up on.',
            ),
            AstroSection(
              emoji: '📈',
              heading: 'Growth Ahead',
              body: 'A change in what is asked of you, rather than a change of place.',
            ),
          ],
          options: i == 11
              ? const ['What of my family?', 'Tell me of Shani', 'And love?']
              : const [],
        ),
      );
    }
    return ChatThread(id: 'thread-1', messages: messages, remaining: 20);
  }

  /// A v5 answer as they were written before the upay was folded into the answer: the answer, the
  /// reason, and the offer of today's upay, with the yes as the first button. The server no longer
  /// writes these, but every such row already stored must still be answerable.
  AstroMessage offer({String id = 'v5', DateTime? at}) => AstroMessage(
        id: id,
        role: ChatRole.astro,
        createdAt: at ?? DateTime(2026, 9, 25, 10),
        kind: ReplyKind.answer,
        topic: 'marriage',
        offersRemedy: true,
        bubbles: const [
          'Aapki kundali ke hisaab se 2027 ke middle se 2028 ke end tak shaadi ka sabse accha samay hai.',
          'Is time Shukra ki dasha chalegi, jo rishton ke liye shubh hai.',
          'Kya main aapko aaj ka upay bataun? 🙏',
        ],
        text: 'Is time Shukra ki dasha chalegi.',
        options: const ['Haan, upay batao 🙏', 'Jeevansathi kaisa hoga?'],
      );

  /// A v5 answer as the server writes it now: the answer, its reason, the upay with the invitation
  /// to come back, and a question about their situation — four messages, no offer, three
  /// follow-ups.
  AstroMessage arc({String id = 'arc', DateTime? at, AskFor askFor = AskFor.none}) => AstroMessage(
        id: id,
        role: ChatRole.astro,
        createdAt: at ?? DateTime(2026, 9, 28, 10),
        kind: ReplyKind.answer,
        topic: 'marriage',
        bubbles: const [
          'Aapki kundali ke hisaab se April se June 2027 mein rishta pakka hone ke sabse acche yog '
              'hain.',
          'Us samay Guru aapke saatve ghar se guzrega, aur wahan Shukra pehle se mazboot hai.',
          'Agle 4 hafte har Shukravar Maa Katyayani ka mantra 11 baar padhiye. Kal wapas aaiye, upay '
              'ka asar dekhte hain 🙏',
          'Ek baat bataiye — rishta ghar wale dhoond rahe hain ya aap khud?',
        ],
        askFor: askFor,
        options: const [
          'Ghar wale dhoond rahe hain',
          'Main khud dhoond raha hoon',
          'Jeevansathi kaisa hoga?',
        ],
      );

  group('the opening screen', () {
    testWidgets('greets, and offers the topics people ask about most, on a small phone',
        (tester) async {
      await pumpAt(tester, small, const ChatView());

      expect(tester.takeException(), isNull);
      // Anchored at the bottom, as a chat is: the greeting and every topic are what show first.
      expect(find.textContaining('Namaste'), findsOneWidget);
      for (final topic in greeting.topics) {
        expect(find.text(topic), findsOneWidget, reason: topic);
      }
      // The WhatsApp bar: who, and whether they are writing.
      expect(find.text(ChatCopy.astroName), findsOneWidget);
      expect(find.text(ChatCopy.online), findsOneWidget);
      expect(find.text(greeting.placeholder), findsOneWidget);

      // The privacy note sits at the very top, a scroll away on the smallest phone.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
      await tester.pump();
      expect(find.textContaining('private'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out on a tall phone', (tester) async {
      await pumpAt(tester, tall, const ChatView());
      expect(tester.takeException(), isNull);
    });

    testWidgets('a topic is sent as the person\'s own words, marked as a topic', (tester) async {
      final repository = _StubChatRepository();
      await pumpAt(tester, small, const ChatView(), overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
      ]);

      await tester.tap(find.text(greeting.topics.first));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(repository.sent, [greeting.topics.first]);
      expect(repository.entries, ['topic']);
    });
  });

  group('the transcript', () {
    testWidgets('lays out a long conversation on a small phone', (tester) async {
      await pumpAt(tester, small, const ChatView(),
          overrides: onThread(_StubChatRepository(messages: longThread().messages)));

      // Proves the transcript actually rendered, and that an old card became bubbles.
      expect(find.textContaining('Career Strengths'), findsWidgets);
      expect(tester.takeException(), isNull);

      // Walking the whole thing is the point: the overflow check applies at every scroll
      // position, not just the first screenful.
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 8; i++) {
        await tester.drag(list, const Offset(0, 260));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'after drag $i');
      }
    });

    testWidgets('an old card reads as a chat: the answer first, then its reasoning', (tester) async {
      await pumpAt(tester, small, const ChatView(), overrides: onThread(
        _StubChatRepository(
          messages: [
            AstroMessage(
              id: 'a',
              role: ChatRole.astro,
              createdAt: DateTime(2026, 9, 4),
              verdict: 'You were a keeper of records, near water.',
              titleEmoji: '🌙',
              title: 'Your Previous Birth',
              text: 'Your Chandra sits in Rohini, whose symbol is the cart.',
            ),
          ],
        ),
      ));

      expect(tester.takeException(), isNull);
      final answer = tester.getTopLeft(find.textContaining('keeper of records'));
      final reasoning = tester.getTopLeft(find.textContaining('whose symbol is the cart'));
      expect(answer.dy, lessThan(reasoning.dy));
      expect(find.byType(ChatBubble), findsNWidgets(2));
    });

    testWidgets('a reply written before verdicts existed still renders', (tester) async {
      await pumpAt(tester, small, const ChatView(), overrides: onThread(
        _StubChatRepository(
          messages: [
            AstroMessage(
              id: 'a',
              role: ChatRole.astro,
              createdAt: DateTime(2026, 9, 4),
              titleEmoji: '✨',
              title: 'The Season Ahead',
              text: 'Guru turns toward your tenth house.',
            ),
          ],
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('The Season Ahead'), findsOneWidget);
      expect(find.textContaining('Guru turns toward your tenth house.'), findsOneWidget);
    });

    testWidgets('a v5 reply is its bubbles, in order, one message each', (tester) async {
      await pumpAt(tester, small, const ChatView(),
          overrides: onThread(_StubChatRepository(messages: [offer()], remaining: 5)));

      expect(tester.takeException(), isNull);
      expect(find.byType(ChatBubble), findsNWidgets(3));
      final first = tester.getTopLeft(find.textContaining('shaadi ka sabse accha samay')).dy;
      final last = tester.getTopLeft(find.textContaining('aaj ka upay')).dy;
      expect(first, lessThan(last));
    });

    testWidgets('reply buttons come only from the newest turn, and send what they say',
        (tester) async {
      final repository = _StubChatRepository(messages: longThread().messages, remaining: 5);
      await pumpAt(tester, tall, const ChatView(), overrides: onThread(repository));

      expect(find.text('What of my family?'), findsOneWidget);
      expect(find.text('Tell me of Shani'), findsOneWidget);

      await tester.tap(find.text('What of my family?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.sent, ['What of my family?']);
      expect(repository.entries, ['quick_reply']);
    });

    testWidgets('a very long single message still lays out', (tester) async {
      final wall = 'word ' * 200;
      await pumpAt(tester, small, const ChatView(), overrides: onThread(
        _StubChatRepository(
          messages: [
            AstroMessage(
              id: 'a',
              role: ChatRole.astro,
              createdAt: DateTime(2026, 9, 4),
              title: 'A Long Answer',
              text: wall,
              sections: [AstroSection(heading: 'Also long', body: wall)],
            ),
            AstroMessage(
              id: 'u',
              role: ChatRole.user,
              createdAt: DateTime(2026, 9, 4),
              text: 'A short question after a very long answer.',
            ),
          ],
        ),
      ));

      expect(find.textContaining('A short question after a very long answer.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 12; i++) {
        await tester.drag(list, const Offset(0, 400));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'after drag $i');
      }
      expect(find.textContaining('A Long Answer'), findsOneWidget);
    });

    testWidgets('a care reply makes its helpline numbers tappable', (tester) async {
      await pumpAt(tester, small, const ChatView(), overrides: onThread(
        _StubChatRepository(
          messages: [
            AstroMessage(
              id: 'c',
              role: ChatRole.astro,
              createdAt: DateTime(2026, 9, 25),
              kind: ReplyKind.care,
              bubbles: const [
                'What you are feeling sounds really heavy.',
                'Please call Tele-MANAS on 14416 — free, 24 hours. iCall: 9152987821. '
                    'If you are in danger right now, call 112.',
              ],
            ),
          ],
          remaining: 5,
        ),
      ));

      expect(tester.takeException(), isNull);
      // Each number is its own tappable piece of text, announced as a call.
      for (final number in ['14416', '9152987821', '112']) {
        expect(find.text(number), findsOneWidget, reason: number);
      }
      expect(find.bySemanticsLabel('${ChatCopy.call} 14416'), findsOneWidget);
    });
  });

  group('how a reply arrives', () {
    /// Sends the first topic and returns once it has left the composer.
    Future<void> ask(WidgetTester tester) async {
      await tester.tap(find.text(greeting.topics.first));
      await tester.pump();
    }

    /// Runs out every pacing timer, so none is left pending when the test ends.
    Future<void> drain(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
    }

    testWidgets('a clock, then one grey tick, then blue ticks as Astro starts typing',
        (tester) async {
      final repository = _StubChatRepository(
        remaining: 5,
        delay: const Duration(seconds: 5),
        replyWith: (_, _) => offer(id: 'arriving', at: DateTime.now()),
      );
      await pumpAt(tester, small, const ChatView(),
          overrides: [chatRepositoryProvider.overrideWithValue(repository)], instant: false);
      await ask(tester);

      // Just sent: the clock, and Astro is only online.
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(find.byType(ChatTypingBubble), findsNothing);
      expect(find.text(ChatCopy.online), findsOneWidget);

      // Left the phone: one grey tick. Still not typing.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);
      expect(find.byType(ChatTypingBubble), findsNothing);

      // Read, and writing back — for the rest of the wait, not only its end.
      await tester.pump(const Duration(milliseconds: 650));
      expect(find.byIcon(Icons.done_rounded), findsNothing);
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(find.byType(ChatTypingBubble), findsOneWidget);
      expect(find.text(ChatCopy.typing), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(find.byType(ChatTypingBubble), findsOneWidget);

      await drain(tester);
    });

    testWidgets('about two seconds between messages, typing before each', (tester) async {
      final repository = _StubChatRepository(
        remaining: 5,
        delay: const Duration(seconds: 5),
        replyWith: (_, _) => offer(id: 'arriving', at: DateTime.now()),
      );
      await pumpAt(tester, small, const ChatView(),
          overrides: [chatRepositoryProvider.overrideWithValue(repository)], instant: false);
      await ask(tester);

      // Typed for the whole wait, so the first message shows the moment it lands.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.textContaining('shaadi ka sabse accha samay'), findsOneWidget);
      expect(find.textContaining('Shukra ki dasha'), findsNothing);
      expect(find.byType(ChatTypingBubble), findsOneWidget);
      expect(find.text('Haan, upay batao 🙏'), findsNothing);

      // Not before the shortest pause…
      await tester.pump(const Duration(milliseconds: 1700));
      expect(find.textContaining('Shukra ki dasha'), findsNothing);
      expect(find.text(ChatCopy.typing), findsOneWidget);
      // …and not after the longest.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.textContaining('Shukra ki dasha'), findsOneWidget);
      expect(find.textContaining('aaj ka upay'), findsNothing);
      expect(find.byType(ChatTypingBubble), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2700));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('aaj ka upay'), findsOneWidget);
      expect(find.byType(ChatTypingBubble), findsNothing);
      expect(find.text(ChatCopy.online), findsOneWidget);
      expect(find.text('Haan, upay batao 🙏'), findsOneWidget);
    });

    testWidgets('a reply that lands at once is still typed for a moment first', (tester) async {
      // A served upay comes back without a model call, in well under a second.
      final repository = _StubChatRepository(
        remaining: 5,
        delay: const Duration(milliseconds: 400),
        replyWith: (_, _) => offer(id: 'arriving', at: DateTime.now()),
      );
      await pumpAt(tester, small, const ChatView(),
          overrides: [chatRepositoryProvider.overrideWithValue(repository)], instant: false);
      await ask(tester);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      // In, and read — but not pasted in.
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(find.byType(ChatTypingBubble), findsOneWidget);
      expect(find.textContaining('shaadi ka sabse accha samay'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.textContaining('shaadi ka sabse accha samay'), findsOneWidget);
      expect(find.textContaining('Shukra ki dasha'), findsNothing);

      await drain(tester);
    });

    testWidgets('reduced motion keeps the pauses; only the dots hold still', (tester) async {
      final repository = _StubChatRepository(
        remaining: 5,
        delay: const Duration(seconds: 3),
        replyWith: (_, _) => offer(id: 'arriving', at: DateTime.now()),
      );
      await pumpAt(
        tester,
        small,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const ChatView(),
          ),
        ),
        overrides: [chatRepositoryProvider.overrideWithValue(repository)],
        instant: false,
      );
      await ask(tester);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('shaadi ka sabse accha samay'), findsOneWidget);
      expect(find.textContaining('aaj ka upay'), findsNothing);
      expect(find.byType(ChatTypingBubble), findsOneWidget);
      // Nothing left animating: the dots are still.
      expect(tester.binding.hasScheduledFrame, isFalse);

      await drain(tester);
      expect(find.textContaining('aaj ka upay'), findsOneWidget);
    });

    testWidgets('a touch on the conversation does not skip ahead', (tester) async {
      final repository = _StubChatRepository(
        remaining: 5,
        delay: const Duration(seconds: 3),
        replyWith: (_, _) => offer(id: 'arriving', at: DateTime.now()),
      );
      await pumpAt(tester, small, const ChatView(),
          overrides: [chatRepositoryProvider.overrideWithValue(repository)], instant: false);
      await ask(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      await tester.tap(find.textContaining('shaadi ka sabse accha samay'));
      await tester.pump();
      expect(find.textContaining('aaj ka upay'), findsNothing);
      expect(find.byType(ChatTypingBubble), findsOneWidget);

      await drain(tester);
    });

    testWidgets('sending again mid-delivery shows the rest of the last reply at once',
        (tester) async {
      final repository = _StubChatRepository(
        remaining: 5,
        delay: const Duration(seconds: 3),
        replyWith: (_, n) => n == 1
            ? offer(id: 'arriving', at: DateTime.now())
            : AstroMessage(
                id: 'second',
                role: ChatRole.astro,
                createdAt: DateTime.now(),
                bubbles: const ['Theek hai.'],
              ),
      );
      await pumpAt(tester, tall, const ChatView(),
          overrides: [chatRepositoryProvider.overrideWithValue(repository)], instant: false);
      await ask(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.textContaining('aaj ka upay'), findsNothing);

      await tester.enterText(find.byType(TextField), 'Aur career?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(find.textContaining('aaj ka upay'), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);

      await drain(tester);
    });

    testWidgets('a turn that fails leaves no ticks and no typing behind', (tester) async {
      await pumpAt(tester, small, const ChatView(),
          overrides: [chatRepositoryProvider.overrideWithValue(_FailingChatRepository())],
          instant: false);
      await ask(tester);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.byType(ChatTypingBubble), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.byType(ChatTypingBubble), findsNothing);
      expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      expect(find.text(ChatCopy.online), findsOneWidget);
      // Back in the composer, to send again.
      expect(find.widgetWithText(TextField, greeting.topics.first), findsOneWidget);

      await drain(tester);
    });

    testWidgets('switching conversations mid-delivery leaves nothing running', (tester) async {
      final repository = _StubChatRepository(
        remaining: 5,
        delay: const Duration(milliseconds: 400),
        replyWith: (_, _) => offer(id: 'arriving', at: DateTime.now()),
      );
      await pumpAt(tester, small, const ChatView(),
          overrides: [chatRepositoryProvider.overrideWithValue(repository)], instant: false);
      await ask(tester);
      // Landed, and held behind "typing…".
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(ChatTypingBubble), findsOneWidget);

      final container = ProviderScope.containerOf(tester.element(find.byType(ChatView)));
      container.read(selectedThreadProvider.notifier).state = 'thread-2';
      await tester.pump();
      await tester.pump();
      expect(container.exists(chatViewModelProvider(ChatThread.draftId)), isFalse);
      expect(find.byType(ChatTypingBubble), findsNothing);
      // No drain: a pacing timer the draft left behind would fail the test as still pending.
    });

    testWidgets('the yes to today\'s upay is the first button, and sends as a quick reply',
        (tester) async {
      final repository = _StubChatRepository(messages: [offer()], remaining: 5);
      await pumpAt(tester, small, const ChatView(), overrides: onThread(repository));

      final yes = find.text('Haan, upay batao 🙏');
      final other = find.text('Jeevansathi kaisa hoga?');
      expect(tester.getTopLeft(yes).dy, lessThan(tester.getTopLeft(other).dy));

      await tester.tap(yes);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.sent, ['Haan, upay batao 🙏']);
    });

    testWidgets('an offer from before still serves its upay, and the card follows the upay',
        (tester) async {
      final repository = _StubChatRepository(
        messages: [offer()],
        remaining: 5,
        askRating: true,
        replyWith: (_, _) => AstroMessage(
          id: 'remedy',
          role: ChatRole.astro,
          createdAt: DateTime.now(),
          kind: ReplyKind.remedy,
          topic: 'marriage',
          bubbles: const [
            'Agle 4 hafte har Shukravar Maa Katyayani ka mantra 11 baar padhiye.',
            'Kal wapas aaiye, upay ka asar dekhte hain.',
            'Ek baat bataiye — rishta ghar wale dhoond rahe hain ya aap khud?',
          ],
          options: const ['Ghar wale dhoond rahe hain', 'Main khud dhoond raha hoon'],
        ),
      );
      await pumpAt(tester, small, const ChatView(), overrides: onThread(repository));
      // Not over the offer: it is still waiting for its answer.
      expect(find.byType(ChatRatingCard), findsNothing);

      await tester.tap(find.text('Haan, upay batao 🙏'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(repository.entries, ['quick_reply']);
      expect(find.textContaining('Maa Katyayani'), findsOneWidget);
      // The yes is spent: the old offer's buttons are gone, the upay's own are up.
      expect(find.text('Haan, upay batao 🙏'), findsNothing);
      expect(find.text('Ghar wale dhoond rahe hain'), findsOneWidget);
      expect(find.byType(ChatRatingCard), findsOneWidget);
    });

    testWidgets('four messages arrive in order, and the buttons and the card wait for the last',
        (tester) async {
      final repository = _StubChatRepository(
        remaining: 5,
        delay: const Duration(seconds: 3),
        askRating: true,
        replyWith: (_, _) => arc(id: 'arriving', at: DateTime.now()),
      );
      await pumpAt(tester, small, const ChatView(),
          overrides: [chatRepositoryProvider.overrideWithValue(repository)], instant: false);
      await ask(tester);

      final bubbles = arc().bubbles;
      Finder bubble(int i) => find.textContaining(bubbles[i]);

      // Typed for the whole wait, so the answer shows the moment it lands.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(bubble(0), findsOneWidget);

      for (var i = 1; i < bubbles.length; i++) {
        // Still typing the next one: nothing to answer with, and nothing to rate, yet.
        expect(bubble(i), findsNothing, reason: 'message $i before its pause');
        expect(find.byType(ChatTypingBubble), findsOneWidget, reason: 'typing before $i');
        expect(find.text('Jeevansathi kaisa hoga?'), findsNothing, reason: 'buttons before $i');
        expect(find.byType(ChatRatingCard), findsNothing, reason: 'card before $i');

        // About two seconds after the one before: never before the shortest pause, never after
        // the longest. Stepped, because each pause runs from when the last message showed.
        var waited = 0;
        while (bubble(i).evaluate().isEmpty && waited < 4000) {
          await tester.pump(const Duration(milliseconds: 100));
          waited += 100;
        }
        expect(waited, inInclusiveRange(1800, 2700), reason: 'the pause before message $i');
        // Under the one before it: the answer, the reason, the upay, the question. Checked as each
        // lands, since on a small phone the first has scrolled away by the time the last is in.
        expect(
          tester.getTopLeft(bubble(i)).dy,
          greaterThan(tester.getTopLeft(bubble(i - 1)).dy),
          reason: 'message $i is below message ${i - 1}',
        );
      }

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ChatTypingBubble), findsNothing);
      expect(find.text('Jeevansathi kaisa hoga?'), findsOneWidget);
      expect(find.byType(ChatRatingCard), findsOneWidget);
    });

    for (final (label, size) in [('a small phone', small), ('a tall phone', tall)]) {
      testWidgets('four messages, a place button, three follow-ups and the card fit $label',
          (tester) async {
        final repository = _StubChatRepository(
          messages: [
            AstroMessage(
              id: 'u',
              role: ChatRole.user,
              createdAt: DateTime(2026, 9, 28, 9),
              text: 'Meri shaadi kab hogi?',
            ),
            arc(id: 'earlier', askFor: AskFor.birthTime),
          ],
          remaining: 5,
          askRating: true,
          replyWith: (_, _) => arc(id: 'arriving', at: DateTime.now(), askFor: AskFor.birthPlace),
        );
        await pumpAt(tester, size, const ChatView(), overrides: onThread(repository));

        await tester.tap(find.text(greeting.dontKnow));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
        expect(find.byType(ChatRatingCard), findsOneWidget);
        for (final label in [greeting.pickPlace, ...arc().options]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }

        final list = find.byType(Scrollable).first;
        for (var i = 0; i < 6; i++) {
          await tester.drag(list, const Offset(0, 240));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'after drag $i');
        }
      });
    }
  });

  group('starting a new conversation', () {
    /// ⋮, then "New chat" — the way a person does it.
    Future<void> newChat(WidgetTester tester) async {
      await tester.tap(find.byTooltip(ChatCopy.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(ChatCopy.newChat).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// A reply that says which message it answers, in words its question does not contain.
    AstroMessage answerTo(String message) => AstroMessage(
          id: 'reply-to-$message',
          role: ChatRole.astro,
          createdAt: DateTime.now(),
          kind: ReplyKind.answer,
          bubbles: ['Astro answers ${message.toUpperCase()}'],
        );

    testWidgets('a reply still in flight stays out of the chat started after it', (tester) async {
      final repository = _StubChatRepository(
        remaining: 5,
        delay: const Duration(seconds: 3),
        replyWith: (message, _) => answerTo(message),
      );
      await pumpAt(tester, small, const ChatView(),
          overrides: [chatRepositoryProvider.overrideWithValue(repository)]);
      final container = ProviderScope.containerOf(tester.element(find.byType(ChatView)));
      final first = greeting.topics.first;
      final second = greeting.topics[4];

      await tester.tap(find.text(first));
      await tester.pump(const Duration(seconds: 1));
      await newChat(tester);
      expect(find.text(first), findsOneWidget, reason: 'the greeting, with its topics');

      // A question in the new chat, and the old reply lands while it is in flight.
      await tester.tap(find.text(second));
      await tester.pump(const Duration(milliseconds: 1500));
      var state = container.read(chatViewModelProvider(ChatThread.draftId));
      expect(state.sending, isTrue, reason: 'the old reply ended the new turn');
      expect(state.messages.map((m) => m.text), [second]);
      expect(state.threadId, isNull, reason: 'the new chat took the old thread');

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      state = container.read(chatViewModelProvider(ChatThread.draftId));
      expect(state.messages.map((m) => m.id).last, 'reply-to-$second');
      expect(find.textContaining('Astro answers ${first.toUpperCase()}'), findsNothing);
      expect(find.textContaining('Astro answers ${second.toUpperCase()}'), findsOneWidget);
    });

    for (final autoSend in [true, false]) {
      testWidgets(
          'a question arriving from ${autoSend ? 'a reading' : 'a push'} is kept while an old '
          'conversation is still selected', (tester) async {
        const question = 'Meri shaadi kab hogi?';
        final repository = _StubChatRepository(
          remaining: 5,
          replyWith: (message, _) => answerTo(message),
        );
        await pumpAt(
          tester,
          small,
          ChatView(launch: ChatLaunch(question: question, source: 'palm', autoSend: autoSend)),
          overrides: onThread(repository),
        );

        if (autoSend) {
          // Sent once, from the new chat — and shown there, with its answer.
          expect(repository.sent, [question]);
          expect(find.textContaining(question), findsOneWidget);
          expect(find.textContaining('Astro answers ${question.toUpperCase()}'), findsOneWidget);
        } else {
          expect(repository.sent, isEmpty);
          expect(find.widgetWithText(TextField, question), findsOneWidget);
        }
      });
    }
  });

  group('the conversations drawer', () {
    final threads = [
      ChatThreadSummary(
        id: 'thread-1',
        title: 'Your Previous Birth',
        preview: 'You were a keeper of records, near water.',
        lastMessageAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      ChatThreadSummary(
        id: 'thread-2',
        title: 'What Your Chart Says Of Work',
        preview: 'Stay where you are a while longer.',
        lastMessageAt: DateTime.now().subtract(const Duration(days: 4)),
      ),
    ];

    for (final (label, size) in [('a small phone', small), ('a tall phone', tall)]) {
      testWidgets('lists every conversation under its heading on $label', (tester) async {
        await pumpAt(tester, size, const ChatView(), overrides: onThread(
          _StubChatRepository(threadList: threads),
        ));

        await openDrawer(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('New chat'), findsOneWidget);
        expect(find.text('Your Previous Birth'), findsOneWidget);
        expect(find.text('What Your Chart Says Of Work'), findsOneWidget);
        expect(find.text('Previous 7 days'), findsOneWidget);
        expect(find.text('What Astro remembers'), findsOneWidget);
      });
    }

    testWidgets('opens on the list it already has, without fetching again', (tester) async {
      final repository = _StubChatRepository(threadList: threads);
      await pumpAt(tester, small, const ChatView(), overrides: onThread(repository));

      Future<void> closeDrawer() async {
        await tester.tapAt(const Offset(8, 300));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      await openDrawer(tester);
      expect(find.text('Your Previous Birth'), findsOneWidget);

      await closeDrawer();
      expect(find.text('New chat'), findsNothing);

      await openDrawer(tester);
      expect(find.text('Your Previous Birth'), findsOneWidget);

      // Once, on arrival at the chat — not once per open.
      expect(repository.threadCalls, 1);
    });

    testWidgets('a conversation deleted elsewhere opens a new one', (tester) async {
      await pumpAt(tester, small, const ChatView(), overrides: onThread(_GoneChatRepository()));

      expect(tester.takeException(), isNull);
      // Landed on the greeting rather than an empty transcript.
      expect(find.text(greeting.topics.first), findsOneWidget);
    });
  });

  group('the composer', () {
    testWidgets('closes when the day is spent, says why, and keeps a helpline', (tester) async {
      await pumpAt(tester, small, const ChatView(), overrides: onThread(
        _StubChatRepository(
          remaining: 0,
          messages: [
            AstroMessage(
              id: 'a',
              role: ChatRole.astro,
              createdAt: DateTime(2026, 9, 4),
              text: 'The last answer of the day.',
            ),
          ],
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('asked Astro everything for today'), findsOneWidget);
      expect(find.textContaining('14416'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('the hint follows what Astro is waiting for', (tester) async {
      await pumpAt(tester, small, const ChatView(), overrides: onThread(
        _StubChatRepository(
          remaining: 5,
          messages: [
            AstroMessage(
              id: 'a',
              role: ChatRole.astro,
              createdAt: DateTime(2026, 9, 25),
              kind: ReplyKind.ask,
              bubbles: const ['Sahi janm tithi likhiye, jaise 15 August 1998.'],
              askFor: AskFor.dob,
            ),
          ],
        ),
      ));

      expect(find.text(greeting.dobHint), findsOneWidget);
    });
  });

  group('the rating card', () {
    const hint = 'Your thoughts (optional)';

    Future<void> pumpComposer(
      WidgetTester tester,
      ChatState state,
      void Function(int? rating, String? comment) onRate, {
      bool screen = false,
    }) async {
      tester.view.physicalSize = small;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final composer = ChatComposer(
        state: state,
        greeting: greeting,
        onSend: (message, entry) {},
        onDraftRestored: () {},
        onRate: onRate,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: screen
                ? Column(
                    children: [
                      const SizedBox(height: 60),
                      const Expanded(child: SizedBox.expand()),
                      composer,
                    ],
                  )
                : Align(alignment: Alignment.bottomCenter, child: composer),
          ),
        ),
      );
      await tester.pump();
    }

    ChatState due({
      String? revealingId,
      bool sending = false,
      AstroMessage? last,
    }) =>
        ChatState(
          loading: false,
          threadId: 'thread-1',
          ratingDue: true,
          revealingId: revealingId,
          sending: sending,
          messages: [
            last ??
                AstroMessage(
                  id: 'a',
                  role: ChatRole.astro,
                  createdAt: DateTime(2026, 9, 4),
                  text: 'An answer.',
                ),
          ],
        );

    VoidCallback? submit(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed;

    testWidgets('asks with five faces and a place to write on a small phone', (tester) async {
      await pumpComposer(tester, due(), (_, _) {});

      expect(tester.takeException(), isNull);
      expect(find.text('How is your chat with Astro so far?'), findsOneWidget);
      for (final face in ChatRatingCard.faces) {
        expect(find.text(face), findsOneWidget);
      }
      expect(find.widgetWithText(TextField, hint), findsOneWidget);
    });

    testWidgets('waits for the reply to finish arriving', (tester) async {
      await pumpComposer(tester, due(revealingId: 'a'), (_, _) {});
      expect(find.byType(ChatRatingCard), findsNothing);
    });

    testWidgets('never over an offer still waiting, and never under a care reply', (tester) async {
      await pumpComposer(tester, due(last: offer()), (_, _) {});
      expect(find.byType(ChatRatingCard), findsNothing);

      await pumpComposer(
        tester,
        due(
          last: AstroMessage(
            id: 'c',
            role: ChatRole.astro,
            createdAt: DateTime(2026, 9, 25),
            kind: ReplyKind.care,
            bubbles: const ['Tele-MANAS 14416.'],
          ),
        ),
        (_, _) {},
      );
      expect(find.byType(ChatRatingCard), findsNothing);
    });

    testWidgets('a face only chooses: nothing is sent until Submit', (tester) async {
      var calls = 0;
      await pumpComposer(tester, due(), (_, _) => calls++);

      expect(submit(tester), isNull);
      await tester.tap(find.text('🙂'));
      await tester.pump();

      expect(calls, 0);
      expect(find.textContaining('Thank you'), findsNothing);
      expect(submit(tester), isNotNull);
    });

    testWidgets('Submit sends the face and what was written, then says thank you', (tester) async {
      int? rating;
      String? comment;
      await pumpComposer(tester, due(), (r, c) {
        rating = r;
        comment = c;
      });

      await tester.tap(find.text('🙂'));
      await tester.enterText(find.widgetWithText(TextField, hint), 'Very accurate about my career');
      await tester.tap(find.text('Submit'));
      await tester.pump();

      expect(rating, 4);
      expect(comment, 'Very accurate about my career');
      expect(find.textContaining('Thank you'), findsOneWidget);

      // Past the thank-you, so its timer is not left running when the test ends.
      await tester.pump(const Duration(milliseconds: 1700));
    });

    testWidgets('the close button dismisses without a score, a comment or a thank-you',
        (tester) async {
      int? rating = -1;
      String? comment = 'unset';
      await pumpComposer(tester, due(), (r, c) {
        rating = r;
        comment = c;
      });

      await tester.enterText(find.widgetWithText(TextField, hint), 'half a thought');
      await tester.tap(find.byTooltip('Not now'));
      await tester.pump();

      expect(rating, isNull);
      expect(comment, isNull);
      expect(find.textContaining('Thank you'), findsNothing);
    });

    testWidgets('fits a small phone with the keyboard up', (tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await pumpComposer(tester, due(), (_, _) {}, screen: true);

      expect(tester.takeException(), isNull);
      expect(find.byType(ChatRatingCard), findsOneWidget);
    });
  });

  group('asking for the birth time', () {
    AstroMessage asking({String id = 'a', AskFor askFor = AskFor.birthTime}) => AstroMessage(
          id: id,
          role: ChatRole.astro,
          createdAt: DateTime(2026, 9, 25),
          kind: ReplyKind.ask,
          bubbles: const [
            'Aap kis samay paida hue the? Jaise subah 7:30 ya raat 10 baje — isse main aur pakka '
                'bata sakta hoon.',
          ],
          askFor: askFor,
        );

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text(greeting.pickTime));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('the ask is answered right under it: pick a time, or say you do not know',
        (tester) async {
      final repository = _StubChatRepository(messages: [asking()], remaining: 5);
      await pumpAt(tester, small, const ChatView(), overrides: onThread(repository));

      expect(tester.takeException(), isNull);
      expect(find.text(greeting.pickTime), findsOneWidget);
      expect(find.text(greeting.timeHint), findsOneWidget);

      await tester.tap(find.text(greeting.dontKnow));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.sent, [greeting.dontKnow]);
      expect(repository.entries, ['birth_time']);
    });

    testWidgets('an older reply that asked keeps no buttons', (tester) async {
      await pumpAt(tester, small, const ChatView(), overrides: onThread(
        _StubChatRepository(
          remaining: 5,
          messages: [
            asking(),
            AstroMessage(
              id: 'u',
              role: ChatRole.user,
              createdAt: DateTime(2026, 9, 25, 1),
              text: 'I was born at 6:45 PM.',
            ),
            asking(id: 'b', askFor: AskFor.none),
          ],
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(find.text(greeting.pickTime), findsNothing);
    });

    testWidgets('no buttons once the day is spent, when there is no way to answer', (tester) async {
      await pumpAt(tester, small, const ChatView(), overrides: onThread(
        _StubChatRepository(messages: [asking()], remaining: 0),
      ));

      expect(tester.takeException(), isNull);
      expect(find.text(greeting.pickTime), findsNothing);
    });

    testWidgets('the sheet sends no time until a part of the day is chosen', (tester) async {
      final repository = _StubChatRepository(messages: [asking()], remaining: 5);
      await pumpAt(tester, small, const ChatView(), overrides: onThread(repository));

      await openSheet(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(ChatCopy.timeSheetTitle), findsOneWidget);

      // No preset: the button names what is missing rather than offering a time nobody chose.
      expect(find.text(ChatCopy.timeSheetPickFirst), findsOneWidget);
      expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed, isNull);

      await tester.tap(find.text(ChatCopy.partEvening));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Confirm 4:00 PM'), findsOneWidget);

      await tester.tap(find.text('Confirm 4:00 PM'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(repository.sent, ['I was born at 4:00 PM.']);
      expect(repository.entries, ['birth_time']);
    });

    testWidgets('the wheels follow the chips, and the button follows the wheels', (tester) async {
      final repository = _StubChatRepository(messages: [asking()], remaining: 5);
      await pumpAt(tester, small, const ChatView(), overrides: onThread(repository));
      await openSheet(tester);

      Future<void> settle() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
      }

      await tester.ensureVisible(find.text(ChatCopy.partNight));
      await settle();

      await tester.tap(find.text(ChatCopy.partNight));
      await settle();
      expect(find.text('Confirm 8:00 PM'), findsOneWidget);

      await tester.tap(find.text(ChatCopy.partAfterMidnight));
      await settle();
      expect(tester.takeException(), isNull);
      expect(find.text('Confirm 12:00 AM'), findsOneWidget);

      await tester.drag(find.text('00'), const Offset(0, -DateWheel.itemExtent));
      await settle();
      expect(tester.takeException(), isNull);
      expect(find.text('Confirm 12:01 AM'), findsOneWidget);
    });

    testWidgets('"I don\'t know" in the sheet is an answer too', (tester) async {
      final repository = _StubChatRepository(messages: [asking()], remaining: 5);
      await pumpAt(tester, small, const ChatView(), overrides: onThread(repository));

      await openSheet(tester);
      await tester.tap(find.text(ChatCopy.timeSheetUnknown));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(repository.sent, [ChatCopy.birthTimeUnknown]);
    });

    test('a chosen time is always sent with morning or night', () {
      // The server reads a bare "11:55" as ambiguous and asks again.
      expect(birthTimeSentence(const TimeOfDay(hour: 0, minute: 5)), 'I was born at 12:05 AM.');
      expect(birthTimeSentence(const TimeOfDay(hour: 12, minute: 30)), 'I was born at 12:30 PM.');
      expect(birthTimeSentence(const TimeOfDay(hour: 23, minute: 55)), 'I was born at 11:55 PM.');
      expect(birthTimeSentence(const TimeOfDay(hour: 7, minute: 0)), 'I was born at 7:00 AM.');
    });
  });

  group('asking for the birth place', () {
    AstroMessage asking({String id = 'p', AskFor askFor = AskFor.birthPlace}) => AstroMessage(
          id: id,
          role: ChatRole.astro,
          createdAt: DateTime(2026, 9, 28),
          kind: ReplyKind.answer,
          bubbles: const [
            'Shukriya! 7:30 PM se dekha — March se August 2027 sabse mazboot mahine hain.',
            'Aapke saatve ghar par Guru ki nazar hai, jo accha rishta laati hai.',
            'Aapka janm kis shehar mein hua tha? Isse lagna pakka ho jayega.',
          ],
          askFor: askFor,
        );

    List<Override> withPlaces(_StubChatRepository chat, _StubPlaceRepository places) => [
          ...onThread(chat),
          placeRepositoryProvider.overrideWithValue(places),
        ];

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text(greeting.pickPlace));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Finder sheetField() =>
        find.descendant(of: find.byType(PlaceSearchField), matching: find.byType(TextField));

    /// Types into the sheet's field and waits out the debounce.
    Future<void> search(WidgetTester tester, String query) async {
      await tester.enterText(sheetField(), query);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    testWidgets('only a place ask raises the button, and the hint asks for a town',
        (tester) async {
      await pumpAt(tester, small, const ChatView(),
          overrides: onThread(_StubChatRepository(messages: [asking()], remaining: 5)));

      expect(tester.takeException(), isNull);
      expect(find.text(greeting.pickPlace), findsOneWidget);
      expect(find.text(greeting.placeHint), findsOneWidget);
      expect(find.text(greeting.pickTime), findsNothing);
    });

    for (final (label, messages) in [
      ('an hour ask', () => [asking(askFor: AskFor.birthTime)]),
      ('a reply that asks for nothing', () => [arc()]),
      (
        'an older reply that asked',
        () => [
              asking(),
              AstroMessage(
                id: 'u',
                role: ChatRole.user,
                createdAt: DateTime(2026, 9, 28, 1),
                text: 'Jaipur, Rajasthan',
              ),
              arc(id: 'b'),
            ],
      ),
    ]) {
      testWidgets('no place button under $label', (tester) async {
        await pumpAt(tester, small, const ChatView(),
            overrides: onThread(_StubChatRepository(messages: messages(), remaining: 5)));

        expect(tester.takeException(), isNull);
        expect(find.text(greeting.pickPlace), findsNothing);
      });
    }

    testWidgets('picking a place sends its words, and the row beside them', (tester) async {
      final chat = _StubChatRepository(messages: [asking()], remaining: 5);
      final places = _StubPlaceRepository();
      await pumpAt(tester, small, const ChatView(), overrides: withPlaces(chat, places));

      await openSheet(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(ChatCopy.placeSheetTitle), findsOneWidget);
      // The keyboard is up with the sheet: it exists only to ask this.
      expect(tester.widget<TextField>(sheetField()).focusNode!.hasFocus, isTrue);

      await search(tester, 'Jai');
      expect(find.text('Jaisalmer'), findsOneWidget);
      await tester.tap(find.text('Jaipur'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.text(ChatCopy.placeSheetTitle), findsNothing);
      expect(chat.sent, ['Jaipur, Rajasthan, India']);
      expect(chat.entries, ['birth_place']);
      // With the session its search ran in, so the server's lookup of the row closes it.
      expect(places.tokens, hasLength(1));
      expect(chat.places, [
        ChatBirthPlace(
          placeId: 'place-jaipur',
          description: 'Jaipur, Rajasthan, India',
          sessionToken: places.tokens.single,
        ),
      ]);
      // Their pick, in their own bubble.
      expect(find.textContaining('Jaipur, Rajasthan, India'), findsOneWidget);
      // One search, and no Details call: the server resolves the row it was sent.
      expect(places.queries, ['Jai']);
      expect(places.detailsCalls, 0);
    });

    testWidgets('typing the town still sends, with no row beside it', (tester) async {
      final chat = _StubChatRepository(messages: [asking()], remaining: 5);
      await pumpAt(tester, small, const ChatView(), overrides: onThread(chat));

      await tester.enterText(find.byType(TextField), 'Jaipur, Rajasthan');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(chat.sent, ['Jaipur, Rajasthan']);
      expect(chat.entries, ['composer']);
      expect(chat.places, [null]);
    });

    testWidgets('closing the sheet without a pick sends nothing', (tester) async {
      final chat = _StubChatRepository(messages: [asking()], remaining: 5);
      await pumpAt(tester, small, const ChatView(),
          overrides: withPlaces(chat, _StubPlaceRepository()));

      await openSheet(tester);
      await search(tester, 'Jai');
      // The barrier above the sheet.
      await tester.tapAt(const Offset(180, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(ChatCopy.placeSheetTitle), findsNothing);
      expect(chat.sent, isEmpty);
      // Still asked, so still answerable.
      expect(find.text(greeting.pickPlace), findsOneWidget);
    });

    testWidgets('with place search switched off there is no button, and typing is the way',
        (tester) async {
      await pumpAt(tester, small, const ChatView(), overrides: [
        ...onThread(_StubChatRepository(messages: [asking()], remaining: 5)),
        appConfigProvider.overrideWith(
          (ref) async => {...shippedAppConfig, placeSearchEnabledKey: 'false'},
        ),
      ]);

      expect(find.text(greeting.pickPlace), findsNothing);
      expect(find.text(greeting.placeHint), findsOneWidget);
    });

    testWidgets('the sheet fits a small phone with the keyboard up and the suggestions out',
        (tester) async {
      await pumpAt(tester, small, const ChatView(), overrides: withPlaces(
        _StubChatRepository(messages: [asking()], remaining: 5),
        _StubPlaceRepository(),
      ));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();

      await openSheet(tester);
      await search(tester, 'Jai');

      expect(tester.takeException(), isNull);
      expect(find.text('Jaunpur'), findsOneWidget);
      // Above the keyboard, not under it.
      expect(tester.getBottomLeft(sheetField()).dy, lessThan(small.height - 300));
    });
  });

  group('the chat\'s clock and calendar', () {
    test('a bubble\'s time is WhatsApp\'s: hour, minute, AM or PM', () {
      expect(formatBubbleTime(DateTime(2026, 9, 25, 0, 5)), '12:05 AM');
      expect(formatBubbleTime(DateTime(2026, 9, 25, 12, 30)), '12:30 PM');
      expect(formatBubbleTime(DateTime(2026, 9, 25, 19, 7)), '7:07 PM');
    });

    test('the day chip says today, yesterday, a weekday, then the date', () {
      final now = DateTime(2026, 9, 25, 9);
      expect(dayLabel(DateTime(2026, 9, 25, 1), now), ChatCopy.ageToday);
      expect(dayLabel(DateTime(2026, 9, 24, 23), now), ChatCopy.ageYesterday);
      expect(dayLabel(DateTime(2026, 9, 21), now), 'Monday');
      expect(dayLabel(DateTime(2026, 9, 4), now), '4 September 2026');
    });
  });

  group('what Astro remembers', () {
    testWidgets('lists the facts and offers a way out of each', (tester) async {
      await pumpAt(tester, small, const MemoryView(), overrides: [
        chatRepositoryProvider.overrideWithValue(
          _StubChatRepository(
            facts: const [
              AstroFact(key: 'works_as', value: 'a schoolteacher in Pune'),
              AstroFact(key: 'worries_about', value: 'her mother'),
            ],
          ),
        ),
      ]);

      expect(tester.takeException(), isNull);
      expect(find.text('Works as'), findsOneWidget);
      expect(find.text('a schoolteacher in Pune'), findsOneWidget);
      expect(find.text('Forget everything'), findsOneWidget);
    });

    testWidgets('says so plainly when there is nothing yet', (tester) async {
      await pumpAt(tester, small, const MemoryView(), overrides: [
        chatRepositoryProvider.overrideWithValue(_StubChatRepository()),
      ]);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Nothing yet'), findsOneWidget);
      expect(find.text('Forget everything'), findsNothing);
    });
  });
}

/// A repository whose sends fail two seconds in, after "typing…" has gone up.
class _FailingChatRepository extends _StubChatRepository {
  @override
  Future<ChatReply> send(
    String message, {
    String? threadId,
    String entry = 'composer',
    ChatBirthPlace? birthPlace,
  }) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    throw const ChatException('That did not reach Astro. Please try again.');
  }
}

/// A repository whose one conversation is gone, for the deleted-elsewhere path.
class _GoneChatRepository extends _StubChatRepository {
  @override
  Future<ChatSnapshot> history(String threadId) async =>
      throw const ChatThreadGoneException('That conversation is no longer here.');
}

/// A repository that answers a fixed snapshot, and a scripted reply to anything sent.
///
/// `FakeChatRepository` is the walkable-app fake and reports a fresh allowance, which is exactly
/// wrong for several states below. Rather than bend it with flags only tests would use, this
/// stands in.
class _StubChatRepository implements ChatRepository {
  _StubChatRepository({
    this.messages = const [],
    this.remaining,
    this.facts = const [],
    this.threadList = const [],
    this.delay = Duration.zero,
    this.replyWith,
    this.askRating = false,
  });

  final List<AstroMessage> messages;
  final int? remaining;
  final List<AstroFact> facts;
  final List<ChatThreadSummary> threadList;

  /// How long a send takes, for watching the typing indicator.
  final Duration delay;

  /// The reply to the nth message sent (1-based), when a test needs a particular one.
  final AstroMessage Function(String message, int n)? replyWith;

  /// Whether each reply asks for the rating card, as the server's `ask_rating` does.
  final bool askRating;

  /// How many times the sidebar has been asked for — proof it is not fetched on every open.
  int threadCalls = 0;

  /// Every message sent, oldest first, the affordance each came from, and the place picked beside
  /// it — null for anything that was not a pick.
  final sent = <String>[];
  final entries = <String>[];
  final places = <ChatBirthPlace?>[];

  @override
  Future<ChatSnapshot> history(String threadId) async =>
      ChatSnapshot(messages: messages, facts: facts, remaining: remaining);

  @override
  Future<ChatThreadList> threads() async {
    threadCalls++;
    return ChatThreadList(threads: threadList, facts: facts, remaining: remaining);
  }

  @override
  Future<ChatReply> send(
    String message, {
    String? threadId,
    String entry = 'composer',
    ChatBirthPlace? birthPlace,
  }) async {
    sent.add(message);
    entries.add(entry);
    places.add(birthPlace);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return ChatReply(
      threadId: threadId ?? 'thread-1',
      remaining: remaining,
      askRating: askRating,
      message: replyWith?.call(message, sent.length) ??
          AstroMessage(
            id: 'reply-${sent.length}',
            role: ChatRole.astro,
            createdAt: DateTime(2026, 9, 4),
            text: 'Then your Chandra rests in Rohini.',
          ),
    );
  }

  @override
  Future<ChatThreadList> renameThread(String id, String title) async => threads();

  @override
  Future<ChatThreadList> deleteThread(String id) async => threads();

  @override
  Future<List<AstroFact>> forget({String? key}) async =>
      key == null ? const [] : facts.where((f) => f.key != key).toList();

  @override
  Future<void> rate({required String threadId, int? rating, String? comment}) async {}
}

/// Place search with a fixed answer, counting what the chat asks of it.
///
/// Details is the call that costs a second lookup; the chat must never make it, so it is counted
/// here to be asserted zero.
class _StubPlaceRepository implements PlaceRepository {
  final queries = <String>[];
  final tokens = <String>{};
  int detailsCalls = 0;

  static const rows = [
    PlaceSuggestion(placeId: 'place-jaipur', primary: 'Jaipur', secondary: 'Rajasthan, India'),
    PlaceSuggestion(placeId: 'place-jaisalmer', primary: 'Jaisalmer', secondary: 'Rajasthan, India'),
    PlaceSuggestion(placeId: 'place-jaunpur', primary: 'Jaunpur', secondary: 'Uttar Pradesh, India'),
  ];

  @override
  Future<List<PlaceSuggestion>> autocomplete(String input, {required String sessionToken}) async {
    queries.add(input);
    tokens.add(sessionToken);
    return rows;
  }

  @override
  Future<BirthPlace> details(
    PlaceSuggestion suggestion, {
    required String sessionToken,
    DateTime? birthDate,
    String? birthTime,
  }) async {
    detailsCalls++;
    throw const PlaceUnavailableException('The chat never resolves a place itself.');
  }
}
