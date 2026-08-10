import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/chrome/golem_alert.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/chrome/golem_toast.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/section_header.dart';
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
        title: 'Privacy & data',
        previousPageTitle: 'Settings',
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
                      'Golem holds no account, sends no analytics, and '
                      'drops its network permission once a model is '
                      'downloaded. There is nothing to opt out of.',
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
            const SectionHeader('On this phone'),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsToggleRow(
                  toggleKey: const Key('toggle-save-history'),
                  label: 'Save chat history',
                  value: preferences?.saveHistory ?? true,
                  footnote:
                      'Off means every chat disappears when you close it.',
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
            const SectionHeader('Your data'),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsNavRow(
                  key: const Key('export-chats'),
                  label: 'Export all chats',
                  value: 'JSON',
                  onTap: () => _exportChats(context, ref),
                ),
                SettingsNavRow(
                  key: const Key('delete-all-chats'),
                  label: 'Delete all chats',
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
      title: 'Stop saving chats?',
      message:
          'Chats already saved on this device are deleted now. Open chats '
          'stay until you close the app, and nothing new is written to '
          'disk.',
      actions: [
        GolemAlertAction(
          label: 'Keep saving',
          onPressed: () => Navigator.pop(context),
        ),
        GolemAlertAction(
          key: const Key('confirm-history-off'),
          label: 'Stop and delete',
          isDestructive: true,
          onPressed: () {
            Navigator.pop(context);
            announceFailedSave(
              context,
              notifier.setSaveHistory(false),
              message: "Couldn't delete the saved chats. Try again.",
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
        subject: 'Golem chats export',
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
      title: 'Delete all chats?',
      message:
          'Every conversation is removed from this device. Downloaded '
          'models are kept.',
      actions: [
        GolemAlertAction(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        GolemAlertAction(
          key: const Key('confirm-delete-all'),
          label: 'Delete all',
          isDestructive: true,
          onPressed: () async {
            Navigator.pop(context);
            final deleted = await ref
                .read(chatControllerProvider.notifier)
                .deleteAllChats();
            if (!context.mounted) return;
            showGolemToast(
              context,
              deleted ? 'Chats deleted' : "Couldn't delete chats. Try again.",
            );
          },
        ),
      ],
    );
  }
}
