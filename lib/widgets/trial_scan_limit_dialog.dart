import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';
import 'primary_button.dart';

/// Every word the trial popup says.
abstract final class TrialScanCopy {
  static const title = 'Trial scan used';
  static const dismiss = 'OK';

  static String bodyFor(int limit) {
    final times = limit == 1 ? 'only once' : 'only $limit times';
    return 'Trial users can scan their palm and face $times each. '
        'Please wait for your trial period to finish to scan again.';
  }

  static String endsOn(DateTime at) => 'Your trial ends on ${_format(at)}.';

  /// `15 Sep, 3:00 PM`, in the device's time zone — [AppUser.trialEndsAt] is already local.
  static String _format(DateTime at) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute.toString().padLeft(2, '0');
    final period = at.hour < 12 ? 'AM' : 'PM';
    return '${at.day} ${months[at.month - 1]}, $hour:$minute $period';
  }
}

/// Tells a trial user their palm or face reading is spent, and when that changes.
///
/// A dialog rather than the capture screen's standing notice, because it is the answer to a tap:
/// the user asked for a reading and has to be told why they are not getting one before anything
/// else happens.
///
/// Pure UI. `showTrialScanLimit` in `lib/app/trial_scan_guard.dart` fills in [limit] and
/// [trialEndsAt] from the data layer and reports the event.
Future<void> showTrialScanLimitDialog(
  BuildContext context, {
  required int limit,
  DateTime? trialEndsAt,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppShape.card),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppShape.featureDisc,
              height: AppShape.featureDisc,
              decoration: const BoxDecoration(
                color: AppColors.goldWash,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.hourglass_top_rounded,
                size: 26,
                color: AppColors.goldDeep,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              TrialScanCopy.title,
              style: AppText.sheetTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              TrialScanCopy.bodyFor(limit),
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
            if (trialEndsAt != null) ...[
              const SizedBox(height: 8),
              Text(
                TrialScanCopy.endsOn(trialEndsAt),
                style: AppText.meta,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 22),
            // In the column rather than in dialog actions: the button is full-width by design, and
            // an action bar lays its children out at intrinsic width.
            PrimaryButton(
              label: TrialScanCopy.dismiss,
              tone: ButtonTone.navy,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}
