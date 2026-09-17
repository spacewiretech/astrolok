import '../models/app_user.dart';
import '../models/birth_place.dart';
import '../models/kundali.dart';
import '../repositories/kundali_repository.dart';
import '../repositories/place_repository.dart';
import 'fake_kundali_chart.dart';
import 'fake_session.dart';

/// A kundali with no server behind it, so the three screens stay walkable on a fresh checkout.
///
/// The wait is real but short — [unlockAfter] — so the whole journey, form to countdown to reveal,
/// can be seen in one sitting. The chart is a genuine one from the server's engine; the reading is
/// canned.
class FakeKundaliRepository implements KundaliRepository {
  FakeKundaliRepository({this.unlockAfter = const Duration(seconds: 45), this.latency = true});

  final Duration unlockAfter;

  /// Off in tests, where a timer left pending at teardown fails the test.
  final bool latency;

  Map<String, Object?>? _row;
  int _regenerationsLeft = 2;

  Future<void> _wait() => latency ? FakeSession.latency(500) : Future<void>.value();

  @override
  Future<KundaliSummary?> status({String surface = 'home'}) async {
    await _wait();
    final row = _row;
    if (row == null) return null;
    return KundaliSummary.fromServer(_payload(row), receivedAt: DateTime.now());
  }

  @override
  Future<KundaliReading> report() async {
    await _wait();
    final row = _row;
    if (row == null) throw const KundaliNotFoundException("You haven't asked for your Kundali yet.");
    final payload = _payload(row);
    if (payload['state'] != 'ready') {
      throw const KundaliNotReadyException("Your Kundali isn't ready to be revealed yet.");
    }
    row['viewed'] = true;
    return KundaliReading.fromServer(
      {..._payload(row), 'chart': fakeKundaliChart, 'report': fakeKundaliReport, 'language': 'English'},
      receivedAt: DateTime.now(),
    )!;
  }

  @override
  Future<KundaliSummary> request({
    required DateTime birthDate,
    required String birthTime,
    required BirthPlace place,
  }) async {
    await _wait();
    final dob = AppUser.formatBirthDate(birthDate);
    final existing = _row;
    final same = existing != null &&
        (existing['birth'] as Map)['dob'] == dob &&
        (existing['birth'] as Map)['birth_time'] == birthTime &&
        (existing['birth'] as Map)['place_label'] == place.label;

    if (!same) {
      if (existing != null) {
        if (_regenerationsLeft <= 0) {
          throw const KundaliLimitException('Your Kundali has already been re-cast the most times allowed.');
        }
        _regenerationsLeft -= 1;
      }
      final now = DateTime.now().toUtc();
      _row = {
        'id': 'fake-kundali-${now.millisecondsSinceEpoch}',
        'requested_at': now.toIso8601String(),
        'unlock_at': now.add(unlockAfter).toIso8601String(),
        'birth': {
          'dob': dob,
          'birth_time': birthTime,
          'place_label': place.label,
          'place_id': place.placeId,
          'time_zone_id': place.timeZoneId,
        },
        'viewed': false,
      };
    }
    return KundaliSummary.fromServer(_payload(_row!), receivedAt: DateTime.now())!;
  }

  Map<String, Object?> _payload(Map<String, Object?> row) {
    final now = DateTime.now().toUtc();
    final requested = DateTime.parse(row['requested_at'] as String);
    final unlock = DateTime.parse(row['unlock_at'] as String);
    final span = unlock.difference(requested);
    final moon = fakeKundaliChart['moon'] as Map;
    return {
      ...row,
      'state': now.isBefore(unlock) ? 'waiting' : 'ready',
      'server_now': now.toIso8601String(),
      'unlock_hours': span.inSeconds / 3600,
      'teaser': {
        'moon_rashi': moon['rashi'],
        'moon_sign': moon['sign'],
        'nakshatra': moon['nakshatra'],
        'pada': moon['pada'],
      },
      'stages': [
        for (final (key, fraction) in const [('positions', 0.02), ('lagna', 0.10), ('dasha', 0.55), ('insights', 1.0)])
          {'key': key, 'completes_at': requested.add(span * fraction).toIso8601String()},
      ],
      'regenerations_left': _regenerationsLeft,
    };
  }
}

