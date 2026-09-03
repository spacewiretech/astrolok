import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../widgets/date_wheel.dart';
import '../../widgets/primary_button.dart';
import 'birth_viewmodel.dart';

/// Collects the date of birth every reading is calculated from.
///
/// UNSKINNED: structure and behaviour are final, visuals are placeholders until the design
/// exports land.
class BirthView extends ConsumerWidget {
  const BirthView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(birthViewModelProvider);
    final model = ref.read(birthViewModelProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppShape.gutter, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('When were you born?', style: AppText.display),
              const SizedBox(height: 6),
              Text(
                'Your birth date is what every reading is calculated from.',
                style: AppText.meta,
              ),
              const SizedBox(height: 32),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: DateWheel(
                        label: 'Day',
                        // Rebuilt when the month changes so 30 February is never offered.
                        values: [for (var d = 1; d <= state.daysInMonth; d++) d],
                        selected: state.day,
                        labelFor: (d) => '$d',
                        onSelected: model.setDay,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DateWheel(
                        label: 'Month',
                        values: [for (var m = 1; m <= 12; m++) m],
                        selected: state.month,
                        labelFor: (m) => BirthState.monthNames[m - 1],
                        onSelected: model.setMonth,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DateWheel(
                        label: 'Year',
                        // Newest first: most users are scrolling back a couple of decades, not
                        // forward from 1900.
                        values: [
                          for (var y = BirthState.maxYear; y >= BirthState.minYear; y--) y,
                        ],
                        selected: state.year,
                        labelFor: (y) => '$y',
                        onSelected: model.setYear,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  state.error!,
                  style: AppText.meta.copyWith(color: AppColors.danger),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Continue',
                busy: state.busy,
                onPressed: state.canSave ? () => _save(context, ref) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final next = await ref.read(birthViewModelProvider.notifier).save();
    if (!context.mounted || next == null) return;
    context.go(next.route);
  }
}
