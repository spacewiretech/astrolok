import '../models/app_user.dart';

/// In-memory stand-in for the Supabase tables, shared by every fake repository so the screens
/// stay consistent with one another for the length of a run.
///
/// Nothing here survives a restart — that is deliberate, it keeps the onboarding flow walkable
/// on every launch.
class FakeSession {
  FakeSession._();

  static final instance = FakeSession._();

  AppUser? user;

  /// Simulated network latency, so loading states are exercised rather than skipped.
  static Future<void> latency([int ms = 400]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  void reset() {
    user = null;
  }
}
