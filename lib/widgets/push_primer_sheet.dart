import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';
import '../data/analytics/analytics.dart';
import '../data/analytics/analytics_events.dart';
import '../data/firebase/push_messaging.dart';
import 'primary_button.dart';
/// Explains what notifications are for before the system asks, then asks.
///
/// The system prompt can be shown once; a user who has just been told why is far more likely to say
/// yes than one ambushed by it. The consent line says plainly that offers are included and that
/// they can be turned off in Profile — both Play and the App Store expect marketing pushes to be
/// opted into, not implied.
///
/// Returns whether notifications ended up allowed. Shows nothing, and returns false, when the OS
/// would not show its prompt anyway.

Future<bool> showPushPrimer(BuildContext context, {required String source}) async {
  if (!await pushMessaging.canPrompt()) return false;
  if (!context.mounted) return false;

  analytics.track(Ev.pushPrimerShown, {P.source: source});

  final allow = await showModalBottomSheet<bool>(
    context: context,
    routeSettings: const RouteSettings(name: 'push-primer'),
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
    isScrollControlled: true,
    builder: (context) => const _PrimerSheet(),
  );

  analytics.track(Ev.pushPrimerAnswered, {P.source: source, P.choice: allow == true ? 'allow' : 'not_now'});
  if (allow != true) return false;
  return pushMessaging.requestFromPrimer(source: source);
}

class _PrimerSheet extends StatelessWidget {
  const _PrimerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppShape.gutter, 24, AppShape.gutter, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.goldWash),
                child: const Icon(Icons.notifications_active_outlined, color: AppColors.gold, size: 32),
              ),
            ),
            const SizedBox(height: 16),
            Text('Never miss what the stars say', style: AppText.sheetTitle.copyWith(fontSize: 22), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            for (final (icon, text) in const [
              (Icons.auto_awesome_mosaic_outlined, 'Know the moment your Kundali is revealed'),
              (Icons.back_hand_outlined, 'Gentle reminders for readings you have not tried'),
              (Icons.chat_bubble_outline_rounded, 'Guidance from Astro when the time is right'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(icon, color: AppColors.goldDeep, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text, style: AppText.body)),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'Includes reading reminders and offers. Turn them off anytime in Profile.',
              style: AppText.legal,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Allow notifications',
              analyticsId: 'push_primer_allow',
              pill: true,
              onPressed: () => Navigator.pop(context, true),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Not now', style: AppText.meta),
            ),
          ],
        ),
      ),
    );
  }
}
