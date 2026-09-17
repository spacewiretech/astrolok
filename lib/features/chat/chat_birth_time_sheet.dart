import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../widgets/date_wheel.dart';
import '../../widgets/primary_button.dart';
import 'chat_copy.dart';

/// Asks for the hour of birth, and hands back what to send: a sentence with the time in it, or
/// [ChatCopy.birthTimeUnknown]. Null when the sheet is closed without an answer.
///
/// Replaces a clock dialog that opened on 9:00 AM. That dialog never said which time it wanted,
/// so a great many people tapped OK on the preset — and a birth time promoted onto the user row is
/// never overwritten by a later one, so each of those is the wrong nakshatra for good. This sheet
/// has no preset at all: nothing can be confirmed until the user has said which part of the day
/// they were born in, and the button reads back the exact time it is about to send.
///
/// [source] is where it was opened from — `reply` or `composer` — and only feeds analytics.
Future<String?> askBirthTime(BuildContext context, {required String source}) async {
  analytics.track(Ev.chatBirthTimeOpened, {P.source: source});
  FocusScope.of(context).unfocus();

  final answer = await showModalBottomSheet<_Answer>(
    context: context,
    routeSettings: const RouteSettings(name: 'chat-birth-time'),
    // Taller than the default nine-sixteenths cap: the wheels must fit under the chips.
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
    builder: (context) => const _BirthTimeSheet(),
  );
  if (answer == null) return null;

  final time = answer.time;
  analytics.track(Ev.chatBirthTimeChosen, {
    P.source: source,
    P.unknown: time == null,
    P.partOfDay: time == null ? null : _PartOfDay.of(time.hour).wire,
    P.adjusted: time == null ? null : answer.adjusted,
  });

  return time == null ? ChatCopy.birthTimeUnknown : birthTimeSentence(time);
}

