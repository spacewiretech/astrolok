/// Push-notification registration.
///
/// Narrow on purpose, and every method must swallow its own failures: registration runs in the
/// background on launch and on every resume, and a device that cannot be notified is never a
/// reason for anything the user is doing to fail.
abstract interface class PushRepository {
  /// Stores this device's FCM [token] against the signed-in account and its session.
  ///
  /// [platform] is `android` or `ios`. Returns whether the backend accepted it — false with no
  /// session, when the call failed, and on a tier with no backend at all — so the caller tries
  /// again next time rather than remembering a registration that never happened.
  Future<bool> register({required String token, required String platform});
}

/// The implementation used wherever there is no backend to talk to.
///
/// The Fast2SMS and fake tiers have no `users` table for a token to belong to. Answering "not
/// registered" rather than throwing keeps push walkable on a fresh checkout: the permission prompt
/// still appears and the token is still fetched, and nothing is stored.
class NoopPushRepository implements PushRepository {
  const NoopPushRepository();

  @override
  Future<bool> register({required String token, required String platform}) async => false;
}
