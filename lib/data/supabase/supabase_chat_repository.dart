import '../models/astro_message.dart';
import '../repositories/chat_repository.dart';
import 'edge_functions.dart';
import 'session_store.dart';

/// Talks to the `astro-chat` and `chat-history` Edge Functions. Gemini is never called from the
/// device.
///
/// The client sends a message and a thread id and nothing else. The prompt, the chart, the
/// memory, the daily allowance and the entitlement check all live server-side, because the anon
/// key ships inside the app and anything the app could assert about its own quota would be
/// assertable by anyone. The thread id is checked against the session's user before it is read
/// from or written to, so sending someone else's id reaches nothing.
class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this._functions, this._sessions);

  final EdgeFunctions _functions;
  final SessionStore _sessions;

  /// A text turn returns in 2-5 seconds; the function gives up at 30. Sitting just past that
  /// lets an orderly failure return its own message rather than being cut off here and reported
  /// as a generic timeout.
  static const _sendTimeout = Duration(seconds: 35);

  @override
  Future<ChatReply> send(String message, {String? threadId}) async {
    final data = await _call('astro-chat', {
      'message': message,
      // Omitted rather than sent as null on the first turn of a new conversation: the server
      // reads its absence as "open one for me".
      if (threadId != null && threadId.isNotEmpty) 'thread_id': threadId,
    }, _sendTimeout);

    final reply = AstroMessage.fromServer(data['message']);
    if (reply == null) {
      // The call succeeded and the body is not a reply. Nothing the user can act on, and asking
      // again is the only sensible offer.
      throw const ChatUnavailableException(
        'That answer came back empty. Please ask again.',
      );
    }

    final thread = data['thread'] is Map ? data['thread'] as Map : const {};
    final landedIn = _text(thread['id']);
    if (landedIn.isEmpty) {
      // A reply with no conversation to file it under would be cached nowhere and unreachable
      // from the sidebar. Better to say so than to show a turn that vanishes on the next open.
      throw const ChatUnavailableException(
        'That answer could not be saved. Please ask again.',
      );
    }

    return ChatReply(
      message: reply,
      threadId: landedIn,
      threadTitle: _text(thread['title']),
      remaining: data['remaining'] is int ? data['remaining'] as int : null,
    );
  }

  @override
  Future<ChatThreadList> threads() async {
    final data = await _call('chat-history', const {}, null);
    return _threadList(data);
  }

  @override
  Future<ChatSnapshot> history(String threadId) async {
    final data = await _call('chat-history', {'thread_id': threadId}, null);
    final thread = data['thread'] is Map ? data['thread'] as Map : const {};

    return ChatSnapshot(
      messages: [
        for (final entry in (data['messages'] is List ? data['messages'] as List : const []))
          ?AstroMessage.fromServer(entry),
      ],
      facts: _facts(data),
      title: _text(thread['title']),
      remaining: data['remaining'] is int ? data['remaining'] as int : null,
    );
  }

  @override
  Future<ChatThreadList> renameThread(String id, String title) async {
    final data = await _call('chat-history', {
      'rename': {'thread_id': id, 'title': title},
    }, null);
    return _threadList(data);
  }

  @override
  Future<ChatThreadList> deleteThread(String id) async {
    final data = await _call('chat-history', {'delete_thread': id}, null);
    return _threadList(data);
  }

  @override
  Future<List<AstroFact>> forget({String? key}) async {
    // "*" is the server's forget-everything. Spelled out here rather than passed through from a
    // caller, so no screen can widen a single deletion by accident.
    final data = await _call('chat-history', {'forget': key ?? '*'}, null);
    return _facts(data);
  }

  ChatThreadList _threadList(Map<String, dynamic> data) {
    return ChatThreadList(
      threads: [
        for (final entry in (data['threads'] is List ? data['threads'] as List : const []))
          ?ChatThreadSummary.fromServer(entry),
      ],
      facts: _facts(data),
      remaining: data['remaining'] is int ? data['remaining'] as int : null,
    );
  }

  List<AstroFact> _facts(Map<String, dynamic> data) => [
        for (final entry in (data['facts'] is List ? data['facts'] as List : const []))
          ?AstroFact.fromServer(entry),
      ];

  static String _text(Object? raw) => raw?.toString().trim() ?? '';

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
        'not_found' => ChatThreadGoneException(e.message),
        'ai_unavailable' => ChatUnavailableException(e.message),
        // Includes the transport failures, where `code` is null and the message already
        // explains the network rather than the server.
        _ => ChatUnavailableException(e.message),
      };
    }
  }
}
