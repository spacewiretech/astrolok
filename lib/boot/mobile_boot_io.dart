
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/analytics_observer.dart';
import '../app/app.dart';
import '../app/env.dart';
import '../data/analytics/analytics.dart';
import '../data/analytics/analytics_context.dart';
import '../data/analytics/analytics_events.dart';
import '../data/analytics/analytics_session.dart';
import '../data/analytics/facebook_analytics.dart';
import '../data/analytics/mixpanel_analytics.dart';
import '../data/providers.dart';
import '../data/repositories/app_config_repository.dart';
import '../data/supabase/supabase_app_config_repository.dart';

/// The phone app's real entry point, lifted out of `main()` so that the web build never
/// imports the app tree. See `mobile_boot.dart` for why that has to be a compile-time split.
Future<void> bootMobileApp() async {
  await Env.load();

  if (Env.hasSupabase) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseAnonKey,
        // Supabase Auth is unused — phone verification runs through Fast2SMS and the Edge
        // Functions issue their own opaque session tokens, so there is no JWT to refresh.
        authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      );
    } catch (error) {
      // A misconfigured project must not be a crash on launch: without Supabase the providers
      // fall back to the Fast2SMS or fake tier and the app is still walkable.
      debugPrint('Supabase init failed, continuing without it: $error');
    }
  }

  // After Supabase, because the cached-token read below wants the client to exist where it can;
  // before runApp, because the first events are launch events.
  final analytics = await _startAnalytics();

  runApp(
    ProviderScope(
      // The same instance the global holder has, so the router observer, the shared widgets and
      // the ViewModels can never end up talking to two different sinks.
      overrides: [analyticsProvider.overrideWithValue(analytics)],
      child: const AstrolokApp(),
    ),
  );
}

/// Brings analytics up as far as it can get before the first frame.
///
/// Never throws and never blocks on the network. The token lives in the `app_config` table, so
/// the most this can do at boot is read the cache that [SupabaseAppConfigRepository] already
/// keeps on disk; a first launch finds nothing there and Mixpanel is started later by
/// [analyticsBootstrapProvider], with the launch events buffered in the meantime.
Future<Analytics> _startAnalytics() async {
  final mixpanel = MixpanelAnalytics();
  final facebook = FacebookAnalytics();

  // Two sinks with very different appetites behind one interface: Mixpanel answers product
  // questions and takes everything, Facebook trains an ad optimiser and takes four conversions.
  // The fan-out is what keeps that a property of the sinks rather than of every call site.
  final analytics = MultiAnalytics([mixpanel, facebook]);

  // Installed before anything is tracked, and before the token is known, because the buffer is
  // what makes an unstarted sink useful rather than lossy.
  installAnalytics(analytics);
  mixpanel.context = () => {
        ...analyticsObserver.contextProperties(),
        ...analyticsSession.contextProperties(),
      };
  analytics.registerSuper({P.backendMode: backendMode});

  // The single place device, locale, version and install context is gathered. Awaited before the
  // token so that even the very first buffered event — `App Launched` — already carries it.
  await analyticsContext.collect(analytics);

  try {
    final cached = await SupabaseAppConfigRepository.readCachedConfig();
    await mixpanel.start(cached?[mixpanelTokenKey]);
    await startFacebook(facebook, cached ?? const {});
  } catch (error) {
    debugPrint('[analytics] could not read the cached config: $error');
  }

  _reportUncaughtErrors();
  await analyticsSession.attach(screensViewed: () => analyticsObserver.screensViewed);

  return analytics;
}

/// Routes uncaught errors to Mixpanel as well as to the console.
///
/// There is no crash reporter in this app, so without this a crash is invisible the moment the
/// user is not attached to a debugger. `App Crashed` is not a substitute for one — it has no
/// symbolication and no grouping — but it does answer the question that matters most for a
/// funnel: whether the users who dropped out of a flow dropped out because it crashed.
///
/// Both handlers chain to whatever was installed before them, so the framework still prints the
/// error to the console and any future crash reporter still sees it.
void _reportUncaughtErrors() {
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousFlutterError?.call(details);
    analytics.track(Ev.appCrashed, {
      P.error: details.exceptionAsString(),
      P.stackHead: _stackHead(details.stack),
      // A Flutter framework error is usually recoverable — a bad layout, a failed image — and
      // the app carries on. Counting those as fatal would drown the ones that are.
      P.fatal: false,
    });
  };

  final previousPlatformError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    analytics.track(Ev.appCrashed, {
      P.error: error.toString(),
      P.stackHead: _stackHead(stack),
      P.fatal: true,
    });
    // Flush now: an error that reached here may well be about to take the isolate down, and a
    // queued crash report that never leaves the device is no report at all.
    analytics.flush();
    return previousPlatformError?.call(error, stack) ?? false;
  };
}

/// The first three frames of a stack, which is enough to tell two crashes apart without
/// shipping a whole trace as an event property.
String? _stackHead(StackTrace? stack) {
  if (stack == null) return null;
  final frames = stack.toString().trim().split('\n');
  if (frames.isEmpty) return null;
  return frames.take(3).map((frame) => frame.trim()).join(' | ');
}
