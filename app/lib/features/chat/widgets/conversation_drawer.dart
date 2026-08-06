import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/chrome/golem_alert.dart';
import '../../../core/chrome/golem_button.dart';
import '../../../core/chrome/golem_menu.dart';
import '../../../core/chrome/golem_sheet.dart';
import '../../../core/domain/app_state.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';

class ConversationDrawer extends ConsumerStatefulWidget {
  const ConversationDrawer({
    required this.chat,
    required this.search,
    required this.blocked,
    required this.close,
    super.key,
  });
  final ChatState chat;
  final TextEditingController search;
  final bool blocked;
  final VoidCallback close;

  @override
  ConsumerState<ConversationDrawer> createState() => _ConversationDrawerState();
}

class _ConversationDrawerState extends ConsumerState<ConversationDrawer> {
  String query = '';

  @override
  void initState() {
    super.initState();
    widget.search.addListener(_update);
  }

  void _update() =>
      setState(() => query = widget.search.text.trim().toLowerCase());

  @override
  void dispose() {
    widget.search.removeListener(_update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = widget.chat.conversations
        .where((item) => item.title.toLowerCase().contains(query))
        .toList();
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: GolemTheme.accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    CupertinoIcons.circle_grid_hex_fill,
                    color: CupertinoColors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Text(
                  'Golem',
                  style: TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: CupertinoButton(
              key: const Key('new-chat-drawer'),
              color: GolemTheme.accent,
              borderRadius: BorderRadius.circular(26),
              minimumSize: const Size.fromHeight(52),
              onPressed: widget.blocked
                  ? null
                  : () {
                      ref.read(chatControllerProvider.notifier).newChat();
                      widget.close();
                    },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.add, color: CupertinoColors.white),
                  SizedBox(width: 8),
                  Text(
                    'New chat',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.chat.conversations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: SizedBox(
                height: 48,
                child: CupertinoSearchTextField(
                  key: const Key('drawer-search'),
                  controller: widget.search,
                  placeholder: 'Search chats',
                  backgroundColor: CupertinoColors.white.withValues(
                    alpha: 0.08,
                  ),
                  style: const TextStyle(color: CupertinoColors.white),
                  placeholderStyle: const TextStyle(
                    color: GolemTheme.mutedOnDark,
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              widget.chat.conversations.isEmpty ? 24 : 14,
              20,
              8,
            ),
            child: const Text(
              'RECENT',
              style: TextStyle(
                color: GolemTheme.faintOnDark,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Expanded(
            child: widget.chat.conversations.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Your conversations will appear here.',
                      style: TextStyle(
                        color: GolemTheme.mutedOnDark,
                        fontSize: 15,
                      ),
                    ),
                  )
                : conversations.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'No chats match your search.',
                      style: TextStyle(
                        color: GolemTheme.mutedOnDark,
                        fontSize: 15,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final item = conversations[index];
                      final selected = item.id == widget.chat.activeId;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 3),
                        decoration: BoxDecoration(
                          color: selected
                              ? CupertinoColors.white.withValues(alpha: 0.09)
                              : null,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Stack(
                          children: [
                            if (selected)
                              Positioned(
                                left: 0,
                                top: 8,
                                bottom: 8,
                                child: Container(
                                  width: 4,
                                  decoration: BoxDecoration(
                                    color: GolemTheme.accent,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            Row(
                              children: [
                                Expanded(
                                  child: CupertinoButton(
                                    key: Key('conversation-${item.id}'),
                                    padding: const EdgeInsets.only(
                                      left: 20,
                                      right: 4,
                                    ),
                                    minimumSize: const Size.fromHeight(56),
                                    alignment: Alignment.centerLeft,
                                    onPressed: widget.blocked
                                        ? null
                                        : () {
                                            ref
                                                .read(
                                                  chatControllerProvider
                                                      .notifier,
                                                )
                                                .selectConversation(item.id);
                                            widget.close();
                                          },
                                    child: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: CupertinoColors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                GolemMenu(
                                  anchorKey: Key(
                                    'conversation-menu-${item.id}',
                                  ),
                                  enabled: !widget.blocked,
                                  triggerColor: GolemTheme.mutedOnDark,
                                  triggerSemanticLabel: 'Conversation actions',
                                  items: [
                                    GolemMenuItem(
                                      label: 'Rename',
                                      icon: CupertinoIcons.pencil,
                                      onPressed: () => _rename(context, item),
                                    ),
                                    GolemMenuItem(
                                      label: 'Delete',
                                      icon: CupertinoIcons.trash,
                                      isDestructive: true,
                                      onPressed: () => _delete(context, item),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            height: 1,
            color: CupertinoColors.white.withValues(alpha: 0.1),
          ),
          CupertinoButton(
            key: const Key('open-settings'),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            minimumSize: const Size.fromHeight(56),
            onPressed: () {
              widget.close();
              context.push('/settings');
            },
            child: const Row(
              children: [
                Icon(
                  CupertinoIcons.slider_horizontal_3,
                  color: GolemTheme.iconOnDark,
                  size: 20,
                ),
                SizedBox(width: 14),
                Text(
                  'Model settings',
                  style: TextStyle(color: CupertinoColors.white, fontSize: 17),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    ChatConversation conversation,
  ) async {
    final controller = TextEditingController(text: conversation.title);
    await showGolemSheet<void>(
      context: context,
      sheetKey: const Key('rename-sheet'),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Rename chat', style: GolemText.cardTitle),
              const SizedBox(height: 16),
              CupertinoTextField(
                key: const Key('rename-field'),
                controller: controller,
                autofocus: true,
                clearButtonMode: OverlayVisibilityMode.editing,
                padding: const EdgeInsets.all(14),
              ),
              const SizedBox(height: 16),
              GolemButton.filled(
                key: const Key('rename-save'),
                label: 'Save',
                onPressed: () {
                  ref
                      .read(chatControllerProvider.notifier)
                      .renameConversation(conversation.id, controller.text);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _delete(
    BuildContext context,
    ChatConversation conversation,
  ) async {
    await showGolemAlert(
      context: context,
      title: 'Delete chat?',
      message:
          '“${conversation.title}” and all of its messages will be removed from this device.',
      actions: [
        GolemAlertAction(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        GolemAlertAction(
          key: const Key('confirm-delete'),
          label: 'Delete',
          isDestructive: true,
          onPressed: () {
            ref
                .read(chatControllerProvider.notifier)
                .deleteConversation(conversation.id);
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
