import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/labeled_row.dart';
import '../../core/widgets/progress_track.dart';
import '../../core/widgets/section_header.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(modelControllerProvider);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        previousPageTitle: 'Chat',
        middle: Text('Settings'),
      ),
      child: SafeArea(
        bottom: false,
        child: model.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (error, stack) => Center(
            child: Text('Could not load simulated model state: $error'),
          ),
          data: (value) => _SettingsBody(model: value),
        ),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody({required this.model});
  final ModelState model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatValue = ref.watch(chatControllerProvider);
    final chats = chatValue.hasValue ? chatValue.requireValue : null;
    return ListView(
      key: const Key('settings-list'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        const _SimulationBanner(),
        const SizedBox(height: 28),
        const SectionHeader(
          'Inference backend',
          subtitle:
              'Choose which fake model state drives the UI. No model runtime is included.',
        ),
        const SizedBox(height: 8),
        GolemCard(
          child: Column(
            children: [
              _BackendOption(
                key: const Key('backend-option-mlx'),
                title: 'Gemma 4 E2B QAT',
                subtitle: 'MLX Swift · ${_mlxStatus(model)}',
                selected: model.backend == BackendId.mlx,
                onTap: () => ref
                    .read(modelControllerProvider.notifier)
                    .selectBackend(BackendId.mlx),
              ),
              const SizedBox(height: 10),
              _BackendOption(
                key: const Key('backend-option-turbofieldfare'),
                title: 'Gemma 4 · 26B-A4B',
                subtitle:
                    'TurboFieldfare · ${model.turboInstalled ? 'Installed' : 'Not installed'}',
                selected: model.backend == BackendId.turboFieldfare,
                onTap: () => ref
                    .read(modelControllerProvider.notifier)
                    .selectBackend(BackendId.turboFieldfare),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader(
          'MLX model',
          subtitle:
              'A deterministic download simulation; no HTTP client or Hugging Face access exists.',
        ),
        const SizedBox(height: 8),
        GolemCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gemma 4 E2B QAT',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 5),
              const Text(
                'Simulated size: 4.3 GB · MLX 4-bit',
                style: TextStyle(color: GolemTheme.mutedInk),
              ),
              const SizedBox(height: 14),
              Semantics(
                key: const Key('mlx-model-status'),
                label: 'MLX model status',
                value: _mlxStatus(model),
                child: _Status(icon: _mlxIcon(model), label: _mlxStatus(model)),
              ),
              if (model.mlxPhase == DownloadPhase.downloading ||
                  model.mlxPhase == DownloadPhase.paused) ...[
                const SizedBox(height: 14),
                _Progress(
                  value: model.mlxProgress,
                  label: 'Simulated download',
                ),
              ],
              if (model.mlxPhase == DownloadPhase.verifying) ...[
                const SizedBox(height: 14),
                const Row(
                  children: [
                    CupertinoActivityIndicator(),
                    SizedBox(width: 10),
                    Text('Verifying simulated files…'),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              if (model.mlxPhase != DownloadPhase.installed)
                CupertinoButton.filled(
                  key: Key(
                    model.mlxPhase == DownloadPhase.downloading
                        ? 'mlx-download-cancel-button'
                        : 'mlx-download-button',
                  ),
                  minimumSize: const Size.fromHeight(48),
                  onPressed: model.mlxPhase == DownloadPhase.downloading
                      ? () => ref
                            .read(modelControllerProvider.notifier)
                            .pauseMlx()
                      : () => ref
                            .read(modelControllerProvider.notifier)
                            .downloadOrResumeMlx(),
                  child: Text(
                    model.mlxPhase == DownloadPhase.downloading
                        ? 'Pause Simulation'
                        : model.mlxProgress > 0
                        ? 'Resume Simulated Download'
                        : 'Simulate Download',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader(
          'TurboFieldfare model',
          subtitle:
              'The native app imports over USB; this port only animates the equivalent states.',
        ),
        const SizedBox(height: 8),
        GolemCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gemma 4 · 26B-A4B',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 5),
              const Text(
                'Simulated size: 14.29 GB · 16-slot LFU + pread',
                style: TextStyle(color: GolemTheme.mutedInk),
              ),
              const SizedBox(height: 14),
              Semantics(
                key: const Key('model-status'),
                label: 'TurboFieldfare model status',
                value: model.turboInstalled
                    ? 'Installed and verified, simulated'
                    : 'Not installed',
                child: _Status(
                  icon: model.turboInstalled
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.archivebox,
                  label: model.turboInstalled
                      ? 'Installed and verified · simulated'
                      : 'Waiting for simulated import',
                ),
              ),
              if (model.importProgress > 0 && model.importProgress < 1) ...[
                const SizedBox(height: 14),
                _Progress(
                  value: model.importProgress,
                  label: 'Simulated verification',
                ),
              ],
              const SizedBox(height: 14),
              CupertinoButton(
                key: const Key('model-import-button'),
                color: GolemTheme.accent,
                minimumSize: const Size.fromHeight(48),
                onPressed: () => ref
                    .read(modelControllerProvider.notifier)
                    .importTurboFieldfare(),
                child: Text(
                  model.turboInstalled
                      ? 'Re-run Import Simulation'
                      : 'Simulate Import and Verify',
                  style: const TextStyle(color: CupertinoColors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader('Runtime'),
        const SizedBox(height: 8),
        GolemCard(
          child: Column(
            children: [
              LabeledRow(
                label: 'Selected model',
                value: model.backend == BackendId.mlx
                    ? 'Gemma 4 E2B QAT'
                    : 'Gemma 4 26B-A4B',
              ),
              const SizedBox(height: 10),
              LabeledRow(label: 'State', value: _runtimeLabel(model.runtime)),
              if (model.failure != null) ...[
                const SizedBox(height: 10),
                Text(
                  model.failure!,
                  style: const TextStyle(color: GolemTheme.destructive),
                ),
              ],
              const SizedBox(height: 14),
              CupertinoButton(
                key: const Key('runtime-toggle-button'),
                color: model.runtime == RuntimePhase.loaded
                    ? null
                    : GolemTheme.accent,
                minimumSize: const Size.fromHeight(48),
                onPressed: model.runtime == RuntimePhase.loading
                    ? null
                    : () => ref
                          .read(modelControllerProvider.notifier)
                          .toggleRuntime(),
                child: Text(
                  model.runtime == RuntimePhase.loaded
                      ? 'Unload Simulated Runtime'
                      : 'Load Simulated Runtime',
                  style: TextStyle(
                    color: model.runtime == RuntimePhase.loaded
                        ? GolemTheme.accent
                        : CupertinoColors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader('Benchmark'),
        const SizedBox(height: 8),
        CupertinoButton(
          key: const Key('open-benchmark'),
          padding: EdgeInsets.zero,
          onPressed: () => context.push('/benchmark'),
          child: const GolemCard(
            child: Row(
              children: [
                Icon(CupertinoIcons.speedometer),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Simulated benchmark',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Exercise protocol UI and JSON export',
                        style: TextStyle(
                          color: GolemTheme.mutedInk,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(CupertinoIcons.chevron_forward, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader('Conversations'),
        const SizedBox(height: 8),
        GolemCard(
          child: LabeledRow(
            label: 'Stored in Flutter container',
            value: '${chats?.conversations.length ?? 0} chats',
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader('About'),
        const SizedBox(height: 8),
        const GolemCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabeledRow(label: 'App', value: 'Golem Flutter 1.0.0'),
              SizedBox(height: 10),
              LabeledRow(label: 'Bundle', value: 'app.golem.flutter'),
              SizedBox(height: 12),
              Text(
                'UI evaluation build. It never reads native Golem data and includes no model weights, network downloader, inference engine, or hardware measurement.',
                style: TextStyle(color: GolemTheme.mutedInk, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SimulationBanner extends StatelessWidget {
  const _SimulationBanner();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('simulation-banner'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(GolemTheme.accentSoft, context),
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      children: [
        Icon(CupertinoIcons.lab_flask_solid, color: GolemTheme.accent),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'SIMULATED BACKENDS · No hardware validation',
            style: TextStyle(
              color: GolemTheme.accent,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

class _BackendOption extends StatelessWidget {
  const _BackendOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: title,
    value: selected ? 'Selected' : subtitle,
    child: CupertinoButton(
      padding: const EdgeInsets.all(12),
      minimumSize: const Size.fromHeight(62),
      onPressed: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? GolemTheme.accent : GolemTheme.divider,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: GolemTheme.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: GolemTheme.mutedInk,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              color: selected ? GolemTheme.accent : GolemTheme.mutedInk,
            ),
          ],
        ),
      ),
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: GolemTheme.accent, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      ),
    ],
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value, required this.label});
  final double value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            '${(value * 100).round()}%',
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
      const SizedBox(height: 7),
      ProgressTrack(
        value: value,
        trackColor: GolemTheme.divider,
        fillColor: GolemTheme.accent,
      ),
    ],
  );
}

String _mlxStatus(ModelState model) => switch (model.mlxPhase) {
  DownloadPhase.notDownloaded => 'Not downloaded',
  DownloadPhase.downloading =>
    'Downloading ${(model.mlxProgress * 100).round()}% · simulated',
  DownloadPhase.paused =>
    'Download paused ${(model.mlxProgress * 100).round()}% · simulated',
  DownloadPhase.verifying => 'Verifying · simulated',
  DownloadPhase.installed => 'Installed and verified · simulated',
};

IconData _mlxIcon(ModelState model) => switch (model.mlxPhase) {
  DownloadPhase.notDownloaded => CupertinoIcons.cloud_download,
  DownloadPhase.downloading => CupertinoIcons.arrow_down_circle_fill,
  DownloadPhase.paused => CupertinoIcons.pause_circle_fill,
  DownloadPhase.verifying => CupertinoIcons.check_mark_circled,
  DownloadPhase.installed => CupertinoIcons.check_mark_circled_solid,
};

String _runtimeLabel(RuntimePhase phase) => switch (phase) {
  RuntimePhase.unloaded => 'Unloaded',
  RuntimePhase.loading => 'Loading simulation…',
  RuntimePhase.loaded => 'Ready · simulated',
  RuntimePhase.failed => 'Stopped',
};