/// "6:45 PM". A birth time is read by a person, not a clock.
String formatBirthClock(TimeOfDay time) {
  final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  final minute = time.minute.toString().padLeft(2, '0');
  final period = time.period == DayPeriod.am ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

/// The time as the user's own words.
///
/// Sent as a sentence rather than as a form value: it becomes a turn in the transcript, and
/// "07:30" sitting in a navy bubble would read as a machine talking. The server picks the time
/// back out of the sentence.
///
/// With AM or PM, never as a bare "11:55". The server no longer guesses which half of the day an
/// unmarked hour means — guessing morning is how someone born at 11:55 at night got the wrong
/// chart — so an unmarked time would only be asked about all over again.
String birthTimeSentence(TimeOfDay time) => 'I was born at ${formatBirthClock(time)}.';

/// What the sheet was answered with. A null [time] is "I don't know".
class _Answer {
  const _Answer({this.time, this.adjusted = false});

  final TimeOfDay? time;

  /// Whether the wheels were moved after the part of the day was picked.
  final bool adjusted;
}

/// The six chips. Four-hour windows, because that is how people remember a birth they were told
/// about — "early morning", "late at night" — long before they remember a minute.
enum _PartOfDay {
  earlyMorning('🌄', ChatCopy.partEarlyMorning, ChatCopy.partEarlyMorningRange, 4, 'early_morning'),
  morning('☀️', ChatCopy.partMorning, ChatCopy.partMorningRange, 8, 'morning'),
  afternoon('🌤️', ChatCopy.partAfternoon, ChatCopy.partAfternoonRange, 12, 'afternoon'),
  evening('🌇', ChatCopy.partEvening, ChatCopy.partEveningRange, 16, 'evening'),
  night('🌙', ChatCopy.partNight, ChatCopy.partNightRange, 20, 'night'),
  afterMidnight('✨', ChatCopy.partAfterMidnight, ChatCopy.partAfterMidnightRange, 0, 'after_midnight');

  const _PartOfDay(this.emoji, this.label, this.range, this.start, this.wire);

  final String emoji;
  final String label;
  final String range;

  /// The first hour of the window, on a 24-hour clock. Where the wheels land when it is tapped.
  final int start;

  final String wire;

  /// The window a 24-hour [hour] falls in, so the highlight follows the wheels across a boundary.
  static _PartOfDay of(int hour) => switch (hour) {
        < 4 => afterMidnight,
        < 8 => earlyMorning,
        < 12 => morning,
        < 16 => afternoon,
        < 20 => evening,
        _ => night,
      };
}

class _BirthTimeSheet extends StatefulWidget {
  const _BirthTimeSheet();

  @override
  State<_BirthTimeSheet> createState() => _BirthTimeSheetState();
}

class _BirthTimeSheetState extends State<_BirthTimeSheet> {
  /// 0–23, or null until a part of the day is picked. Null on purpose: a starting time is a time
  /// someone can confirm without ever choosing it.
  int? _hour;
  int _minute = 0;
  bool _adjusted = false;

  final _wheels = GlobalKey();

  void _pickPart(_PartOfDay part) {
    setState(() {
      _hour = part.start;
      _minute = 0;
      _adjusted = false;
    });
  }

  /// From the wheels. They also report the value they were just jumped to when a chip moves them,
  /// which is not the user adjusting anything — hence the no-change check.
  void _set(int hour, int minute) {
    if (hour == _hour && minute == _minute) return;
    setState(() {
      _hour = hour;
      _minute = minute;
      _adjusted = true;
    });
  }

  /// Once the wheels have opened, scrolls them into view on a phone too short to show the whole
  /// sheet — otherwise the chip tap looks like it did nothing.
  ///
  /// After the frame, not straight from `onEnd`: that fires from the animation's ticker, before
  /// the sheet is laid out at its final height, so the scroll extent it would measure is still
  /// the closed one and the wheels would stop short of the fold.
  void _showWheels() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _wheels.currentContext;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  static String _pad(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final hour = _hour;
    final chosen = hour == null ? null : TimeOfDay(hour: hour, minute: _minute);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppShape.gutter, 22, AppShape.gutter, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Only the question scrolls. The button stays in reach on the smallest phone, because
            // it is also what reads the chosen time back.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The diya shares the title's line: on a small phone a line of its own is
                    // the difference between the last row of chips showing and not.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const ExcludeSemantics(
                          child: Text('🪔', style: TextStyle(fontSize: 22)),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            ChatCopy.timeSheetTitle,
                            style: AppText.section,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ChatCopy.timeSheetWhy,
                      style: AppText.meta.copyWith(height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    const _WhereToLook(),
                    const SizedBox(height: 18),
                    Text(ChatCopy.timeSheetStepDay, style: AppText.title.copyWith(fontSize: 15)),
                    const SizedBox(height: 10),
                    _PartsOfDay(
                      selected: hour == null ? null : _PartOfDay.of(hour),
                      onPick: _pickPart,
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      onEnd: _showWheels,
                      child: hour == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              key: _wheels,
                              padding: const EdgeInsets.only(top: 18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    ChatCopy.timeSheetStepExact,
                                    style: AppText.title.copyWith(fontSize: 15),
                                  ),
                                  const SizedBox(height: 10),
                                  _wheelCard(hour),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              label: chosen == null
                  ? ChatCopy.timeSheetPickFirst
                  : ChatCopy.timeSheetConfirm(formatBirthClock(chosen)),
              // The label carries the time, so it cannot be the id.
              analyticsId: 'chat_birth_time_confirm',
              tone: ButtonTone.navy,
              pill: true,
              onPressed: chosen == null
                  ? null
                  : () => Navigator.pop(context, _Answer(time: chosen, adjusted: _adjusted)),
            ),
            // Not knowing is a real answer, and the sage is told to read on without it. Without
            // this the only way past the question is to invent one.
            TextButton(
              onPressed: () => Navigator.pop(context, const _Answer()),
              child: Text(
                ChatCopy.timeSheetUnknown,
                style: AppText.meta.copyWith(color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wheelCard(int hour) {
    final pm = hour >= 12;
    final hourOfPeriod = hour % 12;

    return DatePickerCard(
      height: 120,
      columns: [
        DateWheelColumn<int>(
          label: ChatCopy.timeSheetHour,
          values: [for (var h = 1; h <= 12; h++) h],
          selected: hourOfPeriod == 0 ? 12 : hourOfPeriod,
          labelFor: (h) => '$h',
          onSelected: (h) => _set(h % 12 + (pm ? 12 : 0), _minute),
        ),
        DateWheelColumn<int>(
          label: ChatCopy.timeSheetMinute,
          values: [for (var m = 0; m < 60; m++) m],
          selected: _minute,
          labelFor: _pad,
          onSelected: (m) => _set(hour, m),
        ),
        DateWheelColumn<DayPeriod>(
          label: ChatCopy.timeSheetPeriod,
          values: DayPeriod.values,
          selected: pm ? DayPeriod.pm : DayPeriod.am,
          labelFor: (p) => p == DayPeriod.am ? 'AM' : 'PM',
          onSelected: (p) => _set(hourOfPeriod + (p == DayPeriod.pm ? 12 : 0), _minute),
        ),
      ],
    );
  }
}

/// Where the time is written down. Most people have never looked, and knowing where to look is
/// the difference between an answer and a guess.
class _WhereToLook extends StatelessWidget {
  const _WhereToLook();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.cardSoft,
        borderRadius: AppShape.control,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(child: Text('📜', style: TextStyle(fontSize: 16))),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ChatCopy.timeSheetWhere,
              style: AppText.meta.copyWith(color: AppColors.body, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two columns of three, rather than a wrap: the labels are different lengths, and chips that
/// size to their words make a ragged grid that reads as a list of tags.
class _PartsOfDay extends StatelessWidget {
  const _PartsOfDay({required this.selected, required this.onPick});

  final _PartOfDay? selected;
  final ValueChanged<_PartOfDay> onPick;

  @override
  Widget build(BuildContext context) {
    const parts = _PartOfDay.values;

    return Column(
      children: [
        for (var row = 0; row < parts.length; row += 2) ...[
          if (row > 0) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _chip(parts[row])),
              const SizedBox(width: 8),
              Expanded(child: _chip(parts[row + 1])),
            ],
          ),
        ],
      ],
    );
  }

  Widget _chip(_PartOfDay part) {
    final isSelected = part == selected;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${part.label}, ${part.range}',
      excludeSemantics: true,
      child: Material(
        color: isSelected ? AppColors.goldWash : AppColors.surface,
        borderRadius: AppShape.control,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onPick(part),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: AppShape.control,
              border: Border.all(
                color: isSelected ? AppColors.gold : AppColors.border,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
            child: Row(
              children: [
                Text(part.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        part.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.meta.copyWith(
                          fontSize: 13,
                          color: AppColors.navy,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        part.range,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.meta.copyWith(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
