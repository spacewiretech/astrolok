import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/push_navigation.dart';
import '../../app/router.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/brand_logo.dart';
import 'splash_viewmodel.dart';

/// Resolves the stored session and routes.
class SplashView extends ConsumerWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(splashDestinationProvider, (_, next) {
      final destination = next.valueOrNull;
      if (destination != null && context.mounted) {
        context.go(destination.route);
        // After the splash's own navigation has landed, so a push that launched the app routes on
        // top of it rather than racing it.
        WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(pushNavigatorProvider).onSplashResolved());
      }
    });

    return const Scaffold(
      body: AstralBackground(
        surface: AstralSurface.onboarding,
        child: Center(child: BrandLogo(size: 64)),
      ),
    );
  }
}
