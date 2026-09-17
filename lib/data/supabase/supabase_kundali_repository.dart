import '../models/app_user.dart';
import '../models/birth_place.dart';
import '../models/kundali.dart';
import '../repositories/kundali_repository.dart';
import 'edge_functions.dart';
import 'session_store.dart';

/// Talks to the `kundali` Edge Function. The chart, the reading and the reveal all live there.
class SupabaseKundaliRepository implements KundaliRepository {
  SupabaseKundaliRepository(this._functions, this._sessions);

  final EdgeFunctions _functions;
  final SessionStore _sessions;

  @override
  Future<KundaliSummary?> status({String surface = 'home'}) async {
    final data = await _call({'action': 'status', 'surface': surface});
    if (data['kundali'] == null) return null;
    final summary = KundaliSummary.fromServer(data['kundali'], receivedAt: DateTime.now());
    if (summary == null) {
      throw const KundaliUnavailableException('Could not read your Kundali. Please try again.');
    }
    return summary;
  }

  @override
  Future<KundaliReading> report() async {
    final data = await _call({'action': 'report'});
    final reading = KundaliReading.fromServer(data['kundali'], receivedAt: DateTime.now());
    if (reading == null) {
      throw const KundaliUnavailableException('Your Kundali came back incomplete. Please try again.');
    }
    return reading;
  }

  @override
  Future<KundaliSummary> request({
    required DateTime birthDate,
    required String birthTime,
    required BirthPlace place,
  }) async {
    final data = await _call({
      'action': 'request',
      'dob': AppUser.formatBirthDate(birthDate),
      'birth_time': birthTime,
      'place': place.toRequest(),
    });
    final summary = KundaliSummary.fromServer(data['kundali'], receivedAt: DateTime.now());
    if (summary == null) {
      throw const KundaliUnavailableException('Could not start your Kundali. Please try again.');
    }
    return summary;
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final token = await _sessions.readToken();
    if (token == null) throw const KundaliSignedOutException('Please sign in again.');

    try {
      return await _functions.call('kundali', bearerToken: token, body: body);
    } on EdgeError catch (e) {
      throw switch (e.code) {
        'not_ready' => KundaliNotReadyException(e.message),
        'limit_reached' => KundaliLimitException(e.message),
        'invalid_request' => KundaliInvalidException(e.message),
        'not_found' => KundaliNotFoundException(e.message),
        'not_entitled' => KundaliNotEntitledException(e.message),
        'unauthorized' => const KundaliSignedOutException('Please sign in again.'),
        _ => KundaliUnavailableException(e.message),
      };
    }
  }
}
