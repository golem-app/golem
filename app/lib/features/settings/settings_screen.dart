import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_identity.dart';
import '../../core/app_version.dart';
import '../../core/chrome/golem_chrome.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/chrome/golem_sheet.dart';
import '../../core/domain/app_preferences.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/settings_rows.dart';
import '../../l10n/l10n.dart';
import '../chat/application/active_model_providers.dart';
import '../legal/ai_disclaimer.dart';
import '../models/application/model_providers.dart';
import '../models/application/storage_providers.dart';
import '../models/model_label.dart';
import '../preferences/application/preferences_providers.dart';
import 'save_feedback.dart';

/// The minimal settings root: model and app rows, the Advanced mode
/// switch, and About. Everything heavier lives one screen deeper.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({required this.identity, super.key});

  final AppIdentity identity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(inferenceBackendProvider);
    final catalog = ref.watch(effectiveModelCatalogProvider);
    final preferences =
        ref.watch(preferencesControllerProvider).value ??
        const AppPreferences();
    // Deliberate .value degrade: the root row shows no size while loading
    // or failed — the Storage screen owns the full error surface.
    final storage = ref.watch(storageBreakdownProvider).value;
    final style = preferences.styleFor(backend.profileKey);
    final l10n = context.l10n;
    return CupertinoPageScaffold(
      navigationBar: GolemNavBar(
        title: l10n.settingsTitle,
        previousPageTitle: l10n.chatTitle,
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: const Key('settings-list'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            if (backend.simulatedInference) ...[
              const SimulationBanner(),
              const SizedBox(height: 24),
            ],
            SectionHeader(l10n.settingsSectionModel),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsNavRow(
                  key: const Key('settings-model-row'),
                  label: l10n.settingsModel,
                  // The row names what the Models screen it opens will mark
                  // active, which the resident key alone did not (#129).
                  value: modelDisplayLabel(
                    backend: backend,
                    catalog: catalog,
                    activeKey: ref.watch(activeModelKeyProvider),
                  ),
                  onTap: () => context.push('/settings/models'),
                ),
                SettingsNavRow(
                  key: const Key('settings-style-row'),
                  label: l10n.settingsResponseStyle,
                  value: _styleLabel(style, l10n),
                  onTap: () => context.push('/settings/response-style'),
                ),
                if (preferences.advancedMode)
                  SettingsNavRow(
                    key: const Key('settings-system-prompt-row'),
                    label: l10n.settingsSystemPrompt,
                    value: preferences.systemPrompt == null
                        ? l10n.defaultValue
                        : l10n.customValue,
                    onTap: () => context.push('/settings/system-prompt'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const AiDisclaimer(key: Key('settings-ai-disclaimer')),
            const SizedBox(height: 24),
            SectionHeader(l10n.settingsSectionApp),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsNavRow(
                  key: const Key('settings-appearance-row'),
                  label: l10n.settingsAppearance,
                  value: _themeLabel(preferences.theme, l10n),
                  onTap: () => context.push('/settings/appearance'),
                ),
                SettingsNavRow(
                  key: const Key('settings-language-row'),
                  label: l10n.settingsLanguage,
                  value: _languageLabel(preferences.language, l10n),
                  onTap: () => context.push('/settings/language'),
                ),
                SettingsNavRow(
                  key: const Key('settings-privacy-row'),
                  label: l10n.settingsPrivacyData,
                  onTap: () => context.push('/settings/privacy'),
                ),
                SettingsNavRow(
                  key: const Key('settings-storage-row'),
                  label: l10n.settingsStorage,
                  value: storage == null
                      ? null
                      : '${(storage.usedBytes / 1e9).toStringAsFixed(1)} GB',
                  onTap: () => context.push('/settings/storage'),
                ),
                if (identity.internalToolsEnabled)
                  SettingsNavRow(
                    key: const Key('open-benchmark'),
                    label: l10n.settingsBenchmark,
                    onTap: () => context.push('/benchmark'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            SettingsCard(
              children: [
                // One control, like every SettingsToggleRow: split up, the
                // label reads twice and the footnote lands on the card's
                // node, which neither screen reader stops on.
                MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.advancedMode,
                                style: GolemText.body,
                              ),
                            ),
                            SizedBox(
                              height: GolemChrome.current.minimumTapTarget,
                              child: Center(
                                child: CupertinoSwitch(
                                  key: const Key('advanced-mode-switch'),
                                  value: preferences.advancedMode,
                                  activeTrackColor:
                                      CupertinoDynamicColor.resolve(
                                        GolemTheme.accent,
                                        context,
                                      ),
                                  onChanged: (value) => announceFailedSave(
                                    context,
                                    ref
                                        .read(
                                          preferencesControllerProvider
                                              .notifier,
                                        )
                                        .setAdvancedMode(value),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.advancedModeDetail,
                          style: GolemText.footnote.copyWith(
                            color: CupertinoDynamicColor.resolve(
                              GolemTheme.mutedInk,
                              context,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SectionHeader(l10n.aboutLegal),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsNavRow(
                  key: const Key('model-attribution-row'),
                  label: l10n.settingsModelAttribution,
                  onTap: () => context.push('/settings/model-attribution'),
                ),
                SettingsNavRow(
                  key: const Key('open-source-licenses-row'),
                  label: l10n.settingsOpenSourceLicenses,
                  onTap: () => context.push('/settings/licenses'),
                ),
                SettingsNavRow(
                  key: const Key('about-row'),
                  label: l10n.settingsAboutGolem,
                  value: appVersion,
                  onTap: () => _showAbout(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SettingsFootnote(l10n.openSourcePrivacyFootnote),
          ],
        ),
      ),
    );
  }

  void _showAbout(BuildContext context, WidgetRef ref) {
    final model = ref.read(modelControllerProvider).value;
    final simulatedInference = ref
        .read(inferenceBackendProvider)
        .simulatedInference;
    showGolemSheet<void>(
      context: context,
      sheetKey: const Key('about-sheet'),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.settingsAboutGolem, style: GolemText.cardTitle),
            const SizedBox(height: 14),
            Text(
              '${identity.displayName} $appVersion · ${identity.applicationId}',
              style: GolemText.footnote.copyWith(
                color: CupertinoDynamicColor.resolve(
                  GolemTheme.mutedInk,
                  context,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              [
                if (model?.simulated ?? true)
                  context.l10n.modelDownloadsSimulated
                else
                  context.l10n.modelDownloadsReal,
                if (simulatedInference)
                  context.l10n.inferenceSimulated
                else
                  context.l10n.inferenceLocal,
                context.l10n.networkPrivacyStatement,
              ].join(' '),
              style: GolemText.footnote.copyWith(
                height: 1.4,
                color: CupertinoDynamicColor.resolve(
                  GolemTheme.mutedInk,
                  context,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _styleLabel(ResponseStyle style, AppLocalizations l10n) =>
    switch (style) {
      ResponseStyle.precise => l10n.stylePrecise,
      ResponseStyle.balanced => l10n.styleBalanced,
      ResponseStyle.creative => l10n.styleCreative,
    };

String _themeLabel(ThemeSetting theme, AppLocalizations l10n) =>
    switch (theme) {
      ThemeSetting.system => l10n.themeSystem,
      ThemeSetting.light => l10n.themeLight,
      ThemeSetting.dark => l10n.themeDark,
    };

String _languageLabel(AppLanguage language, AppLocalizations l10n) =>
    switch (language) {
      AppLanguage.system => l10n.languageSystem,
      AppLanguage.english => l10n.languageEnglish,
      AppLanguage.polish => l10n.languagePolish,
      AppLanguage.spanish => l10n.languageSpanish,
      AppLanguage.brazilianPortuguese => l10n.languageBrazilianPortuguese,
      AppLanguage.japanese => l10n.languageJapanese,
      AppLanguage.indonesian => l10n.languageIndonesian,
      AppLanguage.hindi => l10n.languageHindi,
      AppLanguage.french => l10n.languageFrench,
      AppLanguage.vietnamese => l10n.languageVietnamese,
      AppLanguage.turkish => l10n.languageTurkish,
      AppLanguage.korean => l10n.languageKorean,
      AppLanguage.arabic => l10n.languageArabic,
    };

/// The honesty banner qa builds show at the top of settings.
class SimulationBanner extends StatelessWidget {
  const SimulationBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('simulation-banner'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(GolemTheme.accentSoft, context),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Icon(
          CupertinoIcons.lab_flask_solid,
          color: CupertinoDynamicColor.resolve(GolemTheme.accent, context),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            context.l10n.simulatedInferenceBanner,
            style: TextStyle(
              color: CupertinoDynamicColor.resolve(GolemTheme.accent, context),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}
