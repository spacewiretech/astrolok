import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/entitlement.dart';

/// The signed-in, paid-for home.
///
/// PLACEHOLDER: the real layout comes from the home frame in Track B, and the palm reading and
/// astro talk screens land after that. What is here proves the gate lets an entitled user
/// through and shows the billing warning when one is due.
class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(entitlementProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppShape.gutter, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user?.hasName ?? false ? 'Hello, ${user!.name}' : 'Hello',
                style: AppText.display,
              ),
              const SizedBox(height: 4),
              if (user?.inTrial ?? false) Text('You are on your trial.', style: AppText.meta),

              // A warning, never a gate: the user is still fully entitled here, and this is the
              // only notice they get while there is still time to fix the mandate.
              if (user?.billingState != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cardSoft,
                    borderRadius: AppShape.card,
                  ),
                  child: Text(user!.billingState!.message, style: AppText.meta),
                ),
              ],

              const Spacer(),
              Center(child: Text('Home — coming in Track B', style: AppText.meta)),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
