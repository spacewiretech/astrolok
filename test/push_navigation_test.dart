import 'package:astrolok/app/push_navigation.dart';
import 'package:astrolok/data/firebase/push_payload.dart';
import 'package:astrolok/data/models/app_user.dart';
import 'package:astrolok/features/chat/chat_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where a tapped push goes. A push is data from outside the app, so every rule here is also a
/// refusal: a route not on the allowlist, a signed-out device, a lapsed account.

AppUser _user({bool entitled = true, String name = 'Asha', DateTime? dob, PaymentType type = PaymentType.active}) => AppUser(
      id: 'u1',
      phone: '9931145610',
      name: name,
      birthDate: dob ?? DateTime(1995, 3, 21),
      paymentType: type,
      entitled: entitled,
      chatLanguage: 'English',
    );

PushPayload _to(String route, {String? id}) =>
    PushPayload.fromData({'route': route, 'campaign': 'test', 'notification_id': ?id});

void main() {
  test('only allowed routes survive parsing', () {
    expect(PushPayload.fromData({'route': '/kundali'}).route, '/kundali');
    expect(PushPayload.fromData({'route': '/palm/reading/123'}).route, isNull);
    expect(PushPayload.fromData({'route': 'https://evil.example'}).route, isNull);
    expect(PushPayload.fromData({'params': '{bad json'}).params, isEmpty);
    expect(PushPayload.fromData({'params': '{"kundali_id":"k1"}'}).params['kundali_id'], 'k1');
  });

  test('an unknown route or a signed-out device goes nowhere', () {
    expect(resolvePushNavigation(PushPayload.fromData({'route': '/nope'}), user: _user()).dropReason, 'unknown_route');
    expect(resolvePushNavigation(_to('/kundali'), user: null), const PushNavigation(dropReason: 'signed_out'));
  });

  test('a gated screen opens over Home for an entitled, onboarded account', () {
    for (final route in ['/palm', '/face', '/chat', '/kundali', '/profile']) {
      expect(resolvePushNavigation(_to(route), user: _user()), PushNavigation(go: '/home', push: route), reason: route);
    }
  });

  test('a lapsed account is taken to the paywall instead', () {
    final nav = resolvePushNavigation(_to('/kundali'), user: _user(entitled: false, type: PaymentType.cancelled));
    expect(nav.go, '/subscribe');
    expect(nav.push, isNull);
    expect(nav.dropReason, 'not_entitled');
  });

  test('the leaving screen always opens — its person has usually just lost access', () {
    final lapsed = _user(entitled: false, type: PaymentType.cancelled);
    expect(resolvePushNavigation(_to('/leaving', id: 'n-1'), user: lapsed), const PushNavigation(go: '/leaving?nid=n-1'));
    expect(resolvePushNavigation(_to('/leaving'), user: _user()), const PushNavigation(go: '/leaving'));
  });

  test('the paywall push does nothing for an account that already paid', () {
    expect(resolvePushNavigation(_to('/subscribe'), user: _user(entitled: false, type: PaymentType.none)),
        const PushNavigation(go: '/subscribe'));
    expect(resolvePushNavigation(_to('/subscribe'), user: _user()).dropReason, 'already_entitled');
  });

  test('the birth-details push only opens while onboarding still wants them', () {
    final unfinished = AppUser(id: 'u1', phone: '9', name: 'Asha', paymentType: PaymentType.trial, entitled: true);
    expect(resolvePushNavigation(_to('/birth'), user: unfinished), const PushNavigation(go: '/birth'));
    expect(resolvePushNavigation(_to('/birth'), user: _user()).dropReason, 'no_longer_needed');
  });

  test('an account still in onboarding finishes onboarding before a gated screen', () {
    final unfinished = AppUser(id: 'u1', phone: '9', name: '', paymentType: PaymentType.trial, entitled: true);
    final nav = resolvePushNavigation(_to('/chat'), user: unfinished);
    expect(nav.go, '/birth');
    expect(nav.push, isNull);
  });

  group('a drip push that carries a question', () {
    PushPayload chat({String? q, String? autosend}) => PushPayload.fromData({
          'route': '/chat',
          'campaign': 'daily_today',
          'params': '{"slot":"today","variant":"today_0"'
              '${q == null ? '' : ',"q":${_json(q)}'}'
              '${autosend == null ? '' : ',"autosend":"$autosend"'}}',
        });

    test('reaches the composer as a ChatLaunch', () {
      final nav = resolvePushNavigation(chat(q: 'What does today hold for me?'), user: _user());
      expect(nav.go, '/home');
      expect(nav.push, '/chat');
      expect(nav.extra, const ChatLaunch(question: 'What does today hold for me?', source: 'push'));
    });

    test('is labelled as a push, not as a reading', () {
      // `Chat Opened`'s source drives the funnel. It must not follow autoSend — the two stopped
      // meaning the same thing once a push could auto-send as well.
      for (final autosend in [null, '0', '1']) {
        final nav = resolvePushNavigation(chat(q: 'Hi?', autosend: autosend), user: _user());
        expect((nav.extra! as ChatLaunch).source, 'push', reason: 'autosend=$autosend');
      }
    });

    test('does not send itself unless the server says so', () {
      // Sending on arrival spends a turn and a Gemini call the user never asked for. Anything other
      // than an explicit "1" — absent, empty, "true", "yes" — must mean "put it in the composer".
      expect((resolvePushNavigation(chat(q: 'Hi?'), user: _user()).extra! as ChatLaunch).autoSend, isFalse);
      for (final value in ['0', '', 'true', 'yes', 'TRUE']) {
        final nav = resolvePushNavigation(chat(q: 'Hi?', autosend: value), user: _user());
        expect((nav.extra! as ChatLaunch).autoSend, isFalse, reason: value);
      }
      final on = resolvePushNavigation(chat(q: 'Hi?', autosend: '1'), user: _user());
      expect((on.extra! as ChatLaunch).autoSend, isTrue);
    });

    test('a question the server did not send, or sent badly, costs the question and not the push', () {
      for (final payload in [
        chat(),
        chat(q: ''),
        chat(q: '   '),
        PushPayload.fromData({'route': '/chat', 'params': '{"q":42}'}),
        PushPayload.fromData({'route': '/chat', 'params': '{"q":"${'x' * 201}"}'}),
      ]) {
        final nav = resolvePushNavigation(payload, user: _user());
        expect(nav.push, '/chat', reason: 'the push still opens chat');
        expect(nav.extra, isNull);
      }
    });

    test('control characters are scrubbed before anything is typed', () {
      final nav = resolvePushNavigation(
        PushPayload.fromData({'route': '/chat', 'params': '{"q":"What\\u0000 does\\u001b today hold?"}'}),
        user: _user(),
      );
      expect((nav.extra! as ChatLaunch).question, 'What  does  today hold?');
    });

    test('a lapsed account gets the paywall and no question at all', () {
      // Every drip variant a non-entitled reader sees is routed to `/subscribe` server-side, but if
      // one ever slipped through, there is nowhere on the paywall to put a question.
      final nav = resolvePushNavigation(chat(q: 'What does today hold?'),
          user: _user(entitled: false, type: PaymentType.expired));
      expect(nav.go, '/subscribe');
      expect(nav.extra, isNull);
      expect(nav.dropReason, 'not_entitled');
    });

    test('only chat gets one', () {
      for (final route in ['/palm', '/face', '/kundali']) {
        final nav = resolvePushNavigation(
          PushPayload.fromData({'route': route, 'params': '{"q":"What does today hold?"}'}),
          user: _user(),
        );
        expect(nav.push, route);
        expect(nav.extra, isNull, reason: route);
      }
    });
  });
}

String _json(String value) => '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
