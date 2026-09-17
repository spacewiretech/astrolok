import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/firebase/push_messaging.dart';
import '../data/kundali_summary.dart';
import '../data/providers.dart';
import '../widgets/push_banner.dart';
import 'push_navigation.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class AstrolokApp extends ConsumerWidget {
  const AstrolokApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Kept alive for the life of the app, not read for a value: this is what starts Mixpanel on
    // a first launch, where boot found no cached token to start it with.
    ref.watch(analyticsBootstrapProvider);

    // Likewise, and for the mirror-image reason: boot works out where this install came from but
    // has no session to report it with, so the sending half waits until the repositories exist.
    ref.watch(attributionBootstrapProvider);

    // And push, for the same reason again: the device token is registered against a session, so it
    // waits for the repositories rather than for boot.
    ref.watch(pushBootstrapProvider);

    // Routes tapped pushes. Held for the life of the app, so a tap that arrives while it runs is
    // never dropped for want of a listener.
    final pushNavigator = ref.watch(pushNavigatorProvider);

    return MaterialApp.router(
      title: 'Astrolok',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: appRouter,
      builder: (context, child) => PushBannerHost(
        messages: pushMessaging.received,
        onTap: pushNavigator.handle,
        onReceived: (payload) {
          if (payload.route == Routes.kundali) {
            ref.read(kundaliSummaryProvider.notifier).refresh(force: true);
          }
        },
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