/// Twenty cities, enough to walk the form without a Google key.
class FakePlaceRepository implements PlaceRepository {
  const FakePlaceRepository();

  static const _cities = [
    ('Tirupati', 'Andhra Pradesh, India', 13.6288, 79.4192),
    ('Delhi', 'India', 28.6139, 77.2090),
    ('Mumbai', 'Maharashtra, India', 19.0760, 72.8777),
    ('Bengaluru', 'Karnataka, India', 12.9716, 77.5946),
    ('Chennai', 'Tamil Nadu, India', 13.0827, 80.2707),
    ('Hyderabad', 'Telangana, India', 17.3850, 78.4867),
    ('Kolkata', 'West Bengal, India', 22.5726, 88.3639),
    ('Pune', 'Maharashtra, India', 18.5204, 73.8567),
    ('Ahmedabad', 'Gujarat, India', 23.0225, 72.5714),
    ('Jaipur', 'Rajasthan, India', 26.9124, 75.7873),
    ('Lucknow', 'Uttar Pradesh, India', 26.8467, 80.9462),
    ('Varanasi', 'Uttar Pradesh, India', 25.3176, 82.9739),
    ('Patna', 'Bihar, India', 25.5941, 85.1376),
    ('Bhopal', 'Madhya Pradesh, India', 23.2599, 77.4126),
    ('Kochi', 'Kerala, India', 9.9312, 76.2673),
    ('Thiruvananthapuram', 'Kerala, India', 8.5241, 76.9366),
    ('Madurai', 'Tamil Nadu, India', 9.9252, 78.1198),
    ('Mysuru', 'Karnataka, India', 12.2958, 76.6394),
    ('Visakhapatnam', 'Andhra Pradesh, India', 17.6868, 83.2185),
    ('Chandigarh', 'India', 30.7333, 76.7794),
  ];

  @override
  Future<List<PlaceSuggestion>> autocomplete(String input, {required String sessionToken}) async {
    await FakeSession.latency(150);
    final query = input.trim().toLowerCase();
    return [
      for (final (name, region, _, _) in _cities)
        if (name.toLowerCase().startsWith(query) || name.toLowerCase().contains(query))
          PlaceSuggestion(placeId: 'fake-${name.toLowerCase()}', primary: name, secondary: region),
    ].take(5).toList();
  }

  @override
  Future<BirthPlace> details(
    PlaceSuggestion suggestion, {
    required String sessionToken,
    DateTime? birthDate,
    String? birthTime,
  }) async {
    await FakeSession.latency(150);
    for (final (name, _, lat, lng) in _cities) {
      if ('fake-${name.toLowerCase()}' == suggestion.placeId) {
        return BirthPlace(
          placeId: suggestion.placeId,
          label: suggestion.label,
          latitude: lat,
          longitude: lng,
          timeZoneId: 'Asia/Kolkata',
        );
      }
    }
    throw const PlaceNotFoundException("We couldn't find that place. Please pick another from the list.");
  }
}

