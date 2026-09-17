import 'package:astrolok/app/push_navigation.dart';
import 'package:astrolok/data/firebase/push_payload.dart';
import 'package:astrolok/data/models/app_user.dart';
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
}
