import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chrome/golem_nav_bar.dart';
import '../../core/domain/app_preferences.dart';
import '../../core/widgets/retry_pane.dart';
import '../../core/widgets/section_header.dart';
import '../../l10n/l10n.dart';
import 'application/preferences_providers.dart';
import 'save_feedback.dart';
import 'widgets/settings_rows.dart';

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferencesValue = ref.watch(preferencesControllerProvider);
    final l10n = context.l10n;
    if (preferencesValue.hasError) {
      return CupertinoPageScaffold(
        navigationBar: GolemNavBar(
          title: l10n.settingsLanguage,
          previousPageTitle: l10n.settingsTitle,
        ),
        child: SafeArea(
          bottom: false,
          child: RetryPane(
            key: const Key('language-preferences-load-error'),
            message: l10n.preferencesLoadFailed,
            actionLabel: l10n.tryAgain,
            onRetry: () => ref.invalidate(preferencesControllerProvider),
          ),
        ),
      );
    }
    final language = preferencesValue.value?.language ?? AppLanguage.system;
    final notifier = ref.read(preferencesControllerProvider.notifier);
    return CupertinoPageScaffold(
      navigationBar: GolemNavBar(
        title: l10n.settingsLanguage,
        previousPageTitle: l10n.settingsTitle,
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: const Key('language-list'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            SectionHeader(
              l10n.settingsLanguage,
              subtitle: l10n.languageSystemDetail,
            ),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                _LanguageRow(
                  rowKey: const Key('language-system'),
                  label: l10n.languageSystem,
                  selected: language == AppLanguage.system,
                  onTap: () => _select(context, notifier, AppLanguage.system),
                ),
                _LanguageRow(
                  rowKey: const Key('language-english'),
                  label: l10n.languageEnglish,
                  selected: language == AppLanguage.english,
                  onTap: () => _select(context, notifier, AppLanguage.english),
                ),
                _LanguageRow(
                  rowKey: const Key('language-polish'),
                  label: l10n.languagePolish,
                  selected: language == AppLanguage.polish,
                  onTap: () => _select(context, notifier, AppLanguage.polish),
                ),
                _LanguageRow(
                  rowKey: const Key('language-spanish'),
                  label: l10n.languageSpanish,
                  selected: language == AppLanguage.spanish,
                  onTap: () => _select(context, notifier, AppLanguage.spanish),
                ),
                _LanguageRow(
                  rowKey: const Key('language-brazilian-portuguese'),
                  label: l10n.languageBrazilianPortuguese,
                  selected: language == AppLanguage.brazilianPortuguese,
                  onTap: () => _select(
                    context,
                    notifier,
                    AppLanguage.brazilianPortuguese,
                  ),
                ),
                _LanguageRow(
                  rowKey: const Key('language-japanese'),
                  label: l10n.languageJapanese,
                  selected: language == AppLanguage.japanese,
                  onTap: () => _select(context, notifier, AppLanguage.japanese),
                ),
                _LanguageRow(
                  rowKey: const Key('language-indonesian'),
                  label: l10n.languageIndonesian,
                  selected: language == AppLanguage.indonesian,
                  onTap: () =>
                      _select(context, notifier, AppLanguage.indonesian),
                ),
                _LanguageRow(
                  rowKey: const Key('language-arabic'),
                  label: l10n.languageArabic,
                  selected: language == AppLanguage.arabic,
                  onTap: () => _select(context, notifier, AppLanguage.arabic),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _select(
    BuildContext context,
    PreferencesController notifier,
    AppLanguage language,
  ) {
    announceFailedSave(
      context,
      notifier.setLanguage(language),
      message: context.l10n.languageSaveFailed,
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.rowKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key rowKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    value: selected ? context.l10n.languageSelected(label) : null,
    child: SettingsNavRow(
      key: rowKey,
      label: label,
      value: selected ? '✓' : null,
      onTap: onTap,
    ),
  );
}
