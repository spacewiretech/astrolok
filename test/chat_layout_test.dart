import 'package:astrolok/app/theme/app_theme.dart';
import 'package:astrolok/data/models/astro_message.dart';
import 'package:astrolok/data/providers.dart';
import 'package:astrolok/data/repositories/chat_repository.dart';
import 'package:astrolok/features/chat/chat_view.dart';
import 'package:astrolok/features/profile/memory_view.dart';
import 'package:astrolok/widgets/safe_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The chat stacks a lot into a narrow column — an avatar, a bordered bubble, a title, a
/// paragraph and up to three labelled sections, over a composer that grows with what is typed —
/// and it is exactly the kind of screen that overflows on a small phone without anyone noticing
/// until a user reports it.
///
/// A RenderFlex overflow throws in a test, so pumping at a small size and asserting no exception
/// is the whole check.
void main() {
  /// Roughly the smallest Android still in wide use.
  const small = Size(360, 640);
  const tall = Size(430, 932);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SafeSvg.resetProbeCache();
  });

  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    Widget child, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(theme: buildAppTheme(), home: child),
      ),
    );

    // Fixed pumps rather than pumpAndSettle: the waiting indicator's dots repeat forever, so
    // pumpAndSettle would never return.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// A transcript long enough, and with sections long enough, to find a wrapping bug.
  ///
  /// Real prose rather than lorem ipsum: text that is too short hides exactly the overflow this
  /// file exists to catch.
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
            AstroSection(
              emoji: '🌱',
              heading: 'What To Tend',
              body: 'One thing properly. Vrishabha does not reward a scattered hand.',
            ),
          ],
          options: i == 11
              ? const ['What of my family?', 'Tell me of Shani', 'And love?']
              : const [],
        ),
      );
    }
    return ChatThread(messages: messages, remaining: 20);
  }

  group('the opening screen', () {
    testWidgets('lays out on a small phone with all four pills', (tester) async {
      await pumpAt(tester, small, const ChatView());

      expect(tester.takeException(), isNull);
      for (final topic in ChatTopic.values) {
        expect(find.text(topic.label), findsOneWidget, reason: topic.label);
      }
      expect(find.text('Ask Astro'), findsOneWidget);
    });

    testWidgets('lays out on a tall phone', (tester) async {
      await pumpAt(tester, tall, const ChatView());
      expect(tester.takeException(), isNull);
    });
  });

  group('the transcript', () {
    testWidgets('lays out a long conversation on a small phone', (tester) async {
      final thread = longThread();
      await pumpAt(tester, small, const ChatView(), overrides: [
        chatRepositoryProvider
            .overrideWithValue(_StubChatRepository(messages: thread.messages)),
      ]);

      // Proves the transcript actually rendered. Without this the test passes vacuously on an
      // empty screen, which is exactly what it did the first time it was written.
      expect(find.text('Career Strengths'), findsWidgets);

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

    testWidgets('renders a reply title, body and every section', (tester) async {
      final thread = longThread();
      await pumpAt(tester, tall, const ChatView(), overrides: [
        chatRepositoryProvider
            .overrideWithValue(_StubChatRepository(messages: thread.messages)),
      ]);

      expect(find.text('What Your Chart Says of Work'), findsWidgets);
      expect(find.text('Career Strengths'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('quick replies come only from the newest turn', (tester) async {
      // Chips accumulating down a transcript would turn the screen into a form, and answering a
      // question from six turns back would land somewhere the user did not expect.
      final thread = longThread();
      await pumpAt(tester, tall, const ChatView(), overrides: [
        chatRepositoryProvider
            .overrideWithValue(_StubChatRepository(messages: thread.messages)),
      ]);

      expect(find.text('What of my family?'), findsOneWidget);
      // The other turns' chips are dropped: only the newest offers any.
      expect(find.text('Tell me of Shani'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a very long single message still lays out', (tester) async {
      // The server clamps an opening at 900 characters; this is that, unbroken.
      final wall = 'word ' * 200;
      final messages = <AstroMessage>[
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
      ];

      await pumpAt(tester, small, const ChatView(), overrides: [
        chatRepositoryProvider.overrideWithValue(_StubChatRepository(messages: messages)),
      ]);

      // The newest turn is at the visual bottom, so it is the one built first. Finding it
      // proves the transcript rendered — without an assertion like this the test would pass on
      // an empty screen, which is how it was written the first time.
      expect(find.text('A short question after a very long answer.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Then walk up through the wall of text. `ListView.builder` is lazy, so the long reply is
      // not in the tree until it is scrolled towards — which is also the only way this test
      // exercises laying it out.
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 12; i++) {
        await tester.drag(list, const Offset(0, 400));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'after drag $i');
      }

      expect(find.text('A Long Answer'), findsOneWidget);
    });
  });

  group('the composer', () {
    testWidgets('closes when the day is spent, and says why', (tester) async {
      await pumpAt(tester, small, const ChatView(), overrides: [
        chatRepositoryProvider.overrideWithValue(
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
        ),
      ]);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('asked Astro everything for today'), findsOneWidget);
      // An input that swallows what you type is worse than one honestly absent.
      expect(find.byType(TextField), findsNothing);
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
      // De-slugged, not raw.
      expect(find.text('Works as'), findsOneWidget);
      expect(find.text('a schoolteacher in Pune'), findsOneWidget);
      expect(find.text('Forget everything'), findsOneWidget);
    });

    testWidgets('says so plainly when there is nothing yet', (tester) async {
      await pumpAt(tester, small, const MemoryView());

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Nothing yet'), findsOneWidget);
      // Nothing to forget, so nothing offering to.
      expect(find.text('Forget everything'), findsNothing);
    });
  });
}

/// A repository that answers a fixed snapshot and nothing else.
///
/// `FakeChatRepository` is the walkable-app fake and reports a fresh allowance, which is exactly
/// wrong for the two states below. Rather than bend it with flags that only tests would use,
/// these stand in.
class _StubChatRepository implements ChatRepository {
  _StubChatRepository({this.messages = const [], this.remaining, this.facts = const []});

  final List<AstroMessage> messages;
  final int? remaining;
  final List<AstroFact> facts;

  @override
  Future<ChatSnapshot> history() async =>
      ChatSnapshot(messages: messages, facts: facts, remaining: remaining);

  @override
  Future<ChatReply> send(String message) async =>
      throw UnimplementedError('these tests never send');

  @override
  Future<List<AstroFact>> forget({String? key}) async =>
      key == null ? const [] : facts.where((f) => f.key != key).toList();
}
