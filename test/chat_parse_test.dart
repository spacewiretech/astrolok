import 'package:astrolok/data/local/reading_store.dart';
import 'package:astrolok/data/models/astro_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Parsing a turn, and caching a conversation.
///
/// The server normalises before it stores, so most of what is guarded here is the *other*
/// direction: a row written by a newer server that knows about something this build does not.
/// The rule is the one every model in this app follows — degrade to less, never throw.

Map<String, dynamic> astroTurn([Map<String, dynamic> over = const {}]) => {
      'id': 'astro-1',
      'role': 'astro',
      'created_at': '2026-09-04T10:00:00Z',
      'title_emoji': '✨',
      'title': 'Your Love Reading',
      'opening': 'Your Chandra sits in Rohini.',
      'sections': [
        {'emoji': '❤️', 'heading': 'Relationship Energy', 'body': 'A steadier season.'},
        {'emoji': '💞', 'heading': 'Love Opportunities', 'body': 'Through people you know.'},
      ],
      'options': ['What of my career?'],
      'ask_for': 'none',
      ...over,
    };

Map<String, dynamic> userTurn([Map<String, dynamic> over = const {}]) => {
      'id': 'user-1',
      'role': 'user',
      'created_at': '2026-09-04T09:59:00Z',
      'text': 'I want to know about my love life.',
      ...over,
    };

