import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/env.dart';
import 'cashfree/cashfree_checkout.dart';
import 'cashfree/upi_app_preference.dart';
import 'fake/fake_auth_repository.dart';
import 'fake/fake_session.dart';
import 'fake/fake_subscription_repository.dart';
import 'fast2sms/fast2sms_auth_repository.dart';
import 'fast2sms/fast2sms_client.dart';
import 'repositories/app_config_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/subscription_repository.dart';
import 'supabase/edge_functions.dart';
import 'supabase/session_store.dart';
import 'supabase/supabase_app_config_repository.dart';
import 'supabase/supabase_auth_repository.dart';
import 'supabase/supabase_subscription_repository.dart';

/// The whole data layer is bound here. No ViewModel or view imports a concrete repository, so
/// swapping an implementation is an edit to the right-hand side of one provider.

final fakeSessionProvider = Provider<FakeSession>((ref) => FakeSession.instance);

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

/// Runtime config, served from `app_config` and cached on disk.
final appConfigRepositoryProvider = Provider<AppConfigRepository>((ref) {
  if (!Env.hasSupabase) return const FakeAppConfigRepository();
  return SupabaseAppConfigRepository(Supabase.instance.client);
});

/// Resolved once and read wherever a limit or a price label is needed.
final appConfigProvider = FutureProvider<Map<String, String>>(
  (ref) => ref.watch(appConfigRepositoryProvider).load(),
);

/// Three rungs, best first, so the app is walkable at every level of configuration:
///
/// 1. Supabase — OTP proxied through Edge Functions, users persisted, Fast2SMS key off-device.
/// 2. Fast2SMS direct — real SMS, but nothing is stored and the key ships in the app.
/// 3. Fake — in-memory, any 6-digit code.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final session = ref.watch(fakeSessionProvider);

  if (Env.hasSupabase) {
    return SupabaseAuthRepository(
      SupabaseEdgeFunctions(Supabase.instance.client),
      ref.watch(sessionStoreProvider),
    );
  }

  if (!Env.isConfigured) {
    debugPrint(
      '[auth] Using FakeAuthRepository — ${Env.configurationSummary} '
      'Any ${Fast2SmsClient.otpLength}-digit code will be accepted.',
    );
    return FakeAuthRepository(session);
  }

  debugPrint(
    '[auth] Supabase is not configured; calling Fast2SMS directly. '
    'The API key is shipping inside the app on this path.',
  );
  final client = Fast2SmsClient(
    apiKey: Env.fast2smsApiKey,
    otpId: Env.fast2smsOtpId,
  );
  ref.onDispose(client.dispose);
  return Fast2SmsAuthRepository(client, session);
});

/// The real payment path whenever Supabase is configured — mirroring [authRepositoryProvider].
///
/// This binding is the whole difference between a paywall that charges and one that only looks
/// like it does, so it deliberately follows the same `Env.hasSupabase` rule as auth rather than
/// having a flag of its own that could be left pointing at the fake.
final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  if (Env.hasSupabase) {
    return SupabaseSubscriptionRepository(
      SupabaseEdgeFunctions(Supabase.instance.client),
      ref.watch(sessionStoreProvider),
      ref.watch(appConfigRepositoryProvider),
    );
  }

  debugPrint('[subscription] Supabase is not configured; the paywall will not charge anything.');
  return FakeSubscriptionRepository(ref.watch(fakeSessionProvider));
});

/// The Cashfree SDK, or a stand-in that reports success without opening a UPI app.
final cashfreeCheckoutProvider = Provider<CashfreeCheckout>((ref) {
  if (Env.hasSupabase) return SdkCashfreeCheckout();
  return const FakeCashfreeCheckout();
});

/// Which UPI app the paywall opens on. Cosmetic, so it is not in the secure store.
final upiAppPreferenceProvider = Provider<UpiAppPreference>(
  (ref) => const UpiAppPreference(),
);
