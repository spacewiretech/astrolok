import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'attribution/attribution_service.dart';
import 'firebase/push_messaging.dart';
import 'models/app_user.dart';
import 'providers.dart';

/// The last entitlement answer the server gave, held where the routing layer can read it
/// synchronously.
///
/// Deliberately *not* recomputed on write. While the app is online the server's answer is the
/// authority, grace window and all; re-deriving it here would let the client disagree with the
/// backend the moment `entitlement_grace_hours` is tuned. Offline re-derivation happens in one
/// place only — [SessionStore], where there is no server to ask.
class EntitlementNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  void set(AppUser? user) {
    state = user;

    // The single analytics identity hook. Every path that ends holding a fresh user comes through
    // here — the splash, OTP verification, picking a language, saving the name and birth date,
    // the entitlement gate on mount and on every resume, and the payment-status poll — so binding
    // the Mixpanel profile here means no caller has to remember to.
    //
    // The implementation ignores a repeat of the same account, which matters because the gate
    // re-resolves on every resume; it compares the *profile* rather than the id, so a trial
    // converting to a paid month still updates.
    if (user != null) ref.read(analyticsProvider).identify(user);

    // And the same hook claims a pending referral, for exactly the same reason: this is the one
    // place that reliably holds a *signed-in* user, and a claim needs a session token.
    //
    // Unawaited — nothing on screen waits for a referral, and this runs on every resume. The
    // service guards itself against overlapping drains and against re-asking once the backend has
    // given a terminal answer, so the repeat calls cost a single flag read.
    if (user != null) unawaited(attributionService.onUserResolved());

    // And registers this device for push, once more for the same reason: the token is stored
    // against the session. Unawaited, and de-duplicated inside by token and account, so the resume
    // that re-resolves the same user costs a token read and no request.
    if (user != null) unawaited(pushMessaging.onUserResolved(user));
  }

  void clear() => state = null;
}

final entitlementProvider =
    NotifierProvider<EntitlementNotifier, AppUser?>(EntitlementNotifier.new);
