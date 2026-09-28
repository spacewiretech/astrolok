import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_typography.dart';
import '../../widgets/brand_logo.dart';
import 'chat_copy.dart';
import 'chat_palette.dart';

/// What the ⋮ menu offers.
enum ChatMenuAction { conversations, newChat }

/// The green bar across the top: back, Astro's picture and name, and "online" or "typing…".
///
/// Exactly where WhatsApp puts the same things, because that is where everyone already looks to
/// see whether the other side is writing back.
class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({
    super.key,
    required this.typing,
    required this.onBack,
    required this.onMenu,
  });

  final bool typing;
  final VoidCallback onBack;
  final ValueChanged<ChatMenuAction> onMenu;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final muted = AppText.body.copyWith(
      fontSize: 13,
      height: 1.1,
      color: ChatPalette.onAppBarMuted,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light icons over the green, as WhatsApp's status bar has them.
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: ChatPalette.appBar),
      child: Material(
        color: ChatPalette.appBar,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: preferredSize.height,
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const Icon(Icons.arrow_back_rounded, color: ChatPalette.onAppBar),
                ),
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const BrandMark(size: 32),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ChatCopy.astroName,
                        style: AppText.title.copyWith(
                          fontSize: 17,
                          height: 1.2,
                          color: ChatPalette.onAppBar,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          typing ? ChatCopy.typing : ChatCopy.online,
                          key: ValueKey(typing),
                          style: typing ? muted.copyWith(fontStyle: FontStyle.italic) : muted,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<ChatMenuAction>(
                  tooltip: ChatCopy.menu,
                  icon: const Icon(Icons.more_vert_rounded, color: ChatPalette.onAppBar),
                  onSelected: onMenu,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: ChatMenuAction.conversations,
                      child: Text(ChatCopy.openConversations),
                    ),
                    PopupMenuItem(value: ChatMenuAction.newChat, child: Text(ChatCopy.newChat)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
