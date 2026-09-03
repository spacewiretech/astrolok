import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/date_wheel.dart';
import '../../widgets/primary_button.dart';
import 'birth_viewmodel.dart';

/// Collects the date of birth every reading is calculated from.
class BirthView extends ConsumerWidget {
  const BirthView({super.key});

  /// Zero-padded, as the design draws them — `06`, not `6`.
  static String _pad(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(birthViewModelProvider);
    final model = ref.read(birthViewModelProvider.notifier);

    return Scaffold(
      body: AstralBackground(
        surface: AstralSurface.onboarding,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppShape.gutter),
            child: Column(
              children: [
                // Scrolls rather than overflows. The logo, two blocks of copy and a 220pt
                // picker come to more than a 360x640 phone has once its insets are taken out —
                // this screen overflowed by 65 pixels there before the content was made
                // scrollable. The button stays pinned below, so a tall screen looks unchanged.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        const BrandLogo(size: 44),
                        const SizedBox(height: 36),
                        Text(
                          'Set Your Date of Birth',
                          style: AppText.display,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Enter your date of birth to discover your personalized insights.',
                          style: AppText.body,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        DatePickerCard(
                          columns: [
                            DateWheelColumn<int>(
                              label: 'Date',
                              // Rebuilt when the month changes so 30 February is never offered.
                              values: [for (var d = 1; d <= state.daysInMonth; d++) d],
                              selected: state.day,
                              labelFor: _pad,
                              onSelected: model.setDay,
                            ),
                            DateWheelColumn<int>(
                              label: 'Month',
                              values: [for (var m = 1; m <= 12; m++) m],
                              selected: state.month,
                              labelFor: _pad,
                              onSelected: model.setMonth,
                            ),
                            DateWheelColumn<int>(
                              label: 'Year',
                              // Ascending, as drawn: 2012 above 2013 above 2014.
                              values: [
                                for (var y = BirthState.minYear;
                                    y <= BirthState.maxYear;
                                    y++)
                                  y,
                              ],
                              selected: state.year,
                              labelFor: (y) => '$y',
                              onSelected: model.setYear,
                            ),
                          ],
                        ),
                        if (state.error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            state.error!,
                            style: AppText.meta.copyWith(color: AppColors.danger),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                PrimaryButton(
                  label: 'continue',
                  busy: state.busy,
                  onPressed: state.canSave ? () => _save(context, ref) : null,
                ),
                const SizedBox(height: 20),
              ],
            ),
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
