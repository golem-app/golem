import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/chrome/golem_alert.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/chrome/golem_toast.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/section_header.dart';
import '../../l10n/l10n.dart';
import '../chat/application/chat_providers.dart';
import '../preferences/application/preferences_providers.dart';
import 'save_feedback.dart';
import 'widgets/settings_rows.dart';

/// Privacy & data: the no-network statement, chat-history retention, and
/// the user's own-data actions.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesControllerProvider).value;
    final notifier = ref.read(preferencesControllerProvider.notifier);
    return CupertinoPageScaffold(
      navigationBar: GolemNavBar(
        title: context.l10n.settingsPrivacyData,
        previousPageTitle: context.l10n.settingsTitle,
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(
                  GolemTheme.accentSoft,
                  context,
                ),
                borderRadius: BorderRadius.circular(GolemRadius.card),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    CupertinoIcons.shield_lefthalf_fill,
                    size: 20,
                    color: CupertinoDynamicColor.resolve(
                      GolemTheme.accentIcon,
                      context,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.privacyStatement,
                      style: GolemText.footnote.copyWith(
                        height: 1.4,
                        color: CupertinoDynamicColor.resolve(
                          GolemTheme.accentIcon,
                          context,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SectionHeader(context.l10n.onThisPhone),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsToggleRow(
                  toggleKey: const Key('toggle-save-history'),
                  label: context.l10n.saveChatHistory,
                  value: preferences?.saveHistory ?? true,
                  footnote: context.l10n.saveHistoryOffDetail,
                  onChanged: (value) => value
                      ? announceFailedSave(
                          context,
                          notifier.setSaveHistory(true),
                        )
                      : _confirmHistoryOff(context, notifier),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SectionHeader(context.l10n.yourData),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsNavRow(
                  key: const Key('export-chats'),
                  label: context.l10n.exportAllChats,
                  value: 'JSON',
                  onTap: () => _exportChats(context, ref),
                ),
                SettingsNavRow(
                  key: const Key('delete-all-chats'),
                  label: context.l10n.deleteAllChats,
                  destructive: true,
                  onTap: () => _confirmDeleteAll(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmHistoryOff(
    BuildContext context,
    PreferencesController notifier,
  ) {
    showGolemAlert(
      context: context,
      dialogKey: const Key('confirm-history-off-dialog'),
      title: context.l10n.stopSavingChatsTitle,
      message: context.l10n.stopSavingChatsMessage,
      actions: [
        GolemAlertAction(
          label: context.l10n.keepSaving,
          onPressed: () => Navigator.pop(context),
        ),
        GolemAlertAction(
          key: const Key('confirm-history-off'),
          label: context.l10n.stopAndDelete,
          isDestructive: true,
          onPressed: () {
            Navigator.pop(context);
            announceFailedSave(
              context,
              notifier.setSaveHistory(false),
              message: context.l10n.deleteSavedChatsFailed,
            );
          },
        ),
      ],
    );
  }

  Future<void> _exportChats(BuildContext context, WidgetRef ref) async {
    final json = ref.read(chatControllerProvider.notifier).exportAllChats();
    if (json == null) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: json,
        subject: context.l10n.chatsExportSubject,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  void _confirmDeleteAll(BuildContext context, WidgetRef ref) {
    showGolemAlert(
      context: context,
      dialogKey: const Key('confirm-delete-all-dialog'),
      title: context.l10n.deleteAllChatsTitle,
      message: context.l10n.deleteAllChatsMessage,
      actions: [
        GolemAlertAction(
          label: context.l10n.cancel,
          onPressed: () => Navigator.pop(context),
        ),
        GolemAlertAction(
          key: const Key('confirm-delete-all'),
          label: context.l10n.deleteAllChats,
          isDestructive: true,
          onPressed: () async {
            Navigator.pop(context);
            final deleted = await ref
                .read(chatControllerProvider.notifier)
                .deleteAllChats();
            if (!context.mounted) return;
            showGolemToast(
              context,
              deleted
                  ? context.l10n.chatsDeleted
                  : context.l10n.deleteChatsFailed,
            );
          },
        ),
      ],
    );
  }
}
