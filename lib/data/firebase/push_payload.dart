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

  /// The question a drip push wants waiting in the chat composer, or null.
  ///
  /// The server writes it as `params.q`, already in the reader's own language, because it lands in
  /// the transcript as their words. It is data from outside the app, so it is treated as such:
  /// control characters out, blanks and anything past 200 characters refused. A push that fails
  /// these opens chat empty, which is what every build before this one did anyway.
  String? get chatQuestion {
    final raw = params['q'];
    if (raw is! String) return null;
    final cleaned = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim();
    if (cleaned.isEmpty || cleaned.length > 200) return null;
    return cleaned;
  }

  /// Whether that question should send itself on arrival, from `params.autosend`.
  ///
  /// Off unless the server explicitly says `"1"`. Sending costs a Gemini call and starts a thread the
  /// user did not ask for, six times a day — so an absent, malformed or unrecognised value must mean
  /// "put it in the composer", never "send it".
  bool get chatAutoSend => params['autosend'] == '1';

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
