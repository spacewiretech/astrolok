import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/models/astro_message.dart';
import '../../widgets/app_snackbar.dart';
import 'chat_copy.dart';
import 'chat_threads_viewmodel.dart';

/// Every conversation, and the way to start another.
///
/// A drawer rather than a screen: switching conversations is something people do mid-thought, and
/// making them leave the one they are in to do it would cost the thought. It opens from the right
/// so the back button keeps the left corner it has on every other screen in this app.
class ChatDrawer extends ConsumerWidget {
  const ChatDrawer({
    super.key,
    required this.selectedId,
    required this.onNewChat,
    required this.onOpen,
  });

  /// The conversation currently on screen, or [ChatThread.draftId] for an unsent one.
  final String selectedId;

  final VoidCallback onNewChat;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(chatThreadsProvider);

    return Drawer(
      backgroundColor: AppColors.homeCream,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Heading(),
            _NewChatButton(onTap: onNewChat),

            Expanded(
              child: threads.when(
                // Barely reachable: the list is warmed on Home and kept, so this is a first run
                // with nothing cached, opened before that first fetch has landed.
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                ),
                // The list failing is not worth an error screen: "New chat" above still works,
                // which is the thing people came here to do most of the time.
                error: (_, _) => const _Empty(),
                data: (rows) => rows.isEmpty
                    ? const _Empty()
                    : _ThreadList(
                        threads: rows,
                        selectedId: selectedId,
                        onOpen: onOpen,
                      ),
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),
            const _MemoryLink(),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Text(ChatCopy.conversations, style: AppText.section),
    );
  }
}

class _NewChatButton extends StatelessWidget {
  const _NewChatButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Material(
        color: AppColors.goldWash,
        borderRadius: AppShape.pill,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.of(context).pop();
            onTap();
          },
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: AppShape.pill,
              border: Border.all(color: AppColors.gold),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(
              children: [
                const Icon(Icons.add_rounded, size: 20, color: AppColors.goldDeep),
                const SizedBox(width: 10),
                Text(
                  ChatCopy.newChat,
                  style: AppText.title.copyWith(fontSize: 15, color: AppColors.navy),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        ChatCopy.threadsEmpty,
        style: AppText.meta.copyWith(color: AppColors.muted),
      ),
    );
  }
}

/// The conversations, under their date headings.
///
/// Pull to re-sync. Nothing else here reaches the server: opening the drawer shows the list the
/// app already has, and this is the one gesture that asks whether another device has changed it.
class _ThreadList extends ConsumerWidget {
  const _ThreadList({
    required this.threads,
    required this.selectedId,
    required this.onOpen,
  });

  final List<ChatThreadSummary> threads;
  final String selectedId;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = groupThreads(threads, now: DateTime.now());

    return RefreshIndicator(
      color: AppColors.goldDeep,
      backgroundColor: AppColors.surface,
      onRefresh: () => ref.read(chatThreadsProvider.notifier).refresh(),
      child: ListView(
        // Two conversations do not fill the drawer, and a list that cannot scroll cannot be
        // pulled — which would leave the gesture working only for people who already have plenty.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Text(
                _label(entry.key),
                style: AppText.tileLabel.copyWith(
                  color: AppColors.muted,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            for (final thread in entry.value)
              _ThreadRow(
                thread: thread,
                selected: thread.id == selectedId,
                onOpen: () => onOpen(thread.id),
              ),
          ],
        ],
      ),
    );
  }

  static String _label(ChatAge age) => switch (age) {
        ChatAge.today => ChatCopy.ageToday,
        ChatAge.yesterday => ChatCopy.ageYesterday,
        ChatAge.week => ChatCopy.ageWeek,
        ChatAge.older => ChatCopy.ageOlder,
      };
}

class _ThreadRow extends ConsumerWidget {
  const _ThreadRow({
    required this.thread,
    required this.selected,
    required this.onOpen,
  });

  final ChatThreadSummary thread;
  final bool selected;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = thread.title.isEmpty ? ChatCopy.untitledThread : thread.title;

    return Material(
      color: selected ? AppColors.goldWash : Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          onOpen();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 11, 8, 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.title.copyWith(
                        fontSize: 15,
                        color: AppColors.navy,
                      ),
                    ),
                    if (thread.preview.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        thread.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.meta.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ],
                ),
              ),
              _RowMenu(thread: thread),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ThreadAction { rename, delete }

class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.thread});

  final ChatThreadSummary thread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_ThreadAction>(
      icon: const Icon(Icons.more_horiz_rounded, size: 20, color: AppColors.muted),
      tooltip: '',
      // Popped straight away for either action: both open something modal of their own, and a
      // menu left hanging over a dialog is how a drawer ends up with two overlays on it.
      onSelected: (action) => switch (action) {
        _ThreadAction.rename => _rename(context, ref),
        _ThreadAction.delete => _delete(context, ref),
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _ThreadAction.rename,
          child: Text(ChatCopy.renameThread, style: AppText.body),
        ),
        PopupMenuItem(
          value: _ThreadAction.delete,
          child: Text(
            ChatCopy.deleteThread,
            style: AppText.body.copyWith(color: AppColors.danger),
          ),
        ),
      ],
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: thread.title);

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(ChatCopy.renameThreadTitle, style: AppText.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.body,
          textInputAction: TextInputAction.done,
          maxLength: 80,
          onSubmitted: (value) => Navigator.of(context).pop(value),
          decoration: InputDecoration(
            hintText: ChatCopy.renameThreadHint,
            hintStyle: AppText.body.copyWith(color: AppColors.muted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              ChatCopy.deleteThreadDismiss,
              style: AppText.meta.copyWith(color: AppColors.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(
              ChatCopy.renameThreadConfirm,
              style: AppText.meta.copyWith(color: AppColors.goldDeep),
            ),
          ),
        ],
      ),
    );

    controller.dispose();
    if (name == null || name.trim().isEmpty) return;

    await ref.read(chatThreadsProvider.notifier).rename(thread.id, name);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(ChatCopy.deleteThreadTitle, style: AppText.title),
        content: Text(ChatCopy.deleteThreadBody, style: AppText.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              ChatCopy.deleteThreadDismiss,
              style: AppText.meta.copyWith(color: AppColors.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              ChatCopy.deleteThreadConfirm,
              style: AppText.meta.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final removed = await ref.read(chatThreadsProvider.notifier).remove(thread.id);
    if (removed || !context.mounted) return;

    showAppSnackBar(context, ChatCopy.deleteThreadFailed, error: true);
  }
}

/// What Astro remembers, which is not per-conversation and so belongs here rather than in any
/// one of them.
class _MemoryLink extends StatelessWidget {
  const _MemoryLink();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          context.push(Routes.memory);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_outlined, size: 19, color: AppColors.goldDeep),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ChatCopy.memoryHeading,
                  style: AppText.title.copyWith(fontSize: 14, color: AppColors.navy),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
