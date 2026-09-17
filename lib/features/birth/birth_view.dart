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
import '../../widgets/phone_field.dart';
import '../../widgets/primary_button.dart';
import 'birth_viewmodel.dart';

/// Collects the name and the date of birth every reading is calculated from.
///
/// One screen, after payment: the paywall is reached on nothing but a phone number and a
/// language, and what the readings need is asked once the account is paid for.
class BirthView extends ConsumerStatefulWidget {
  const BirthView({super.key});

  @override
  ConsumerState<BirthView> createState() => _BirthViewState();
}

class _BirthViewState extends ConsumerState<BirthView> {
  final _name = TextEditingController();

  /// Zero-padded, as the design draws them — `06`, not `6`.
  static String _pad(int value) => value.toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    // Seeded from state rather than the other way round, so a name the account already has is
    // on screen from the first frame.
    _name.text = ref.read(birthViewModelProvider).name;
    _name.addListener(() => ref.read(birthViewModelProvider.notifier).setName(_name.text));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                // Scrolls rather than overflows. The logo, the copy, a name field and a 220pt
                // picker come to more than a 360x640 phone has once its insets are taken out, and
                // the keyboard takes half of what is left. The button stays pinned below, so a
                // tall screen looks unchanged.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 20),
                        const Center(child: BrandLogo(size: 44)),
                        const SizedBox(height: 36),
                        Text(
                          'Tell us about yourself',
                          style: AppText.display,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Your name and date of birth personalise every reading.',
                          style: AppText.body,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        Text('Your name', style: AppText.title),
                        const SizedBox(height: 10),
                        TextFieldBox(
                          controller: _name,
                          hint: 'Enter your name',
                          keyboardType: TextInputType.name,
                          // Not focused on arrival: the keyboard would sit over the date wheels,
                          // which are the half of this screen that cannot be typed into.
                          autofocus: false,
                          onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        ),
                        const SizedBox(height: 24),
                        Text('Date of birth', style: AppText.title),
                        const SizedBox(height: 10),
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
                  onPressed: state.canSave ? _save : null,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final next = await ref.read(birthViewModelProvider.notifier).save();
    if (!mounted || next == null) return;
    context.go(next.route);
  }
}
