import '../models/astro_message.dart';
import '../repositories/chat_repository.dart';
import 'edge_functions.dart';
import 'session_store.dart';

/// Talks to the `astro-chat` and `chat-history` Edge Functions. Gemini is never called from the
/// device.
///
/// The client sends a message and nothing else. The prompt, the chart, the memory, the daily
/// allowance and the entitlement check all live server-side, because the anon key ships inside
/// the app and anything the app could assert about its own quota would be assertable by anyone.
class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this._functions, this._sessions);

  final EdgeFunctions _functions;
  final SessionStore _sessions;

  /// A text turn returns in 2-5 seconds; the function gives up at 30. Sitting just past that
  /// lets an orderly failure return its own message rather than being cut off here and reported
  /// as a generic timeout.
  static const _sendTimeout = Duration(seconds: 35);

  @override
  Future<ChatReply> send(String message) async {
    final data = await _call('astro-chat', {'message': message}, _sendTimeout);

    final reply = AstroMessage.fromServer(data['message']);
    if (reply == null) {
      // The call succeeded and the body is not a reply. Nothing the user can act on, and asking
      // again is the only sensible offer.
      throw const ChatUnavailableException(
        'That answer came back empty. Please ask again.',
      );
    }

    return ChatReply(
      message: reply,
      remaining: data['remaining'] is int ? data['remaining'] as int : null,
    );
  }

  @override
  Future<ChatSnapshot> history() async {
    final data = await _call('chat-history', const {}, null);
    return _snapshot(data);
  }

  @override
  Future<List<AstroFact>> forget({String? key}) async {
    // "*" is the server's forget-everything. Spelled out here rather than passed through from a
    // caller, so no screen can widen a single deletion by accident.
    final data = await _call('chat-history', {'forget': key ?? '*'}, null);
    return _snapshot(data).facts;
  }

  ChatSnapshot _snapshot(Map<String, dynamic> data) {
    return ChatSnapshot(
      messages: [
        for (final entry in (data['messages'] is List ? data['messages'] as List : const []))
          ?AstroMessage.fromServer(entry),
      ],
      facts: [
        for (final entry in (data['facts'] is List ? data['facts'] as List : const []))
          ?AstroFact.fromServer(entry),
      ],
      remaining: data['remaining'] is int ? data['remaining'] as int : null,
    );
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> body,
    Duration? timeout,
  ) async {
    final token = await _sessions.readToken();
    if (token == null) {
      throw const ChatSignedOutException('Please sign in again.');
    }

    try {
      return await _functions.call(
        name,
        bearerToken: token,
        timeout: timeout,
        body: body,
      );
    } on EdgeError catch (e) {
      throw switch (e.code) {
        'limit_reached' => ChatLimitReachedException(e.message),
        'not_entitled' => ChatNotEntitledException(e.message),
        'unauthorized' => const ChatSignedOutException('Please sign in again.'),
        'ai_unavailable' => ChatUnavailableException(e.message),
        // Includes the transport failures, where `code` is null and the message already
        // explains the network rather than the server.
        _ => ChatUnavailableException(e.message),
      };
    }
  }
}
