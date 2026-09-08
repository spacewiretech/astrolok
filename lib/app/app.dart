import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class AstrolokApp extends ConsumerWidget {
  const AstrolokApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Kept alive for the life of the app, not read for a value: this is what starts Mixpanel on
    // a first launch, where boot found no cached token to start it with.
    ref.watch(analyticsBootstrapProvider);

    return MaterialApp.router(
      title: 'Astrolok',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: appRouter,
    );
  }
}