/// A canned reading for [fakeKundaliChart], in the shape `normaliseKundaliReport` produces.
const fakeKundaliReport = <String, Object?>{
  'invocation': 'Sit with me a while, and let us look at the sky you were born under.',
  'headline': 'A steady heart that builds slowly and loves deeply',
  'highlights': [
    {'planet': 'sun', 'line': 'Surya in the eleventh house draws you toward circles of friends who share your aims.'},
    {'planet': 'moon', 'line': 'Chandra in the seventh house makes partnership the mirror you learn yourself in.'},
    {'planet': 'mars', 'line': 'Mangal in the third house gives courage that grows quieter and deeper with time.'},
    {'planet': 'mercury', 'line': 'Budh in the tenth house lends a clear, practical voice to your work.'},
    {'planet': 'jupiter', 'line': 'Guru beside the Moon in the seventh blesses bonds built on shared values.'},
    {'planet': 'venus', 'line': 'Shukra in the ninth house finds beauty in learning, travel and faith.'},
    {'planet': 'saturn', 'line': 'Shani in its own sign in the tenth rewards patient, disciplined effort.'},
    {'planet': 'rahu', 'line': 'Rahu in the sixth house turns daily challenges into a hunger to improve.'},
    {'planet': 'ketu', 'line': 'Ketu in the twelfth house invites quiet reflection and letting go.'},
  ],
  'insights': {
    'love': {
      'evidence': ['moon_h7', 'jupiter_h7', 'venus_h9'],
      'summary': 'Partnership tends to be where you grow most, and generosity keeps it warm.',
      'detail':
          'Your Chandra — the Moon — sits in the seventh house of partnership, with Guru beside it. People with this placement often feel most themselves in a close bond, and tend to give generously once they trust. Shukra in the ninth house suggests a partner who shares your curiosity about the wider world keeps the connection alive.',
      'tip': 'Say out loud the small things you admire in the people close to you.',
    },
    'career': {
      'evidence': ['saturn_h10', 'saturn_own', 'mercury_h10'],
      'summary': 'Work that rewards patience and clear thinking suits you well.',
      'detail':
          'Shani sits in its own sign in your tenth house of work, a placement that tends to reward steady, disciplined effort over quick wins. Budh alongside it lends a clear and practical voice, so roles that ask you to organise, explain or plan often suit you.',
      'tip': 'Choose one long project this month and give it a fixed hour each day.',
    },
    'finance': {
      'evidence': ['lord2_h4', 'jupiter_h7', 'sun_h11'],
      'summary': 'You lean toward earning through people and keeping a calm hand with savings.',
      'detail':
          'The lord of your second house sits in the fourth, which often points to an instinct for security and a home-centred way of saving. Surya in the eleventh house of gains suggests your circles and collaborations tend to open doors, and Guru in the seventh leans toward generosity in partnership.',
      'tip': 'Before a large purchase, wait one full day and decide again.',
    },
    'year_ahead': {
      'evidence': ['mahadasha_mercury', 'antardasha_rahu', 'transit_jupiter_h9'],
      'summary': 'This season favours learning, new skills and widening your horizons.',
      'detail':
          'You are in the period of Budh, with Rahu running within it — a season that tends to stir curiosity and a wish to try something new. Guru is moving through the ninth sign from your Moon, which often brings teachers, study or meaningful travel into view.',
      'tip': 'Sign up for the class or course you have been putting off.',
    },
  },
  'houses': [
    {'house': 1, 'theme': 'A calm, grounded presence that others find reassuring.'},
    {'house': 2, 'theme': 'Speech and family values shaped by care and patience.'},
    {'house': 3, 'theme': 'Courage that grows through effort and honest communication.'},
    {'house': 4, 'theme': 'A deep need for a peaceful, secure home.'},
    {'house': 5, 'theme': 'Creativity that flourishes when it has a practical purpose.'},
    {'house': 6, 'theme': 'Turning daily obstacles into steady self-improvement.'},
    {'house': 7, 'theme': 'Partnerships as the place you grow the most.'},
    {'house': 8, 'theme': 'Quiet resilience through life’s changes.'},
    {'house': 9, 'theme': 'Faith, learning and travel as sources of joy.'},
    {'house': 10, 'theme': 'Recognition earned through patience and discipline.'},
    {'house': 11, 'theme': 'Friends and networks that open doors.'},
    {'house': 12, 'theme': 'Reflection, rest and letting go.'},
  ],
  'dasha_summary':
      'The period of Budh with Rahu within it tends to emphasise learning and fresh ideas. Meet it with curiosity, and ground new plans in steady routines.',
  'blessing': 'May your patience keep finding good company, and your curiosity good teachers.',
};
