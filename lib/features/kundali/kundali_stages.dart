import '../../data/models/kundali.dart';
import '../../widgets/stage_checklist.dart';
import 'kundali_copy.dart';

/// The waiting screen's checklist for [summary] at [deviceNow].
///
/// Pure, so the one rule that matters is tested: the last stage — the reading — is only ever shown
/// done when the server says the reading is ready. The first three follow the clock; this one
/// follows the truth.
List<StageItem> kundaliStageItems(KundaliSummary summary, DateTime deviceNow) {
  final current = summary.currentStage(deviceNow);
  final titles = {
    'positions': KundaliCopy.stagePositions,
    'lagna': KundaliCopy.stageLagna,
    'dasha': KundaliCopy.stageDasha,
    'insights': KundaliCopy.stageInsights,
  };

  final stages = summary.stages.isEmpty
      ? const ['positions', 'lagna', 'dasha', 'insights']
      : [for (final stage in summary.stages) stage.key];

  return [
    for (var i = 0; i < stages.length; i++)
      StageItem(
        title: titles[stages[i]] ?? stages[i],
        status: i < current
            ? StageStatus.done
            : i == current && summary.state != KundaliState.failed
                ? StageStatus.active
                : StageStatus.pending,
        detail: KundaliCopy.stageActiveDetail,
      ),
  ];
}

/// "14h 22m", "22m 05s", "45s" — coarse when far off, to the second when close.
String formatRemaining(Duration left) {
  if (left <= Duration.zero) return '0s';
  final hours = left.inHours;
  final minutes = left.inMinutes.remainder(60);
  final seconds = left.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  if (hours > 0) return '${hours}h ${two(minutes)}m';
  if (minutes > 0) return '${minutes}m ${two(seconds)}s';
  return '${seconds}s';
}

/// The countdown, to the second, for the big number on the waiting screen.
String formatCountdown(Duration left) {
  if (left <= Duration.zero) return '00 : 00 : 00';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(left.inHours)} : ${two(left.inMinutes.remainder(60))} : ${two(left.inSeconds.remainder(60))}';
}

/// "today at 9:41 PM", "tomorrow at 9:41 AM", or "on 21 Sep at 9:41 AM", in the device's zone.
String formatReveal(DateTime unlockAt, DateTime deviceNow) {
  final local = unlockAt.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final clock = '$hour:${local.minute.toString().padLeft(2, '0')} ${local.hour < 12 ? 'AM' : 'PM'}';
  final today = DateTime(deviceNow.year, deviceNow.month, deviceNow.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'today at $clock';
  if (diff == 1) return 'tomorrow at $clock';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return 'on ${local.day} ${months[local.month - 1]} at $clock';
}
