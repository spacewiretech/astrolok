import '../models/astro_message.dart';

/// One turn of a conversation with Astro, and the transcript behind it.
///
/// The implementation talks to Edge Functions that hold the model credentials. Nothing here ever
/// sees an API key, and no conversation is ever read without a session token.
abstract interface class ChatRepository {
  /// Sends a message and returns Astro's reply.
  ///
  /// [threadId] is null for the first message of a new conversation — the server opens one and
  /// says which in [ChatReply.threadId]. Passing an id that no longer resolves starts a new
  /// conversation rather than failing, so a stale id cannot leave someone unable to talk.
  Future<ChatReply> send(String message, {String? threadId});

  /// Every conversation, newest first, for the sidebar.
  Future<ChatThreadList> threads();

  /// One conversation in full, and what Astro remembers.
  Future<ChatSnapshot> history(String threadId);

  /// Renames a conversation. Returns the list as it stands afterwards.
  Future<ChatThreadList> renameThread(String id, String title);

  /// Removes a conversation from the sidebar. Returns the list as it stands afterwards.
  Future<ChatThreadList> deleteThread(String id);

  /// Forgets one fact by its key, or everything when [key] is null.
  ///
  /// Returns the memory as it stands afterwards, so the caller renders the server's answer
  /// rather than its own guess at it.
  Future<List<AstroFact>> forget({String? key});
}

/// What comes back from one turn.
class ChatReply {
  const ChatReply({
    required this.message,
    required this.threadId,
    this.threadTitle = '',
    this.remaining,
  });

  final AstroMessage message;

  /// The conversation this turn landed in — the one that was asked for, or a newly opened one.
  final String threadId;

  /// What the server decided to call it. Only interesting on the first turn, when the
  /// conversation gets its name.
  final String threadTitle;

  /// Questions left today, so the composer can close before the next one is refused.
  final int? remaining;
}

/// The sidebar, and the day's allowance alongside it.
class ChatThreadList {
  const ChatThreadList({
    this.threads = const [],
    this.facts = const [],
    this.remaining,
  });

  final List<ChatThreadSummary> threads;
  final List<AstroFact> facts;
  final int? remaining;
}

/// One transcript, the memory, and the day's allowance.
class ChatSnapshot {
  const ChatSnapshot({
    this.messages = const [],
    this.facts = const [],
    this.title = '',
    this.remaining,
  });

  final List<AstroMessage> messages;
  final List<AstroFact> facts;

  /// What this conversation is called, so the header can say so.
  final String title;

  final int? remaining;
}

/// Base for everything that can go wrong. [message] is always safe to show.
///
/// Its own hierarchy rather than an extension of `FaceException`, for the reason
/// `face_repository.dart` gives for not sharing with palm: the screens switch on these
/// exhaustively, and a shared base would let a case belonging to another feature fall silently
/// through this one's handling.
class ChatException implements Exception {
  const ChatException(this.message);

  final String message;

  @override
  String toString() => 'ChatException: $message';
}

/// The day's allowance is gone. Not a failure — the composer closes and says so.
class ChatLimitReachedException extends ChatException {
  const ChatLimitReachedException(super.message);
}

/// The model is unreachable, overloaded, or answered with something unusable. Retryable, and
/// nothing is wrong with what the user typed — so the message is offered back to them rather
/// than discarded.
class ChatUnavailableException extends ChatException {
  const ChatUnavailableException(super.message);
}

/// The subscription lapsed mid-conversation.
class ChatNotEntitledException extends ChatException {
  const ChatNotEntitledException(super.message);
}

/// The session is gone; the user has to sign in again.
class ChatSignedOutException extends ChatException {
  const ChatSignedOutException(super.message);
}

/// The conversation is not there any more — deleted on another device, or aged out.
///
/// Distinct from [ChatUnavailableException] because there is nothing to retry: the screen drops
/// what it was holding and opens a new conversation rather than offering the message back.
class ChatThreadGoneException extends ChatException {
  const ChatThreadGoneException(super.message);
}
