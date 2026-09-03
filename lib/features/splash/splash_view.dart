import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import 'splash_viewmodel.dart';

/// Resolves the stored session and routes.
///
/// UNSKINNED: the logo and artwork land with the design exports.
class SplashView extends ConsumerWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(splashDestinationProvider, (_, next) {
      final destination = next.valueOrNull;
      if (destination != null && context.mounted) context.go(destination.route);
    });

    return Scaffold(
      backgroundColor: AppColors.night,
      body: Center(
        child: Text(
          'Astrolok',
          style: AppText.display.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
