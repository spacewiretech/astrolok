import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/app.dart';
import '../app/env.dart';

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

  runApp(const ProviderScope(child: AstrolokApp()));
}
