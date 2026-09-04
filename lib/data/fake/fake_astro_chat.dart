import '../models/astro_message.dart';
import '../repositories/chat_repository.dart';

/// A scripted sage, for the tier with no Supabase configured.
///
/// Two jobs, the same two the other fakes have. It keeps the app walkable end to end on a
/// checkout that has never been pointed at a project, and it makes the chat screen's timing and
/// layout observable while building it — otherwise impossible without a deployed function and a
/// real model call per turn.
///
/// The replies are written in the register the prompt asks for: a computed detail cited, a
/// hedged claim, a question back, and a nakshatra that is only named once a birth time is known.
/// A fake that answered in lorem ipsum would hide exactly the layout problems this exists to
/// surface — three sections of real prose wrap very differently from three short strings.
class FakeChatRepository implements ChatRepository {
  FakeChatRepository({this.latency = const Duration(milliseconds: 1400)});

  /// Roughly what a text turn really costs. Long enough to see the waiting state, short enough
  /// not to make development tedious.
  final Duration latency;

  final List<AstroMessage> _messages = [];
  final List<AstroFact> _facts = [];

  int _turn = 0;

  @override
  Future<ChatReply> send(String message) async {
    await Future<void>.delayed(latency);

    _messages.add(
      AstroMessage(
        id: 'fake-user-${_messages.length}',
        role: ChatRole.user,
        createdAt: DateTime.now(),
        text: message,
      ),
    );

    final reply = _scripted(_turn++);
    _messages.add(reply);

    return ChatReply(message: reply, remaining: 40 - _turn);
  }

  @override
  Future<ChatSnapshot> history() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return ChatSnapshot(
      messages: List.unmodifiable(_messages),
      facts: List.unmodifiable(_facts),
      remaining: 40 - _turn,
    );
  }

  @override
  Future<List<AstroFact>> forget({String? key}) async {
    if (key == null) {
      _facts.clear();
    } else {
      _facts.removeWhere((fact) => fact.key == key);
    }
    return List.unmodifiable(_facts);
  }

  AstroMessage _scripted(int turn) {
    final id = 'fake-astro-$turn';
    final now = DateTime.now();

    // The first turn asks for the hour, as the real prompt is instructed to — so the ask_for
    // control and the time picker behind it are exercised without a model.
    if (turn == 0) {
      return AstroMessage(
        id: id,
        role: ChatRole.astro,
        createdAt: now,
        titleEmoji: '🪔',
        title: 'Before We Begin',
        text: 'Come, sit. Your Chandra rests in Vrishabha, which is a patient sign and slow to '
            'give its trust — but the finer reading needs the hour you arrived. Tell me that, '
            'and I can name the nakshatra you were born beneath.',
        options: const ['Morning', 'Afternoon', 'Evening', 'I do not know'],
        askFor: AskFor.birthTime,
      );
    }

    if (turn == 1) {
      _facts.add(const AstroFact(key: 'birth_time', value: 'the morning'));
      return AstroMessage(
        id: id,
        role: ChatRole.astro,
        createdAt: now,
        titleEmoji: '✨',
        title: 'Your Love Reading',
        text: 'Then your Moon sits in Rohini, the nakshatra of steady attachment. Those born '
            'beneath it tend to love slowly and then wholly, and to be more wounded by '
            'carelessness than by argument.',
        sections: const [
          AstroSection(
            emoji: '❤️',
            heading: 'Relationship Energy',
            body: 'A season for tending what already exists rather than seeking what does not.',
          ),
          AstroSection(
            emoji: '💞',
            heading: 'Love Opportunities',
            body: 'What comes is likelier to come through people who already know you.',
          ),
        ],
        options: const ['What of my career?', 'Tell me of Shani'],
      );
    }

    return AstroMessage(
      id: id,
      role: ChatRole.astro,
      createdAt: now,
      titleEmoji: '💫',
      title: 'The Season Ahead',
      text: 'Rohini asks for patience, and the months after your next birthday will ask more of '
          'it than of your courage. What you plant quietly now tends to be what you are glad '
          'of later.',
      sections: const [
        AstroSection(
          emoji: '🌱',
          heading: 'What To Tend',
          body: 'One thing, properly. Vrishabha does not reward a scattered hand.',
        ),
      ],
      options: const ['And my family?', 'What should I avoid?'],
    );
  }
}
