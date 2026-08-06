import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/chrome/golem_alert.dart';
import '../../core/chrome/golem_button.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/chrome/golem_toast.dart';
import '../../core/domain/app_preferences.dart';
import '../../core/domain/model_catalog.dart';
import '../../core/domain/model_speed.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/labeled_row.dart';
import '../../core/widgets/progress_track.dart';
import '../../core/widgets/section_header.dart';
import 'widgets/settings_rows.dart';

enum _CatalogTab { all, installed }

/// Models & downloads: the catalog cards, the runtime, and — in Advanced
/// mode — the custom repository loader.
class ModelsScreen extends ConsumerStatefulWidget {
  const ModelsScreen({super.key});

  @override
  ConsumerState<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends ConsumerState<ModelsScreen> {
  // Ephemeral screen state stays widget-local: the tab, the custom
  // repository draft, and its engine chip.
  _CatalogTab _tab = _CatalogTab.all;
  final _repositoryController = TextEditingController();
  ModelEngine _customEngine = ModelEngine.mlx;

  @override
  void dispose() {
    _repositoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(modelControllerProvider);
    return CupertinoPageScaffold(
      navigationBar: GolemNavBar(
        title: 'Models',
        previousPageTitle: 'Settings',
      ),
      child: SafeArea(
        bottom: false,
        child: model.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (error, stack) =>
              Center(child: Text('Could not load model state: $error')),
          data: (value) => _body(context, value),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ModelState model) {
    final catalog = ref.watch(effectiveModelCatalogProvider);
    // Only the fake backend can download hand-added repositories; the
    // real downloader knows the pinned catalog alone until #20, and an
    // enabled button there would fail on every tap.
    final pinnedKeys = {
      for (final entry in ref.watch(modelCatalogEntriesProvider)) entry.key,
    };
    final advanced =
        ref.watch(preferencesControllerProvider).value?.advancedMode ?? false;
    final simulatedInference = ref
        .watch(inferenceBackendProvider)
        .simulatedInference;
    final downloadingKey = model.artifacts.entries
        .where((entry) => entry.value.phase == ArtifactPhase.downloading)
        .map((entry) => entry.key)
        .firstOrNull;
    final visible = _tab == _CatalogTab.all
        ? catalog
        : catalog
              .where(
                (entry) =>
                    model.statusOf(entry.key).phase == ArtifactPhase.installed,
              )
              .toList();
    return ListView(
      key: const Key('models-list'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        GolemSegmented<_CatalogTab>(
          groupValue: _tab,
          onChanged: (tab) => setState(() => _tab = tab),
          segments: const {
            _CatalogTab.all: Text(
              'All models',
              key: Key('models-tab-all'),
              style: GolemText.footnoteStrong,
            ),
            _CatalogTab.installed: Text(
              'Installed',
              key: Key('models-tab-installed'),
              style: GolemText.footnoteStrong,
            ),
          },
        ),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: SettingsFootnote(
              model.simulated
                  ? 'Nothing is installed yet. Downloads here are a '
                        'deterministic simulation.'
                  : 'Nothing is installed yet.',
              key: const Key('models-empty'),
            ),
          ),
        for (final entry in visible) ...[
          _ModelCard(
            entry: entry,
            status: model.statusOf(entry.key),
            simulated: model.simulated,
            active: entry.key == model.activeArtifactKey,
            otherDownloadActive:
                downloadingKey != null && downloadingKey != entry.key,
            downloadable: model.simulated || pinnedKeys.contains(entry.key),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        const SectionHeader('Runtime'),
        const SizedBox(height: 8),
        _RuntimeCard(model: model, simulatedInference: simulatedInference),
        if (advanced) ...[
          const SizedBox(height: 24),
          const SectionHeader('Custom repository'),
          const SizedBox(height: 8),
          _CustomRepositoryCard(
            controller: _repositoryController,
            engine: _customEngine,
            onEngine: (engine) => setState(() => _customEngine = engine),
            simulatedDownloads: model.simulated,
          ),
        ],
        const SizedBox(height: 18),
        SettingsFootnote(
          model.simulated
              ? 'Downloads are a deterministic simulation of the pinned '
                    'catalog; no network access exists.'
              : 'Downloads pull straight from Hugging Face and are verified '
                    'by revision hash.',
        ),
      ],
    );
  }
}

class _RuntimeCard extends ConsumerWidget {
  const _RuntimeCard({required this.model, required this.simulatedInference});
  final ModelState model;
  final bool simulatedInference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(effectiveModelCatalogProvider);
    final active = catalog
        .where((entry) => entry.key == model.activeArtifactKey)
        .firstOrNull;
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              LabeledRow(
                label: 'Active model',
                value:
                    active?.displayName ??
                    (simulatedInference
                        ? 'None · simulated inference'
                        : 'None'),
              ),
              const SizedBox(height: 10),
              LabeledRow(
                label: 'State',
                value: _runtimeLabel(model.runtime, simulatedInference),
              ),
              if (model.failure != null) ...[
                const SizedBox(height: 10),
                Text(
                  model.failure!,
                  style: const TextStyle(color: GolemTheme.destructive),
                ),
              ],
              const SizedBox(height: 14),
              GolemButton.tinted(
                key: const Key('runtime-toggle-button'),
                label: model.runtime == RuntimePhase.loaded
                    ? 'Unload ${simulatedInference ? 'Simulated ' : ''}Runtime'
                    : 'Load ${simulatedInference ? 'Simulated ' : ''}Runtime',
                onPressed: model.runtime == RuntimePhase.loading
                    ? null
                    : () => ref
                          .read(modelControllerProvider.notifier)
                          .toggleRuntime(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomRepositoryCard extends ConsumerWidget {
  const _CustomRepositoryCard({
    required this.controller,
    required this.engine,
    required this.onEngine,
    required this.simulatedDownloads,
  });

  final TextEditingController controller;
  final ModelEngine engine;
  final ValueChanged<ModelEngine> onEngine;

  /// Only the fake management backend simulates arbitrary repositories;
  /// the real downloader stays pinned-catalog-only until #20.
  final bool simulatedDownloads;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _EngineChip(
                    key: const Key('custom-repo-engine-mlx'),
                    label: 'MLX',
                    selected: engine == ModelEngine.mlx,
                    onTap: () => onEngine(ModelEngine.mlx),
                  ),
                  const SizedBox(width: 8),
                  _EngineChip(
                    key: const Key('custom-repo-engine-gguf'),
                    label: 'GGUF',
                    selected: engine == ModelEngine.gguf,
                    onTap: () => onEngine(ModelEngine.gguf),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              CupertinoTextField(
                key: const Key('custom-repo-field'),
                controller: controller,
                placeholder: engine == ModelEngine.mlx
                    ? 'mlx-community/model-name'
                    : 'org/model-name-GGUF',
                autocorrect: false,
                enableSuggestions: false,
                style: GolemText.code,
                placeholderStyle: GolemText.code.copyWith(color: muted),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: CupertinoDynamicColor.resolve(
                      GolemTheme.borderStrong,
                      context,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(GolemRadius.field),
                ),
              ),
              const SizedBox(height: 12),
              const LabeledRow(label: 'Revision', value: 'main'),
              const SizedBox(height: 16),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => GolemButton.filled(
                  key: const Key('custom-repo-add'),
                  label: 'Add model',
                  onPressed: !simulatedDownloads || value.text.trim().isEmpty
                      ? null
                      : () => _add(context, ref, value.text.trim()),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                simulatedDownloads
                    ? 'Nothing is validated ahead of time. If the repository '
                          'isn\'t a supported MLX or GGUF build, loading it '
                          'will simply fail.'
                    : 'Custom repositories on a real engine arrive in a '
                          'future update.',
                style: GolemText.footnote.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    String repository,
  ) async {
    final spec = CustomModelSpec(repository: repository, engine: engine);
    await ref.read(preferencesControllerProvider.notifier).addCustomModel(spec);
    controller.clear();
    if (context.mounted) showGolemToast(context, 'Model added');
  }
}

class _EngineChip extends StatelessWidget {
  const _EngineChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoDynamicColor.resolve(GolemTheme.accent, context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
            selected ? GolemTheme.accentSoft : GolemTheme.fillQuiet,
            context,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GolemText.captionStrong.copyWith(
                color: selected
                    ? CupertinoDynamicColor.resolve(
                        GolemTheme.accentIcon,
                        context,
                      )
                    : CupertinoDynamicColor.resolve(
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

class _ModelCard extends ConsumerWidget {
  const _ModelCard({
    required this.entry,
    required this.status,
    required this.simulated,
    required this.active,
    required this.otherDownloadActive,
    required this.downloadable,
  });

  final ModelCatalogEntry entry;
  final ArtifactStatus status;
  final bool simulated;
  final bool active;
  final bool otherDownloadActive;

  /// False for hand-added entries on a real download backend, whose
  /// repository would reject the unknown key.
  final bool downloadable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(modelControllerProvider.notifier);
    final suffix = simulated ? ' · simulated' : '';
    final statusLabel = _statusLabel(suffix);
    final chats = ref.watch(chatControllerProvider).value?.conversations;
    final backend = ref.watch(inferenceBackendProvider);
    final measured = chats == null
        ? null
        : measuredTokensPerSecond(
            chats,
            modelKey: entry.key,
            defaultModelKey: backend.artifactKey ?? 'gemma4-mlx',
          );
    return GolemCard(
      child: Column(
        key: Key('model-card-${entry.key}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(entry.displayName, style: GolemText.cardTitle),
              ),
              if (active) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: CupertinoDynamicColor.resolve(
                      GolemTheme.accentSoft,
                      context,
                    ),
                    borderRadius: BorderRadius.circular(GolemRadius.badge),
                  ),
                  child: Text(
                    'ACTIVE',
                    style: GolemText.badge.copyWith(
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.accent,
                        context,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${_engineLabel(entry.engine)} · ${entry.quantization}',
            style: TextStyle(
              color: CupertinoDynamicColor.resolve(
                GolemTheme.mutedInk,
                context,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            key: Key('model-status-${entry.key}'),
            label: '${entry.displayName} ${_engineLabel(entry.engine)} status',
            value: statusLabel,
            child: _Status(icon: _statusIcon(), label: statusLabel),
          ),
          if (status.phase == ArtifactPhase.downloading ||
              status.phase == ArtifactPhase.paused) ...[
            const SizedBox(height: 14),
            _Progress(
              value: entry.totalBytes == 0
                  ? 0
                  : (status.downloadedBytes / entry.totalBytes).clamp(0, 1),
              label: 'Download$suffix',
            ),
          ],
          if (status.phase == ArtifactPhase.verifying) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const CupertinoActivityIndicator(),
                const SizedBox(width: 10),
                Text('Verifying files$suffix…'),
              ],
            ),
          ],
          if (status.phase == ArtifactPhase.failed &&
              status.failure != null) ...[
            const SizedBox(height: 10),
            Text(
              status.failure!,
              style: const TextStyle(color: GolemTheme.destructive),
            ),
          ],
          const SizedBox(height: 14),
          GestureDetector(
            key: Key('model-repository-${entry.key}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => launchUrl(entry.repositoryUrl),
            child: Semantics(
              button: true,
              label: 'Open ${entry.repository} on Hugging Face',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: LabeledRow(
                        label: 'Repository',
                        value: entry.repository,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      CupertinoIcons.arrow_up_right_square,
                      size: 15,
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.mutedInk,
                        context,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          LabeledRow(
            label: 'Revision',
            value: entry.revision.length > 12
                ? entry.revision.substring(0, 12)
                : entry.revision,
          ),
          const SizedBox(height: 6),
          LabeledRow(
            label: 'Size',
            value:
                '${_gigabytes(entry.totalBytes)} · '
                '${entry.files.length} ${entry.files.length == 1 ? 'file' : 'files'}',
          ),
          if (measured != null) ...[
            const SizedBox(height: 6),
            LabeledRow(
              label: 'Measured',
              // Honesty: the fake's canned rate is never sold as hardware.
              value: simulated
                  ? '${measured.toStringAsFixed(1)} tok/s · simulated'
                  : '${measured.toStringAsFixed(1)} tok/s on this phone',
            ),
          ],
          ..._buttons(context, controller),
        ],
      ),
    );
  }

  List<Widget> _buttons(BuildContext context, ModelController controller) {
    final download = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GolemButton.filled(
          key: Key('model-download-${entry.key}'),
          label: switch (status.phase) {
            ArtifactPhase.paused => 'Resume Download',
            ArtifactPhase.failed => 'Retry Download',
            _ => 'Download · ${_gigabytes(entry.totalBytes)}',
          },
          onPressed: otherDownloadActive || !downloadable
              ? null
              : () => controller.download(entry.key),
        ),
        if (!downloadable)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Hand-added repositories can\'t download on this engine yet — '
              'that arrives in a future update.',
              style: GolemText.footnote.copyWith(
                color: CupertinoDynamicColor.resolve(
                  GolemTheme.mutedInk,
                  context,
                ),
              ),
            ),
          ),
      ],
    );
    final cancel = CupertinoButton(
      key: Key('model-cancel-${entry.key}'),
      minimumSize: const Size.fromHeight(48),
      onPressed: () => controller.cancel(entry.key),
      child: const Text(
        'Cancel and Discard',
        style: TextStyle(color: GolemTheme.destructive),
      ),
    );
    return switch (status.phase) {
      ArtifactPhase.notDownloaded => [const SizedBox(height: 14), download],
      ArtifactPhase.downloading => [
        const SizedBox(height: 14),
        GolemButton.tinted(
          key: Key('model-pause-${entry.key}'),
          label: 'Pause',
          onPressed: () => controller.pause(entry.key),
        ),
        cancel,
      ],
      ArtifactPhase.paused ||
      ArtifactPhase.failed => [const SizedBox(height: 14), download, cancel],
      ArtifactPhase.verifying => const [],
      ArtifactPhase.installed => [
        const SizedBox(height: 14),
        CupertinoButton(
          key: Key('model-delete-${entry.key}'),
          minimumSize: const Size.fromHeight(48),
          onPressed: () => _confirmDelete(context, controller),
          child: const Text(
            'Delete Download',
            style: TextStyle(color: GolemTheme.destructive),
          ),
        ),
      ],
    };
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ModelController controller,
  ) => showGolemAlert(
    context: context,
    dialogKey: const Key('model-delete-dialog'),
    title: 'Delete ${entry.displayName}?',
    message:
        'Removes ${_gigabytes(entry.totalBytes)} from this device. '
        'The model can be downloaded again later.',
    actions: [
      GolemAlertAction(label: 'Keep', onPressed: () => Navigator.pop(context)),
      GolemAlertAction(
        key: const Key('confirm-model-delete'),
        label: 'Delete',
        isDestructive: true,
        onPressed: () {
          Navigator.pop(context);
          controller.delete(entry.key);
        },
      ),
    ],
  );

  String _statusLabel(String suffix) => switch (status.phase) {
    ArtifactPhase.notDownloaded => 'Not downloaded',
    ArtifactPhase.downloading =>
      'Downloading ${_gigabytes(status.downloadedBytes)} of '
          '${_gigabytes(entry.totalBytes)}$suffix',
    ArtifactPhase.paused =>
      'Paused at ${_gigabytes(status.downloadedBytes)}$suffix',
    ArtifactPhase.verifying => 'Verifying$suffix',
    ArtifactPhase.installed => 'Installed and verified$suffix',
    ArtifactPhase.failed => 'Download failed',
  };

  IconData _statusIcon() => switch (status.phase) {
    ArtifactPhase.notDownloaded => CupertinoIcons.cloud_download,
    ArtifactPhase.downloading => CupertinoIcons.arrow_down_circle_fill,
    ArtifactPhase.paused => CupertinoIcons.pause_circle_fill,
    ArtifactPhase.verifying => CupertinoIcons.check_mark_circled,
    ArtifactPhase.installed => CupertinoIcons.check_mark_circled_solid,
    ArtifactPhase.failed => CupertinoIcons.exclamationmark_triangle_fill,
  };
}

class _Status extends StatelessWidget {
  const _Status({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        icon,
        color: CupertinoDynamicColor.resolve(GolemTheme.accent, context),
        size: 20,
      ),
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

String _engineLabel(ModelEngine engine) => switch (engine) {
  ModelEngine.mlx => 'MLX',
  ModelEngine.gguf => 'GGUF · llama.cpp',
};

String _gigabytes(int bytes) => '${(bytes / 1000000000).toStringAsFixed(2)} GB';

String _runtimeLabel(RuntimePhase phase, bool simulated) => switch (phase) {
  RuntimePhase.unloaded => 'Unloaded',
  RuntimePhase.loading => simulated ? 'Loading simulation…' : 'Loading…',
  RuntimePhase.loaded => simulated ? 'Ready · simulated' : 'Ready',
  RuntimePhase.failed => 'Stopped',
};
