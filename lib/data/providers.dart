import 'package:camera/camera.dart' show CameraLensDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/env.dart';
import 'camera/reading_camera.dart';
import 'cashfree/cashfree_checkout.dart';
import 'cashfree/upi_app_preference.dart';
import 'fake/fake_astro_chat.dart';
import 'fake/fake_auth_repository.dart';
import 'fake/fake_face_reading.dart';
import 'fake/fake_palm_reading.dart';
import 'fake/fake_session.dart';
import 'fake/fake_subscription_repository.dart';
import 'fast2sms/fast2sms_auth_repository.dart';
import 'fast2sms/fast2sms_client.dart';
import 'local/reading_image_store.dart';
import 'local/reading_store.dart';
import 'repositories/app_config_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/chat_repository.dart';
import 'repositories/face_repository.dart';
import 'repositories/palm_repository.dart';
import 'repositories/subscription_repository.dart';
import 'supabase/edge_functions.dart';
import 'supabase/session_store.dart';
import 'supabase/supabase_app_config_repository.dart';
import 'supabase/supabase_auth_repository.dart';
import 'supabase/supabase_chat_repository.dart';
import 'supabase/supabase_face_repository.dart';
import 'supabase/supabase_palm_repository.dart';
import 'supabase/supabase_subscription_repository.dart';
import 'tts/reading_speech.dart';

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

// ---------------------------------------------------------------- palm reading

/// Reads a palm photograph, through the Edge Function that holds the Gemini key.
///
/// Same `Env.hasSupabase` rule as the two above: there is no direct-to-Gemini rung, because
/// that would mean shipping the key inside the app, and the fake is a canned reading so the
/// four screens stay walkable on a checkout that has never been pointed at a project.
final palmRepositoryProvider = Provider<PalmRepository>((ref) {
  if (Env.hasSupabase) {
    return SupabasePalmRepository(
      SupabaseEdgeFunctions(Supabase.instance.client),
      ref.watch(sessionStoreProvider),
    );
  }

  debugPrint('[palm] Supabase is not configured; readings are canned.');
  return const FakePalmRepository();
});

/// The live camera, back-facing. autoDispose so leaving the capture screen releases the
/// hardware — a held camera keeps the indicator light on and blocks other apps.
final palmCameraProvider = Provider.autoDispose<ReadingCamera>((ref) {
  final camera = DeviceCamera();
  ref.onDispose(camera.dispose);
  return camera;
});

/// The captured photographs, on the device only.
final palmImageStoreProvider =
    Provider<ReadingImageStore>((ref) => ReadingImageStore('palm'));

/// The recent readings, so a result survives a cold start.
final palmReadingStoreProvider =
    Provider<PalmReadingStore>((ref) => const PalmReadingStore());

// ---------------------------------------------------------------- face reading

/// Reads a face photograph, through the Edge Function that holds the Gemini key.
///
/// Same rule and same reasons as [palmRepositoryProvider].
final faceRepositoryProvider = Provider<FaceRepository>((ref) {
  if (Env.hasSupabase) {
    return SupabaseFaceRepository(
      SupabaseEdgeFunctions(Supabase.instance.client),
      ref.watch(sessionStoreProvider),
    );
  }

  debugPrint('[face] Supabase is not configured; readings are canned.');
  return const FakeFaceRepository();
});

/// The live camera, front-facing — the whole difference from [palmCameraProvider].
///
/// A separate provider rather than a parameter on one, so that leaving either capture screen
/// disposes only its own controller. Two `autoDispose` families keyed by lens would achieve the
/// same thing with more ceremony.
final faceCameraProvider = Provider.autoDispose<ReadingCamera>((ref) {
  final camera = DeviceCamera(lens: CameraLensDirection.front);
  ref.onDispose(camera.dispose);
  return camera;
});

/// Its own directory, so signing out of one feature's images cannot take the other's, and so
/// palm and face each keep ten photos rather than ten between them.
final faceImageStoreProvider =
    Provider<ReadingImageStore>((ref) => ReadingImageStore('face'));

final faceReadingStoreProvider =
    Provider<FaceReadingStore>((ref) => const FaceReadingStore());

// ---------------------------------------------------------------- astro chat

/// Talks to Astro, through the Edge Functions that hold the Gemini key.
///
/// Same rule and same reasons as the two reading repositories: no direct-to-Gemini rung, because
/// that would mean shipping the key inside the app.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  if (Env.hasSupabase) {
    return SupabaseChatRepository(
      SupabaseEdgeFunctions(Supabase.instance.client),
      ref.watch(sessionStoreProvider),
    );
  }

  debugPrint('[chat] Supabase is not configured; Astro is scripted.');
  return FakeChatRepository();
});

/// The conversation, cached so a cold start paints before the network answers.
final chatThreadStoreProvider =
    Provider<ChatThreadStore>((ref) => const ChatThreadStore());

// ---------------------------------------------------------------- narration

/// Reads a reading aloud. One instance app-wide, shared by both features: two would talk over
/// each other, and a palm reading left playing while a face reading starts is a bug the user
/// hears rather than sees.
final readingSpeechProvider = Provider<ReadingSpeech>((ref) {
  final speech = ReadingSpeech();
  ref.onDispose(speech.dispose);
  return speech;
});
