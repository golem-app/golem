import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_identity.dart';
import '../../core/app_version.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/chrome/golem_sheet.dart';
import '../../core/domain/app_preferences.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/section_header.dart';
import '../chat/model_label.dart';
import 'widgets/settings_rows.dart';

/// The minimal settings root: model and app rows, the Advanced mode
/// switch, and About. Everything heavier lives one screen deeper.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(inferenceBackendProvider);
    final catalog = ref.watch(effectiveModelCatalogProvider);
    final preferences =
        ref.watch(preferencesControllerProvider).value ??
        const AppPreferences();
    final storage = ref.watch(storageBreakdownProvider).value;
    final style = preferences.styleFor(backend.profileKey);
    return CupertinoPageScaffold(
      navigationBar: GolemNavBar(title: 'Settings', previousPageTitle: 'Chat'),
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
            const SectionHeader('Model'),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsNavRow(
                  key: const Key('settings-model-row'),
                  label: 'Model',
                  value: chatModelLabel(backend: backend, catalog: catalog),
                  onTap: () => context.push('/settings/models'),
                ),
                SettingsNavRow(
                  key: const Key('settings-style-row'),
                  label: 'Response style',
                  value: _styleLabel(style),
                  onTap: () => context.push('/settings/response-style'),
                ),
                if (preferences.advancedMode)
                  SettingsNavRow(
                    key: const Key('settings-system-prompt-row'),
                    label: 'System prompt',
                    value: preferences.systemPrompt == null
                        ? 'Default'
                        : 'Custom',
                    onTap: () => context.push('/settings/system-prompt'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const SectionHeader('App'),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsNavRow(
                  key: const Key('settings-appearance-row'),
                  label: 'Appearance',
                  value: _themeLabel(preferences.theme),
                  onTap: () => context.push('/settings/appearance'),
                ),
                SettingsNavRow(
                  key: const Key('settings-privacy-row'),
                  label: 'Privacy & data',
                  onTap: () => context.push('/settings/privacy'),
                ),
                SettingsNavRow(
                  key: const Key('settings-storage-row'),
                  label: 'Storage',
                  value: storage == null
                      ? null
                      : '${(storage.usedBytes / 1e9).toStringAsFixed(1)} GB',
                  onTap: () => context.push('/settings/storage'),
                ),
                SettingsNavRow(
                  key: const Key('open-benchmark'),
                  label: 'Benchmark',
                  onTap: () => context.push('/benchmark'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SettingsCard(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Advanced mode', style: GolemText.body),
                          ),
                          MergeSemantics(
                            child: Semantics(
                              label: 'Advanced mode',
                              child: SizedBox(
                                height: GolemSize.hitTarget,
                                child: Center(
                                  child: CupertinoSwitch(
                                    key: const Key('advanced-mode-switch'),
                                    value: preferences.advancedMode,
                                    activeTrackColor:
                                        CupertinoDynamicColor.resolve(
                                          GolemTheme.accent,
                                          context,
                                        ),
                                    onChanged: (value) => ref
                                        .read(
                                          preferencesControllerProvider
                                              .notifier,
                                        )
                                        .setAdvancedMode(value),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sampling controls, a custom system prompt, and '
                        'loading any Hugging Face repository by hand.',
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
              ],
            ),
            const SizedBox(height: 24),
            SettingsCard(
              children: [
                SettingsNavRow(
                  key: const Key('about-row'),
                  label: 'About Golem',
                  value: appVersion,
                  onTap: () => _showAbout(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const SettingsFootnote(
              'Golem is open source. Nothing on this screen sends anything '
              'anywhere.',
            ),
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
            Text('About Golem', style: GolemText.cardTitle),
            const SizedBox(height: 14),
            Text(
              '${AppIdentity.current.displayName} $appVersion · '
              '${AppIdentity.current.applicationId}',
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
                  'Model downloads are a deterministic simulation of the '
                      'pinned catalog; no network access exists.'
                else
                  'Model downloads fetch the pinned artifacts from Hugging '
                      'Face over HTTPS.',
                if (simulatedInference)
                  'Inference is a deterministic UI simulation — no model '
                      'weights, engine, or hardware measurement is included.'
                else
                  'Inference runs the local engine on this device with the '
                      'active model.',
                'Nothing else touches the network, and Golem reads no other '
                    'app\'s data.',
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

String _styleLabel(ResponseStyle style) => switch (style) {
  ResponseStyle.precise => 'Precise',
  ResponseStyle.balanced => 'Balanced',
  ResponseStyle.creative => 'Creative',
};

String _themeLabel(ThemeSetting theme) => switch (theme) {
  ThemeSetting.system => 'System',
  ThemeSetting.light => 'Light',
  ThemeSetting.dark => 'Dark',
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
            'SIMULATED INFERENCE · No hardware validation',
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
