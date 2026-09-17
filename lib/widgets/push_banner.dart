import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';
import '../data/firebase/push_payload.dart';

/// Shows a push that arrived while the app was open, as a banner across the top.
///
/// The OS shows nothing for a foreground push, and a system-style heads-up drawn by a plugin would
/// look like it came from somewhere else. This is on-brand, and a tap goes through the same routing
/// as a tap on the real notification.
class PushBannerHost extends StatefulWidget {
  const PushBannerHost({super.key, required this.child, required this.messages, required this.onTap, this.onReceived});

  final Widget child;
  final Stream<RemoteMessage> messages;
  final void Function(PushPayload payload) onTap;

  /// Every received push, shown or not — the kundali summary refreshes on `kundali_ready`.
  final void Function(PushPayload payload)? onReceived;

  @override
  State<PushBannerHost> createState() => _PushBannerHostState();
}

class _PushBannerHostState extends State<PushBannerHost> {
  StreamSubscription<RemoteMessage>? _subscription;
  Timer? _hide;
  RemoteMessage? _message;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.messages.listen(_show);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  void _show(RemoteMessage message) {
    widget.onReceived?.call(PushPayload.fromData(message.data));
    final notification = message.notification;
    if (notification == null || (notification.title ?? notification.body ?? '').isEmpty) return;

    _hide?.cancel();
    setState(() {
      _message = message;
      _visible = true;
    });
    _hide = Timer(const Duration(seconds: 6), _dismiss);
  }

  void _dismiss() {
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    final top = MediaQuery.paddingOf(context).top + 8;

    return Stack(
      children: [
        widget.child,
        if (message != null)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            left: 12,
            right: 12,
            top: _visible ? top : -160,
            child: Material(
              color: Colors.transparent,
              child: Dismissible(
                key: ValueKey(message.messageId),
                direction: DismissDirection.up,
                onDismissed: (_) => _dismiss(),
                child: InkWell(
                  borderRadius: AppShape.card,
                  onTap: () {
                    _dismiss();
                    widget.onTap(PushPayload.fromData(message.data));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppShape.card,
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
                      boxShadow: const [
                        BoxShadow(color: Color(0x33000C2B), blurRadius: 24, offset: Offset(0, 8)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.goldWash),
                          child: const Icon(Icons.auto_awesome, color: AppColors.gold, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if ((message.notification?.title ?? '').isNotEmpty)
                                Text(message.notification!.title!, style: AppText.title.copyWith(fontSize: 15)),
                              if ((message.notification?.body ?? '').isNotEmpty)
                                Text(
                                  message.notification!.body!,
                                  style: AppText.meta.copyWith(fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
