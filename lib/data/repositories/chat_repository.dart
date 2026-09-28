import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
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
  ///
  /// [entry] is which affordance produced it — `composer`, `quick_reply`, `topic`, `reading`,
  /// `push`, `birth_time`, `birth_place`. The server answers a button's English opener in the
  /// user's language rather than in English.
  ///
  /// [birthPlace] is the row they picked in the chat's place search, sent beside [message] (its
  /// description, so the transcript reads as their own words). The server resolves the id rather
  /// than geocoding the text: a typed town still works, but it is the likeliest match for the
  /// words, and a picked one is the exact row they chose.
  Future<ChatReply> send(
    String message, {
    String? threadId,
    String entry = 'composer',
    ChatBirthPlace? birthPlace,
  });

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

  /// Records how the conversation has felt, 1 to 5, or null when the card was dismissed.
  ///
  /// [comment] is what the user wrote beside the score, or null when they wrote nothing. It goes in
  /// the same request, so the score and the words are one answer.
  ///
  /// Asked once per account, which the server enforces: a second answer changes nothing.
  Future<void> rate({required String threadId, int? rating, String? comment});
}

/// A birth place picked from the search under Astro's ask: the Google row's id and what it said.
///
/// Not a `BirthPlace`: that is coordinates and a zone, which cost a Details call to learn. The
/// chat sends only what the search already returned and leaves resolving it to the server, which
/// has to look the place up anyway before it can save it.
@immutable
class ChatBirthPlace {
  const ChatBirthPlace({required this.placeId, required this.description, this.sessionToken});

  final String placeId;

  /// "Jaipur, Rajasthan, India" — the row as it was shown.
  final String description;

  /// The search's billing session, which the server's Details call closes. Google bills the
  /// keystrokes of a session that ends in a Details call as that one lookup; without it, every
  /// autocomplete request of the search was billed on its own, and the lookup again beside them.
  final String? sessionToken;

  /// The `birth_place` object `astro-chat` reads.
  Map<String, String> toRequest() => {
        'place_id': placeId,
        'description': description,
        'session_token': ?sessionToken,
      };

  @override
  bool operator ==(Object other) =>
      other is ChatBirthPlace &&
      other.placeId == placeId &&
      other.description == description &&
      other.sessionToken == sessionToken;

  @override
  int get hashCode => Object.hash(placeId, description, sessionToken);
}

/// What comes back from one turn.
class ChatReply {
  const ChatReply({
    required this.message,
    required this.threadId,
    this.threadTitle = '',
    this.remaining,
    this.savedLanguage,
    this.askRating = false,
    this.user,
  });

  /// The account as it stands after this turn, when the turn saved something onto it — a date or
  /// hour of birth given in the chat. Installed the way Profile installs a saved birth time, so
  /// Profile, the chart and the kundali all follow at once. Null when nothing was saved.
  final AppUser? user;

  /// Set when this message moved the account's chat language and the server saved it — they wrote
  /// in Devanagari, or asked for Hindi in words. Null when nothing changed.
  ///
  /// The app has to be told: Profile's picker and the read-aloud voice both follow the stored
  /// language, and neither would otherwise hear about it until the next sign-in.
  final String? savedLanguage;

  /// True when the server wants this account asked to rate the chat. It says so on every reply
  /// until they answer or dismiss, and never again after.
  final bool askRating;

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
