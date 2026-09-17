import '../models/birth_place.dart';
import '../models/kundali.dart';

/// The kundali: ask for one, check on it, read it once it is revealed.
///
/// The chart is cast and the reading written server-side. The server also enforces the reveal —
/// [report] is refused until `unlock_at` — so the app's countdown is a courtesy, never the lock.
abstract interface class KundaliRepository {
  /// This account's live kundali, or null when it has never asked for one.
  ///
  /// [surface] is `home` or `waiting`. The waiting screen passes `waiting`, which is how the
  /// halfway reminder knows not to nudge someone who has already come back to look.
  Future<KundaliSummary?> status({String surface = 'home'});

  /// The revealed kundali. Throws [KundaliNotReadyException] before the reveal.
  Future<KundaliReading> report();

  /// Casts a kundali. Asking again with the same details returns the one already cast; different
  /// details spend a regeneration and restart the wait.
  Future<KundaliSummary> request({
    required DateTime birthDate,
    required String birthTime,
    required BirthPlace place,
  });
}

/// Base for everything that can go wrong. [message] is always safe to show.
class KundaliException implements Exception {
  const KundaliException(this.message);

  final String message;

  @override
  String toString() => 'KundaliException: $message';
}

/// Not revealed yet, or revealed but not written. The waiting screen, not an error.
class KundaliNotReadyException extends KundaliException {
  const KundaliNotReadyException(super.message);
}

/// The regenerations are spent.
class KundaliLimitException extends KundaliException {
  const KundaliLimitException(super.message);
}

/// Something about the birth details was refused. The message says what.
class KundaliInvalidException extends KundaliException {
  const KundaliInvalidException(super.message);
}

/// There is no kundali to show.
class KundaliNotFoundException extends KundaliException {
  const KundaliNotFoundException(super.message);
}

class KundaliNotEntitledException extends KundaliException {
  const KundaliNotEntitledException(super.message);
}

class KundaliSignedOutException extends KundaliException {
  const KundaliSignedOutException(super.message);
}

/// The network, or the server. Worth trying again.
class KundaliUnavailableException extends KundaliException {
  const KundaliUnavailableException(super.message);
}
