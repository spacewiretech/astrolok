import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/assets.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../widgets/astral_background.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/circle_icon_button.dart';
import '../../widgets/date_wheel.dart';
import '../../widgets/place_search_field.dart';
import '../../widgets/primary_button.dart';
import 'kundali_copy.dart';
import 'kundali_form_state.dart';
import 'kundali_form_viewmodel.dart';

/// "Your Kundali": date, time and place of birth, then Generate.
class KundaliFormView extends ConsumerWidget {
  const KundaliFormView({super.key, this.edit = false});

  final bool edit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(kundaliFormViewModelProvider(edit));
    final model = ref.read(kundaliFormViewModelProvider(edit).notifier);

    return Scaffold(
      body: AstralBackground(
        surface: AstralSurface.onboarding,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppShape.gutter, 8, AppShape.gutter, 0),
                child: Row(
                  children: [
                    CircleIconButton(
                      image: PalmIcon.backCircle,
                      icon: Icons.chevron_left_rounded,
                      semanticLabel: 'Back',
                      onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppShape.gutter, 12, AppShape.gutter, 24),
                  children: [
                    const AccentHeading(lead: KundaliCopy.formTitleLead, accent: KundaliCopy.formTitleAccent),
                    const SizedBox(height: 10),
                    Text(KundaliCopy.formSubtitle, style: AppText.body, textAlign: TextAlign.center),
                    const SizedBox(height: 28),
                    _FieldCard(
                      icon: Icons.calendar_month_outlined,
                      title: KundaliCopy.dobTitle,
                      child: _ValueBox(
                        value: state.birthDate == null ? null : _formatDate(state.birthDate!),
                        hint: KundaliCopy.dobHint,
                        semanticLabel: KundaliCopy.pickDob,
                        onTap: state.busy ? null : () => _pickDate(context, state, model),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _FieldCard(
                      icon: Icons.access_time_rounded,
                      title: KundaliCopy.timeTitle,
                      help: KundaliCopy.timeHelp,
                      child: _ValueBox(
                        value: state.birthTime == null ? null : _formatTime(state.birthTime!),
                        hint: KundaliCopy.timeHint,
                        semanticLabel: KundaliCopy.timeTitle,
                        onTap: state.busy ? null : () => _pickTime(context, state, model),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _FieldCard(
                      icon: Icons.location_on_outlined,
                      title: KundaliCopy.placeTitle,
                      child: PlaceSearchField(
                        hint: KundaliCopy.placeHint,
                        selectedLabel: state.place?.label,
                        enabled: !state.busy,
                        unavailableMessage: state.placeSearchEnabled ? null : KundaliCopy.placeUnavailable,
                        search: model.searchPlaces,
                        onChosen: model.choosePlace,
                        onCleared: model.clearPlace,
                      ),
                    ),
                    if (state.error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        state.error!,
                        style: AppText.meta.copyWith(color: AppColors.danger),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppShape.gutter, 4, AppShape.gutter, 16),
                child: PrimaryButton(
                  label: state.isEdit && state.changesExisting ? KundaliCopy.update : KundaliCopy.generate,
                  analyticsId: 'kundali_generate',
                  tone: ButtonTone.navy,
                  pill: true,
                  busy: state.busy,
                  onPressed: state.canSubmit ? () => _submit(context, ref, state) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context, WidgetRef ref, KundaliFormState state) async {
    FocusScope.of(context).unfocus();
    if (state.changesExisting) {
      final confirmed = await showDialog<bool>(
        context: context,
        routeSettings: const RouteSettings(name: 'kundali-recast'),
        builder: (context) => AlertDialog(
          title: Text(KundaliCopy.regenerateTitle, style: AppText.section),
          content: Text(KundaliCopy.regenerateBody(state.existing?.regenerationsLeft ?? 0), style: AppText.body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(KundaliCopy.cancel)),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text(KundaliCopy.regenerateConfirm)),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final next = await ref.read(kundaliFormViewModelProvider(edit).notifier).submit();
    if (next != null && context.mounted) context.go(next);
  }

  Future<void> _pickDate(BuildContext context, KundaliFormState state, KundaliFormViewModel model) async {
    FocusScope.of(context).unfocus();
    final today = DateTime.now();
    final initial = state.birthDate ?? DateTime(2000);
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      routeSettings: const RouteSettings(name: 'kundali-dob'),
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      builder: (context) => _DateSheet(initial: initial, latest: today),
    );
    if (picked != null) model.setBirthDate(picked);
  }

  Future<void> _pickTime(BuildContext context, KundaliFormState state, KundaliFormViewModel model) async {
    FocusScope.of(context).unfocus();
    final parts = state.birthTime?.split(':');
    final picked = await showTimePicker(
      context: context,
      routeSettings: const RouteSettings(name: 'kundali-time'),
      helpText: KundaliCopy.timeTitle,
      initialTime: parts == null
          ? const TimeOfDay(hour: 6, minute: 0)
          : TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked != null) {
      model.setBirthTime('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  static String _formatTime(String hhmm) {
    final parts = hhmm.split(':');
    final hour = int.parse(parts[0]);
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:${parts[1]} ${hour < 12 ? 'AM' : 'PM'}';
  }
}

/// A white card with the gold icon disc on the left, as the design draws each field.
class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.icon, required this.title, required this.child, this.help});

  final IconData icon;
  final String title;
  final Widget child;
  final String? help;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.card,
        boxShadow: const [AppColors.floatingShadow],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.goldWash),
            child: Icon(icon, color: AppColors.gold, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: AppText.title),
                const SizedBox(height: 10),
                child,
                if (help != null) ...[
                  const SizedBox(height: 8),
                  Text(help!, style: AppText.legal),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueBox extends StatelessWidget {
  const _ValueBox({required this.value, required this.hint, required this.onTap, required this.semanticLabel});

  final String? value;
  final String hint;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      value: value,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppShape.control,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            borderRadius: AppShape.control,
            border: Border.all(color: AppColors.fieldBorder),
          ),
          child: Text(
            value ?? hint,
            style: AppText.input.copyWith(fontSize: 16, color: value == null ? AppColors.muted : AppColors.navy),
          ),
        ),
      ),
    );
  }
}

class _DateSheet extends StatefulWidget {
  const _DateSheet({required this.initial, required this.latest});

  final DateTime initial;
  final DateTime latest;

  @override
  State<_DateSheet> createState() => _DateSheetState();
}

class _DateSheetState extends State<_DateSheet> {
  static const _firstYear = 1900;
  late int _day = widget.initial.day;
  late int _month = widget.initial.month;
  late int _year = widget.initial.year;

  int get _daysInMonth => DateTime(_year, _month + 1, 0).day;

  static String _pad(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final day = _day > _daysInMonth ? _daysInMonth : _day;
    final chosen = DateTime(_year, _month, day);
    final future = chosen.isAfter(widget.latest);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppShape.gutter, 20, AppShape.gutter, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(KundaliCopy.pickDob, style: AppText.section, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            DatePickerCard(
              columns: [
                DateWheelColumn<int>(
                  label: 'Date',
                  values: [for (var d = 1; d <= _daysInMonth; d++) d],
                  selected: day,
                  labelFor: _pad,
                  onSelected: (v) => setState(() => _day = v),
                ),
                DateWheelColumn<int>(
                  label: 'Month',
                  values: [for (var m = 1; m <= 12; m++) m],
                  selected: _month,
                  labelFor: _pad,
                  onSelected: (v) => setState(() => _month = v),
                ),
                DateWheelColumn<int>(
                  label: 'Year',
                  values: [for (var y = _firstYear; y <= widget.latest.year; y++) y],
                  selected: _year,
                  labelFor: (y) => '$y',
                  onSelected: (v) => setState(() => _year = v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: KundaliCopy.done,
              analyticsId: 'kundali_dob_done',
              tone: ButtonTone.navy,
              pill: true,
              onPressed: future ? null : () => Navigator.pop(context, chosen),
            ),
          ],
        ),
      ),
    );
  }
}
