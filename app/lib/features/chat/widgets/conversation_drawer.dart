import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/app_identity.dart';
import '../../../core/chrome/golem_alert.dart';
import '../../../core/chrome/golem_button.dart';
import '../../../core/chrome/golem_chrome.dart';
import '../../../core/chrome/golem_menu.dart';
import '../../../core/chrome/golem_sheet.dart';
import '../../../core/chrome/golem_toast.dart';
import '../../../core/domain/app_state.dart';
import '../../../core/domain/byte_format.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../l10n/bidi.dart';
import '../../../l10n/l10n.dart';
import '../../models/application/model_providers.dart';
import '../../settings/application/storage_providers.dart';
import '../application/chat_providers.dart';
import '../domain/chat_sections.dart';
import '../model_label.dart';

class ConversationDrawer extends ConsumerStatefulWidget {
  const ConversationDrawer({
    required this.chat,
    required this.blocked,
    required this.close,
    super.key,
  });
  final ChatState chat;
  final bool blocked;
  final VoidCallback close;

  @override
  ConsumerState<ConversationDrawer> createState() => _ConversationDrawerState();
}

class _ConversationDrawerState extends ConsumerState<ConversationDrawer> {
  @override
  Widget build(BuildContext context) {
    final sections = groupConversations(
      widget.chat.conversations,
      DateTime.now(),
    );
    // The same one-line claim the nav bar makes, from the same function: two
    // copies of the honesty rule is one copy too many, and this one drifted.
    final modelSubtitle = chatModelSubtitle(
      backend: ref.watch(inferenceBackendProvider),
      catalog: ref.watch(effectiveModelCatalogProvider),
      modelKey: widget.chat.active?.modelKey,
      residentModelKey: ref.watch(residentModelKeyProvider),
      loadableKeys: ref.watch(loadableModelKeysProvider),
      runsModels: ref.watch(
        deviceEligibilityProvider.select((value) => value.runsModels),
      ),
      unsupportedLabel: context.l10n.unsupportedDevice,
      simulatedLabel: context.l10n.simulated,
      onDeviceLabel: context.l10n.onDevice,
    );
    final ink = CupertinoDynamicColor.resolve(GolemTheme.drawerInk, context);
    final faint = CupertinoDynamicColor.resolve(
      GolemTheme.drawerFaintInk,
      context,
    );
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Row(
              children: [
                // The shipped app icon, not the bare mascot: this is the
                // tile carrying the frame, and it already masks its own
                // corners (tool/prepare_launcher.dart).
                Image.asset(
                  AppIdentity.current.iconAsset,
                  width: 42,
                  height: 42,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Golem',
                        style: TextStyle(
                          color: ink,
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.23,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        modelSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GolemText.caption.copyWith(color: faint),
                      ),
                    ],
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
              borderRadius: BorderRadius.circular(GolemRadius.pill),
              minimumSize: const Size.fromHeight(GolemSize.button),
              onPressed: widget.blocked
                  ? null
                  : () {
                      ref.read(chatControllerProvider.notifier).newChat();
                      widget.close();
                    },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.add, color: CupertinoColors.white),
                  SizedBox(width: 8),
                  Text(
                    context.l10n.newChat,
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
            child: CupertinoButton(
              key: const Key('drawer-search-button'),
              padding: EdgeInsets.zero,
              // 46 is the drawn height; the platform floor only ever raises it.
              minimumSize: Size.fromHeight(
                math.max(46, GolemChrome.current.minimumTapTarget),
              ),
              // Gated like the conversation rows: opening a result calls
              // selectConversation, which no-ops mid-generation — search
              // must not offer taps that silently do nothing.
              onPressed: widget.blocked
                  ? null
                  : () {
                      widget.close();
                      context.push('/search');
                    },
              child: Container(
                // A minimum rather than a fixed height: at an accessibility
                // text size the placeholder is taller than 46pt and needs the
                // room to wrap instead of being cropped.
                constraints: const BoxConstraints(minHeight: 46),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.drawerFill,
                    context,
                  ),
                  borderRadius: BorderRadius.circular(GolemRadius.field),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.search, size: 19, color: faint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.l10n.searchChats,
                        style: TextStyle(color: faint, fontSize: 17),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: widget.chat.conversations.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      context.l10n.conversationsAppearHere,
                      style: TextStyle(
                        color: CupertinoDynamicColor.resolve(
                          GolemTheme.drawerMutedInk,
                          context,
                        ),
                        fontSize: 15,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    children: [
                      _section(context, context.l10n.pinned, sections.pinned),
                      _section(context, context.l10n.today, sections.today),
                      _section(
                        context,
                        context.l10n.yesterday,
                        sections.yesterday,
                      ),
                      _section(context, context.l10n.earlier, sections.earlier),
                    ],
                  ),
          ),
          // Inset, not full-bleed: the handoff rules this line to the
          // footer block, which sits 6pt outside the storage row's own
          // gutter rather than running edge to edge across the panel.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              height: 1,
              color: CupertinoDynamicColor.resolve(
                GolemTheme.drawerLine,
                context,
              ),
            ),
          ),
          _StorageMeter(),
          CupertinoButton(
            key: const Key('open-settings'),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            minimumSize: const Size.fromHeight(56),
            onPressed: () {
              widget.close();
              context.push('/settings');
            },
            child: Row(
              children: [
                Icon(CupertinoIcons.slider_horizontal_3, color: ink, size: 21),
                const SizedBox(width: 14),
                Text(
                  context.l10n.settings,
                  style: TextStyle(color: ink, fontSize: 17),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    List<ChatConversation> items,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    final locale = Localizations.localeOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
          child: Text(
            localizedUppercase(title, locale),
            style: localizedLabelStyle(GolemText.overline, locale).copyWith(
              color: CupertinoDynamicColor.resolve(
                GolemTheme.drawerFaintInk,
                context,
              ),
            ),
          ),
        ),
        for (final item in items) _row(context, item),
      ],
    );
  }

  Widget _row(BuildContext context, ChatConversation item) {
    final selected = item.id == widget.chat.activeId;
    final accent = CupertinoDynamicColor.resolve(GolemTheme.accent, context);
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        color: selected
            ? CupertinoDynamicColor.resolve(GolemTheme.drawerSelected, context)
            : null,
        borderRadius: BorderRadius.circular(GolemRadius.field),
      ),
      child: Stack(
        children: [
          if (selected)
            PositionedDirectional(
              start: 0,
              top: 8,
              bottom: 8,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  key: Key('conversation-${item.id}'),
                  padding: const EdgeInsetsDirectional.only(start: 20, end: 4),
                  minimumSize: const Size.fromHeight(52),
                  alignment: AlignmentDirectional.centerStart,
                  onPressed: widget.blocked
                      ? null
                      : () {
                          ref
                              .read(chatControllerProvider.notifier)
                              .selectConversation(item.id);
                          widget.close();
                        },
                  child: Text(
                    item.title.isEmpty ? context.l10n.newChat : item.title,
                    textDirection: item.title.isEmpty
                        ? Directionality.of(context)
                        : contentTextDirection(
                            item.title,
                            fallback: Directionality.of(context),
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.drawerInk,
                        context,
                      ),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              GolemMenu(
                anchorKey: Key('conversation-menu-${item.id}'),
                enabled: !widget.blocked,
                triggerColor: CupertinoDynamicColor.resolve(
                  GolemTheme.drawerMutedInk,
                  context,
                ),
                triggerSemanticLabel: context.l10n.conversationActions,
                items: [
                  GolemMenuItem(
                    itemKey: const Key('menu-pin-toggle'),
                    label: item.pinned
                        ? context.l10n.unpin
                        : context.l10n.pinToTop,
                    icon: item.pinned
                        ? CupertinoIcons.pin_slash
                        : CupertinoIcons.arrow_up_to_line,
                    onPressed: () => _togglePinned(context, item),
                  ),
                  GolemMenuItem(
                    itemKey: const Key('menu-rename'),
                    label: context.l10n.rename,
                    icon: CupertinoIcons.pencil,
                    onPressed: () => _rename(context, item),
                  ),
                  GolemMenuItem(
                    itemKey: const Key('menu-share-transcript'),
                    label: context.l10n.shareTranscript,
                    icon: CupertinoIcons.square_arrow_up,
                    onPressed: () => _shareTranscript(context, item),
                  ),
                  GolemMenuItem(
                    itemKey: const Key('menu-delete'),
                    label: context.l10n.delete,
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
  }

  Future<void> _togglePinned(
    BuildContext context,
    ChatConversation conversation,
  ) async {
    final wasPinned = conversation.pinned;
    await ref
        .read(chatControllerProvider.notifier)
        .togglePinned(conversation.id);
    if (context.mounted) {
      showGolemToast(
        context,
        wasPinned ? context.l10n.unpinned : context.l10n.pinned,
      );
    }
  }

  Future<void> _shareTranscript(
    BuildContext context,
    ChatConversation conversation,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: conversation.transcriptMarkdown(
          untitledTitle: context.l10n.newChat,
          userSpeaker: context.l10n.userSpeaker,
          assistantSpeaker: context.l10n.assistantSpeaker,
        ),
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
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
      // The keyboard inset is the sheet chrome's job now (golem_sheet.dart).
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.renameChat, style: GolemText.cardTitle),
              const SizedBox(height: 16),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => CupertinoTextField(
                  key: const Key('rename-field'),
                  controller: controller,
                  textDirection: contentTextDirection(
                    value.text,
                    fallback: Directionality.of(context),
                  ),
                  placeholder: context.l10n.newChat,
                  autofocus: true,
                  maxLength: 80,
                  clearButtonMode: OverlayVisibilityMode.editing,
                  padding: const EdgeInsets.all(14),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 8, end: 2),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: ValueListenableBuilder(
                    valueListenable: controller,
                    builder: (context, value, _) => Text(
                      '${value.text.characters.length}/80',
                      key: const Key('rename-counter'),
                      style: GolemText.caption.copyWith(
                        color: CupertinoDynamicColor.resolve(
                          GolemTheme.tertiaryInk,
                          context,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GolemButton.filled(
                key: const Key('rename-save'),
                label: context.l10n.save,
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
      title: context.l10n.deleteChatTitle,
      message: context.l10n.deleteNamedChatMessage(
        conversation.title.isEmpty ? context.l10n.newChat : conversation.title,
      ),
      actions: [
        GolemAlertAction(
          label: context.l10n.cancel,
          onPressed: () => Navigator.pop(context),
        ),
        GolemAlertAction(
          key: const Key('confirm-delete'),
          label: context.l10n.delete,
          isDestructive: true,
          onPressed: () {
            ref
                .read(chatControllerProvider.notifier)
                .deleteConversation(conversation.id);
            Navigator.pop(context);
            if (context.mounted) {
              showGolemToast(context, context.l10n.chatDeleted);
            }
          },
        ),
      ],
    );
  }
}

/// The storage footer: Golem's bytes on this device (models, chats, and
/// cache) over the volume's capacity. Hidden entirely when the capacity
/// is unknown.
final class _StorageMeter extends ConsumerWidget {
  const _StorageMeter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Deliberate .value degrade: an inline meter hides while loading or
    // failed — the Storage screen owns the full error surface.
    final overview = ref.watch(storageBreakdownProvider).value;
    final total = overview?.totalBytes;
    if (overview == null || total == null) return const SizedBox.shrink();
    final muted = CupertinoDynamicColor.resolve(
      GolemTheme.drawerMutedInk,
      context,
    );
    return Padding(
      key: const Key('storage-meter'),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                context.l10n.settingsStorage,
                style: GolemText.caption.copyWith(color: muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.storageAmount(
                    gigabytes(overview.usedBytes),
                    gigabytes(total),
                  ),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GolemText.caption.copyWith(color: muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              // Both bars need Positioned.fill. A Stack hands its
              // non-positioned children loose constraints, and a childless
              // ColoredBox takes the smallest size it is offered — so either
              // one laid out 4pt tall by 0pt wide and painted nothing.
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.drawerLine,
                        context,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: FractionallySizedBox(
                      // Left-anchored: the default centers the fill, which
                      // would float it in the middle of the track.
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: (overview.usedBytes / total).clamp(0.0, 1.0),
                      child: ColoredBox(
                        color: CupertinoDynamicColor.resolve(
                          GolemTheme.accent,
                          context,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
