import 'package:camera/camera.dart' show CameraLensDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../app/env.dart';
import 'analytics/analytics.dart';
import 'analytics/analytics_events.dart';
import 'analytics/facebook_analytics.dart';
import 'analytics/mixpanel_analytics.dart';
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
import 'media/promo_video_source.dart';
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

// ---------------------------------------------------------------- analytics

/// Where events go.
///
/// Defaults to the no-op so tests and any build that never ran `bootMobileApp` behave exactly as
/// they did before analytics existed. Boot overrides it with the same instance installed in the
/// global holder, so the two can never disagree about which sink is live.
final analyticsProvider = Provider<Analytics>((ref) => const NoopAnalytics());

/// Starts Mixpanel once the fetched config arrives, and stamps the environment onto every event.
///
/// Watched by [AstrolokApp] so it runs for the life of the app. It is a no-op whenever boot
/// already started Mixpanel from the cached config — which is every launch after the first — but
/// it is what covers the first launch on a device, where there was no cache to read.
final analyticsBootstrapProvider = FutureProvider<void>((ref) async {
  var config = await ref.watch(appConfigProvider.future);

  final analytics = ref.read(analyticsProvider);
  analytics.registerSuper({
    P.env: config.configString('env'),
    P.backendMode: backendMode,
  });

  // A row added to `app_config` after this install last cached is invisible for the whole
  // six-hour TTL, because a fresh cache is served without asking the server at all. That is
  // correct for a value that changed and wrong for a key that did not exist yet: on the day
  // `mixpanel_token` was added, every already-installed app ran blind until its cache aged out.
  //
  // The test is *absence*, not emptiness. A missing key means this cache predates the row; a
  // present-but-blank one is someone having deliberately cleared it, and re-fetching on every
  // launch to rediscover that would make the off switch cost a request per launch.
  if (!config.containsKey(mixpanelTokenKey) || !config.containsKey(facebookAppIdKey)) {
    try {
      config = await ref.read(appConfigRepositoryProvider).load(force: true);
    } catch (error) {
      debugPrint('[analytics] forced config refresh failed: $error');
    }
  }

  // Resolved through [analyticsSink] rather than a direct `is` test, because the installed sink
  // is a [MultiAnalytics] fan-out and a plain `analytics is MixpanelAnalytics` would now be false
  // — silently leaving Mixpanel unstarted on exactly the first launch this provider exists to
  // cover. The helper looks inside the fan-out, and still copes with a bare sink in tests.
  final mixpanel = analyticsSink<MixpanelAnalytics>(analytics);
  if (mixpanel != null) await mixpanel.start(config[mixpanelTokenKey]);

  final facebook = analyticsSink<FacebookAnalytics>(analytics);
  if (facebook != null) await startFacebook(facebook, config);
});

/// Which rung of the repository ladder below is live.
///
/// On every event, because without it a developer running against the fakes — where any code
/// signs in and the paywall charges nothing — pollutes the same funnels as production traffic.
String get backendMode {
  if (Env.hasSupabase) return BackendMode.supabase;
  if (Env.isConfigured) return BackendMode.fast2sms;
  return BackendMode.fake;
}

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

/// The paywall's promo clip, opened long before the paywall is reached.
///
/// Warmed from the onboarding phone sheet, so the whole of onboarding and the birth date are
/// lead time and the paywall paints a playing frame on its first build rather than a spinner.
/// See [PromoVideoSource] for what "opened" costs and why it is worth moving.
///
/// Deliberately **not** `autoDispose`, for the same reason as `chatThreadsProvider`: the screen
/// that starts this is torn down four routes before the screen that uses it.
///
/// [PromoVideoSource.close] is registered before the first await, so config re-emitting with a
/// different URL tears the old player down before the new one is built.
final promoVideoProvider = FutureProvider<VideoPlayerController?>((ref) async {
  final source = PromoVideoSource();
  ref.onDispose(source.close);
  final config = await ref.watch(appConfigProvider.future);
  return source.open(config.configString('paywall_video_url'));
});

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