void main() {
  group('AstroMessage.fromServer', () {
    test('parses an Astro turn', () {
      final message = AstroMessage.fromServer(astroTurn())!;

      expect(message.role, ChatRole.astro);
      expect(message.isUser, isFalse);
      expect(message.title, 'Your Love Reading');
      expect(message.titleEmoji, '✨');
      expect(message.text, 'Your Chandra sits in Rohini.');
      expect(message.sections, hasLength(2));
      expect(message.sections.first.heading, 'Relationship Energy');
      expect(message.options, ['What of my career?']);
      expect(message.askFor, AskFor.none);
    });

    test('parses a user turn, which carries its words under a different key', () {
      final message = AstroMessage.fromServer(userTurn())!;

      expect(message.role, ChatRole.user);
      expect(message.isUser, isTrue);
      expect(message.text, 'I want to know about my love life.');
      expect(message.sections, isEmpty);
    });

    test('a turn with nothing to show is null', () {
      // Both roles, since they read their body from different keys.
      expect(AstroMessage.fromServer(astroTurn({'opening': ''})), isNull);
      expect(AstroMessage.fromServer(userTurn({'text': '   '})), isNull);
    });

    test('a malformed payload is null rather than a throw', () {
      for (final raw in [null, 'not a map', 42, <String, dynamic>{}, []]) {
        expect(AstroMessage.fromServer(raw), isNull);
      }
    });

    test('ask_for is parsed, and an unknown value falls back to none', () {
      expect(AstroMessage.fromServer(astroTurn({'ask_for': 'birth_time'}))!.askFor,
          AskFor.birthTime);
      expect(AstroMessage.fromServer(astroTurn({'ask_for': 'birth_place'}))!.askFor,
          AskFor.birthPlace);
      // A control this build cannot raise must not be requested.
      expect(AstroMessage.fromServer(astroTurn({'ask_for': 'shoe_size'}))!.askFor,
          AskFor.none);
    });

    test('an unreadable role is treated as Astro, not as the user', () {
      // Attributing a message to the user puts words in their mouth; attributing one to Astro
      // merely looks odd. The safer guess is the one that cannot misrepresent someone.
      final message = AstroMessage.fromServer(astroTurn({'role': 'wizard'}))!;
      expect(message.role, ChatRole.astro);
    });

    test('a section missing a heading or a body is dropped, not half-rendered', () {
      final message = AstroMessage.fromServer(astroTurn({
        'sections': [
          {'emoji': '1', 'heading': 'Kept', 'body': 'yes'},
          {'emoji': '2', 'heading': '', 'body': 'no heading'},
          {'emoji': '3', 'heading': 'No body', 'body': ''},
          'not a map',
        ],
      }))!;

      expect(message.sections, hasLength(1));
      expect(message.sections.single.heading, 'Kept');
    });

    test('a section with no emoji still renders', () {
      final message = AstroMessage.fromServer(astroTurn({
        'sections': [
          {'heading': 'Plain', 'body': 'no emoji here'},
        ],
      }))!;

      expect(message.sections.single.emoji, '');
      expect(message.sections.single.heading, 'Plain');
    });

    test('a turn with no id still gets one, so a list can key on it', () {
      final message = AstroMessage.fromServer(astroTurn({'id': ''}))!;
      expect(message.id, isNotEmpty);
    });
  });

  group('the spoken form', () {
    test('reads the title, the opening and every section', () {
      final spoken = AstroMessage.fromServer(astroTurn())!.spoken;

      expect(spoken, contains('Your Love Reading'));
      expect(spoken, contains('Your Chandra sits in Rohini.'));
      expect(spoken, contains('Relationship Energy'));
      expect(spoken, contains('A steadier season.'));
    });

    test('leaves the emoji out, which a device voice would read aloud as a word', () {
      expect(AstroMessage.fromServer(astroTurn())!.spoken, isNot(contains('✨')));
    });
  });

  group('AstroFact', () {
    test('de-slugs its key into something a person can read', () {
      expect(const AstroFact(key: 'works_as', value: 'x').label, 'Works as');
      expect(const AstroFact(key: 'worries_about', value: 'x').label, 'Worries about');
      expect(const AstroFact(key: 'partner', value: 'x').label, 'Partner');
    });

    test('a fact with no key or no value is null', () {
      expect(AstroFact.fromServer({'key': '', 'value': 'x'}), isNull);
      expect(AstroFact.fromServer({'key': 'works_as', 'value': ''}), isNull);
      expect(AstroFact.fromServer('not a map'), isNull);
    });
  });

  group('ChatTopic', () {
    test('every pill sends a sentence in the first person', () {
      // The opener becomes the user's own bubble in the transcript, so "love" sitting in a navy
      // bubble would read as a machine talking.
      for (final topic in ChatTopic.values) {
        expect(topic.opener, isNotEmpty, reason: topic.name);
        expect(topic.opener.endsWith('.') || topic.opener.endsWith('?'), isTrue,
            reason: '${topic.name} is not a sentence');
        expect(topic.label, isNotEmpty);
      }
    });
  });

  group('the answer, before the reasoning', () {
    test('a verdict is parsed and round-trips through the cache', () {
      final message = AstroMessage.fromServer(
        astroTurn({'verdict': 'You were a keeper of records, near water.'}),
      )!;

      expect(message.verdict, 'You were a keeper of records, near water.');
      expect(
        AstroMessage.fromServer(message.toJson())!.verdict,
        'You were a keeper of records, near water.',
      );
    });

    test('a turn written before verdicts existed parses with an empty one', () {
      // Every Astro row already in the database is this case, and the bubble simply omits the
      // block rather than showing an empty card.
      expect(AstroMessage.fromServer(astroTurn())!.verdict, '');
    });

    test('the read-aloud answers first too', () {
      // Spoken, an answer that arrives after its own justification is worse than on the page —
      // a listener cannot skip ahead to find it.
      final message = AstroMessage.fromServer(
        astroTurn({'verdict': 'Patience, not courage.'}),
      )!;

      expect(message.spoken.startsWith('Patience, not courage.'), isTrue);
      // And the emoji still never reaches the voice, which would read it as "sparkles".
      expect(message.spoken.contains('✨'), isFalse);
    });
  });

  group('ChatThreadSummary', () {
    test('parses a row from the sidebar', () {
      final summary = ChatThreadSummary.fromServer({
        'id': 'thread-1',
        'title': 'Your Previous Birth',
        'preview': 'You were a keeper of records.',
        'last_message_at': '2026-09-04T10:00:00Z',
      })!;

      expect(summary.id, 'thread-1');
      expect(summary.title, 'Your Previous Birth');
      expect(summary.preview, 'You were a keeper of records.');
      expect(summary.lastMessageAt, isNotNull);
    });

    test('a row with no id is dropped rather than half-built', () {
      // It could not be opened, keyed or deleted — a row that does nothing when tapped is worse
      // than one that is not there.
      expect(ChatThreadSummary.fromServer({'title': 'Nameless'}), isNull);
      expect(ChatThreadSummary.fromServer('not a map'), isNull);
    });

    test('an untitled conversation parses rather than failing', () {
      // Real whenever a first reply never landed. The drawer shows a placeholder.
      expect(ChatThreadSummary.fromServer({'id': 'thread-1'})!.title, '');
    });
  });

  group('groupThreads', () {
    ChatThreadSummary at(DateTime? when, [String id = 'x']) =>
        ChatThreadSummary(id: id, title: 't', lastMessageAt: when);

    test('buckets by calendar day, not by elapsed hours', () {
      // Something said at 11pm belongs under "Yesterday" at 1am, not under "Today" because
      // twenty-three hours have not gone by.
      final now = DateTime(2026, 9, 7, 1);
      final grouped = groupThreads([at(DateTime(2026, 9, 6, 23))], now: now);

      expect(grouped.keys, [ChatAge.yesterday]);
    });

    test('sorts today, yesterday, the week and older into their own buckets', () {
      final now = DateTime(2026, 9, 7, 12);
      final grouped = groupThreads([
        at(DateTime(2026, 9, 7, 9), 'today'),
        at(DateTime(2026, 9, 6, 9), 'yesterday'),
        at(DateTime(2026, 9, 3, 9), 'week'),
        at(DateTime(2026, 8, 1, 9), 'older'),
      ], now: now);

      // In enum order, so the drawer never has to sort.
      expect(grouped.keys.toList(), ChatAge.values);
      expect(grouped[ChatAge.today]!.single.id, 'today');
      expect(grouped[ChatAge.yesterday]!.single.id, 'yesterday');
      expect(grouped[ChatAge.week]!.single.id, 'week');
      expect(grouped[ChatAge.older]!.single.id, 'older');
    });

    test('the seventh day is the last of the week bucket', () {
      final now = DateTime(2026, 9, 7, 12);
      final grouped = groupThreads([
        at(DateTime(2026, 9, 1, 12), 'six'),
        at(DateTime(2026, 8, 31, 12), 'seven'),
      ], now: now);

      expect(grouped[ChatAge.week]!.single.id, 'six');
      expect(grouped[ChatAge.older]!.single.id, 'seven');
    });

    test('a clock behind the server reads as today rather than as the future', () {
      final grouped = groupThreads(
        [at(DateTime(2026, 9, 8))],
        now: DateTime(2026, 9, 7, 12),
      );

      expect(grouped.keys, [ChatAge.today]);
    });

    test('an undated conversation goes last rather than first', () {
      // Almost always one cached before it reached the server; pinning it to the top would be a
      // lie about when it was last spoken to.
      final grouped = groupThreads([
        at(null, 'undated'),
        at(DateTime(2026, 9, 7, 9), 'today'),
      ], now: DateTime(2026, 9, 7, 12));

      expect(grouped[ChatAge.older]!.single.id, 'undated');
    });

    test('empty buckets are absent rather than empty', () {
      final grouped = groupThreads(
        [at(DateTime(2026, 9, 7, 9))],
        now: DateTime(2026, 9, 7, 12),
      );

      expect(grouped.keys, [ChatAge.today]);
    });

    test('nothing to group is an empty map, not a map of empty lists', () {
      expect(groupThreads(const [], now: DateTime(2026, 9, 7)), isEmpty);
    });
  });

  group('ChatThreadStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('round-trips a conversation', () async {
      const store = ChatThreadStore();
      final thread = ChatThread(
        id: 'thread-1',
        title: 'Your Love Reading',
        messages: [
          AstroMessage.fromServer(userTurn())!,
          AstroMessage.fromServer(astroTurn())!,
        ],
        remaining: 38,
      );

      await store.save(thread);
      final restored = await store.load('thread-1');

      expect(restored, isNotNull);
      expect(restored!.messages, hasLength(2));
      expect(restored.messages.first.isUser, isTrue);
      expect(restored.messages.last.sections, hasLength(2));
      expect(restored.messages.last.options, ['What of my career?']);
      expect(restored.remaining, 38);
    });

    test('saving a thread again replaces it rather than accumulating it', () async {
      // A conversation's whole transcript is one entry keyed on its id, so every turn overwrites
      // rather than piling a second copy of the same conversation into the cache.
      const store = ChatThreadStore();

      await store.save(ChatThread(
        id: 'thread-1',
        messages: [AstroMessage.fromServer(userTurn())!],
      ));
      await store.save(ChatThread(id: 'thread-1', messages: [
        AstroMessage.fromServer(userTurn())!,
        AstroMessage.fromServer(astroTurn())!,
      ]));

      expect(await store.all(), hasLength(1));
      expect((await store.load('thread-1'))!.messages, hasLength(2));
    });

    test('different conversations are kept side by side', () async {
      // The reason the cache is keyed per thread at all: opening one must not evict the other,
      // or the sidebar would paint a single row on every cold start.
      const store = ChatThreadStore();

      await store.save(ChatThread(
        id: 'thread-1',
        title: 'Your Love Reading',
        messages: [AstroMessage.fromServer(astroTurn())!],
      ));
      await store.save(ChatThread(
        id: 'thread-2',
        title: 'The Season Ahead',
        messages: [AstroMessage.fromServer(astroTurn())!],
      ));

      expect(await store.all(), hasLength(2));
      expect((await store.load('thread-1'))!.title, 'Your Love Reading');
      expect((await store.load('thread-2'))!.title, 'The Season Ahead');

      final listed = await store.recent();
      expect(listed.map((t) => t.id), containsAll(['thread-1', 'thread-2']));
    });

    test('a deleted conversation does not come back from the cache', () async {
      // Without this the drawer would repaint it on the next cold start, and the deletion would
      // read as having silently failed.
      const store = ChatThreadStore();

      await store.save(ChatThread(id: 'thread-1', messages: [
        AstroMessage.fromServer(astroTurn())!,
      ]));
      await store.remove('thread-1');

      expect(await store.load('thread-1'), isNull);
      expect(await store.recent(), isEmpty);
    });

    test('keeps its own key, so it cannot collide with the readings', () async {
      await const ChatThreadStore().save(ChatThread(
        id: 'thread-1',
        messages: [AstroMessage.fromServer(userTurn())!],
      ));

      expect(await const PalmReadingStore().all(), isEmpty);
      expect(await const FaceReadingStore().all(), isEmpty);
    });

    test('a corrupt cache reads as nothing rather than throwing', () async {
      SharedPreferences.setMockInitialValues({
        'astrolok.chat_thread': 'not json at all',
      });

      expect(await const ChatThreadStore().load('thread-1'), isNull);
    });

    test('a long conversation survives the round trip', () async {
      // The transcript is re-encoded whole on every turn, so this is the shape that would break
      // if the cache were ever keyed per message instead of per thread — the eleventh would go.
      const store = ChatThreadStore();
      final messages = [
        for (var i = 0; i < 60; i++)
          AstroMessage.fromServer(
            i.isEven ? userTurn({'id': 'u$i'}) : astroTurn({'id': 'a$i'}),
          )!,
      ];

      await store.save(ChatThread(id: 'thread-1', messages: messages));

      expect((await store.load('thread-1'))!.messages, hasLength(60));
    });
  });
}
