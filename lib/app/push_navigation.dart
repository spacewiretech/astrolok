import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/analytics/analytics.dart';
import '../data/analytics/analytics_events.dart';
import '../data/analytics/analytics_session.dart';
import '../data/entitlement.dart';
import '../data/firebase/push_messaging.dart';
import '../data/firebase/push_payload.dart';
import '../data/models/app_user.dart';
import '../features/splash/splash_viewmodel.dart';
import 'router.dart';

/// Where a tapped push goes, decided before anything navigates.
@immutable
class PushNavigation {
  const PushNavigation({this.go, this.push, this.dropReason});

  /// Replaces the stack.
  final String? go;

  /// Pushed on top of [go], so back lands somewhere sensible rather than closing the app.
  final String? push;

  /// Set when the push could not go where it pointed. [go] may still be set — a lapsed account is
  /// taken to the paywall rather than left where it was.
  final String? dropReason;

  @override
  bool operator ==(Object other) =>
      other is PushNavigation && other.go == go && other.push == push && other.dropReason == dropReason;

  @override
  int get hashCode => Object.hash(go, push, dropReason);

  @override
  String toString() => 'PushNavigation(go: $go, push: $push, drop: $dropReason)';
}

/// The routes behind `EntitlementGate`: opened on top of Home, and only for an entitled account.
const _gatedRoutes = {'/palm', '/face', '/chat', '/kundali', '/profile'};

/// Pure: [payload] and the signed-in [user] in, a navigation out.
///
/// The rules, in order:
///  - no allowed route, or no user: nothing happens (a push for a signed-out account is stale);
///  - `/leaving` always opens — it is ungated because the person it asks has usually just lost access;
///  - `/subscribe` only for an account that is not entitled;
///  - `/birth` only while onboarding still wants the birth details;
///  - everything else needs onboarding finished and entitlement, and opens over Home.
PushNavigation resolvePushNavigation(PushPayload payload, {required AppUser? user}) {
  final route = payload.route;
  if (route == null) return const PushNavigation(dropReason: 'unknown_route');
  if (user == null) return const PushNavigation(dropReason: 'signed_out');

  final onboarding = destinationForUser(user).route;

  switch (route) {
    case Routes.leaving:
      final id = payload.notificationId;
      return PushNavigation(go: id == null ? Routes.leaving : '${Routes.leaving}?nid=${Uri.encodeQueryComponent(id)}');

    case Routes.subscribe:
      return user.entitled
          ? const PushNavigation(go: Routes.home, dropReason: 'already_entitled')
          : const PushNavigation(go: Routes.subscribe);

    case Routes.birth:
      return onboarding == Routes.birth
          ? const PushNavigation(go: Routes.birth)
          : PushNavigation(go: onboarding, dropReason: 'no_longer_needed');

    case Routes.home:
      return PushNavigation(go: onboarding, dropReason: onboarding == Routes.home ? null : 'onboarding');

    default:
      if (!_gatedRoutes.contains(route)) return const PushNavigation(dropReason: 'unknown_route');
      if (onboarding != Routes.home) {
        return PushNavigation(go: onboarding, dropReason: user.entitled ? 'onboarding' : 'not_entitled');
      }
      return PushNavigation(go: Routes.home, push: route);
  }
}

/// Takes tapped pushes to their screens.
///
/// A push that launched the app waits for the splash to resolve the session — navigating before it
/// would race the splash's own `go` and lose. One that arrives while the app is running is handled
/// at once. Watched by [AstrolokApp] so it listens for the life of the app.
class PushNavigator {
  PushNavigator(this._ref);

  final Ref _ref;
  StreamSubscription<RemoteMessage>? _subscription;
  bool _ready = false;
  PushPayload? _pending;

  void attach() {
    _subscription ??= pushMessaging.opened.listen((message) => handle(PushPayload.fromData(message.data)));
  }

  /// Called by the splash once it has routed. Hands over whatever launched the app.
  void onSplashResolved() {
    if (_ready) return;
    _ready = true;
    final initial = pushMessaging.takeInitialMessage();
    final pending = initial == null ? _pending : PushPayload.fromData(initial.data);
    _pending = null;
    if (pending != null) handle(pending);
  }

  /// Routes a push — from a tap on the system notification, or on the in-app banner.
  void handle(PushPayload payload) {
    if (!_ready) {
      _pending = payload;
      return;
    }

    final user = _ref.read(entitlementProvider);
    final navigation = resolvePushNavigation(payload, user: user);

    if (payload.campaign != null || payload.notificationId != null) {
      analyticsSession.attributePush(campaign: payload.campaign, notificationId: payload.notificationId);
    }

    // No kundali refresh here on purpose. `/kundali` opens KundaliGateView, which forces one as its
    // first act; firing a second from here put two identical status calls in flight against a
    // session that was still resolving, and whichever lost the race reported knowing nothing.

    if (navigation.dropReason != null) {
      analytics.track(Ev.pushDropped, {
        P.dropReason: navigation.dropReason,
        P.campaign: ?payload.campaign,
        P.notificationId: ?payload.notificationId,
        P.route: ?payload.route,
      });
    } else {
      analytics.track(Ev.pushRouted, {
        P.route: payload.route,
        P.campaign: ?payload.campaign,
        P.notificationId: ?payload.notificationId,
      });
    }

    final go = navigation.go;
    if (go != null) appRouter.go(go);
    final push = navigation.push;
    if (push != null) appRouter.push(push);
  }

  void dispose() => _subscription?.cancel();
}

final pushNavigatorProvider = Provider<PushNavigator>((ref) {
  final navigator = PushNavigator(ref)..attach();
  ref.onDispose(navigator.dispose);
  return navigator;
});
