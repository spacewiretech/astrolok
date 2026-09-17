import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The routes a push may open. Must match `PUSH_ROUTES` in `_shared/notification_campaigns.ts`.
///
/// An allowlist rather than "whatever the payload says": a push is data from outside the app, and a
/// route that is not on this list is dropped on tap rather than navigated to.
const kPushRoutes = <String>{
  '/home',
  '/palm',
  '/face',
  '/chat',
  '/kundali',
  '/subscribe',
  '/birth',
  '/leaving',
  '/profile',
};

/// What the backend puts in a push's data: `route`, `campaign`, `notification_id`, `params`.
@immutable
class PushPayload {
  const PushPayload({this.route, this.campaign, this.notificationId, this.params = const {}});

  /// Null when the push carried no route, or one this build does not allow.
  final String? route;
  final String? campaign;
  final String? notificationId;
  final Map<String, Object?> params;

  bool get routable => route != null;

  static PushPayload fromData(Map<String, dynamic> data) {
    final route = data['route'];
    Map<String, Object?> params = const {};
    final raw = data['params'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) params = decoded.cast<String, Object?>();
      } catch (_) {
        // Malformed params cost the params, not the push.
      }
    }
    String? text(Object? value) => value is String && value.isNotEmpty ? value : null;

    return PushPayload(
      route: route is String && kPushRoutes.contains(route) ? route : null,
      campaign: text(data['campaign']),
      notificationId: text(data['notification_id']),
      params: params,
    );
  }
}
