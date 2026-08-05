import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

// Deliberate layering note: features may consume the broker's model
// knowledge (profiles carry no Inferno import); the Inferno boundary is
// unchanged — only lib/broker/ touches package:inferno.
import '../../broker/model_profile.dart';
import '../../core/app_identity.dart';
import '../../core/domain/generation_settings.dart';
import '../../core/domain/model_catalog.dart';
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
          error: (error, stack) =>
              Center(child: Text('Could not load model state: $error')),
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
    final catalog = ref.watch(modelCatalogEntriesProvider);
    // Two independent honesty axes: model.simulated covers the download
    // surface, the backend signal covers inference. A dev build can run
    // real downloads with fake inference — each label keys on its own axis.
    final simulatedInference = ref
        .watch(inferenceBackendProvider)
        .simulatedInference;
    // Downloads are serial, so the one card in a downloading phase is the
    // live one; deriving it from watched state keeps a single source of
    // truth instead of mirroring a controller field.
    final downloadingKey = model.artifacts.entries
        .where((entry) => entry.value.phase == ArtifactPhase.downloading)
        .map((entry) => entry.key)
        .firstOrNull;
    final active = catalog
        .where((entry) => entry.key == model.activeArtifactKey)
        .firstOrNull;
    return ListView(
      key: const Key('settings-list'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (simulatedInference) ...[
          const _SimulationBanner(),
          const SizedBox(height: 28),
        ],
        SectionHeader(
          'Models',
          subtitle: model.simulated
              ? 'A deterministic download simulation of the pinned catalog; no network access exists.'
              : 'Pinned Hugging Face artifacts; every file is verified against its recorded SHA-256.',
        ),
        const SizedBox(height: 8),
        for (final entry in catalog) ...[
          _ModelCard(
            entry: entry,
            status: model.statusOf(entry.key),
            simulated: model.simulated,
            active: entry.key == model.activeArtifactKey,
            otherDownloadActive:
                downloadingKey != null && downloadingKey != entry.key,
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 16),
        const SectionHeader(
          'Generation',
          subtitle:
              'Per-model sampling and budget controls. Recommended defaults '
              'come from the model profile; changes reach generation on the '
              'real engine only. Token budgets always leave 512 context '
              'tokens for the prompt.',
        ),
        const SizedBox(height: 8),
        for (final profileKey in modelProfiles.keys) ...[
          _GenerationCard(profileKey: profileKey),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 16),
        const SectionHeader('Runtime'),
        const SizedBox(height: 8),
        GolemCard(
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
                      ? 'Unload ${simulatedInference ? 'Simulated ' : ''}Runtime'
                      : 'Load ${simulatedInference ? 'Simulated ' : ''}Runtime',
                  style: TextStyle(
                    color: model.runtime == RuntimePhase.loaded
                        ? CupertinoDynamicColor.resolve(
                            GolemTheme.accent,
                            context,
                          )
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
          child: GolemCard(
            child: Row(
              children: [
                const Icon(CupertinoIcons.speedometer),
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
                          color: CupertinoDynamicColor.resolve(
                            GolemTheme.mutedInk,
                            context,
                          ),
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
        GolemCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabeledRow(
                label: 'App',
                value: '${AppIdentity.current.displayName} 1.0.0',
              ),
              const SizedBox(height: 10),
              LabeledRow(
                label: 'Bundle',
                value: AppIdentity.current.applicationId,
              ),
              const SizedBox(height: 12),
              Text(
                [
                  if (model.simulated)
                    'Model downloads are a deterministic simulation of the pinned catalog; no network access exists.'
                  else
                    'Model downloads fetch the pinned artifacts above from Hugging Face over HTTPS.',
                  if (simulatedInference)
                    'Inference is a deterministic UI simulation — no model weights, engine, or hardware measurement is included.'
                  else
                    'Inference runs the local engine on this device with the active model.',
                  'Nothing else touches the network, and Golem reads no other app\'s data.',
                ].join(' '),
                style: TextStyle(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.mutedInk,
                    context,
                  ),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
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
  });

  final ModelCatalogEntry entry;
  final ArtifactStatus status;
  final bool simulated;
  final bool active;
  final bool otherDownloadActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(modelControllerProvider.notifier);
    final suffix = simulated ? ' · simulated' : '';
    final statusLabel = _statusLabel(suffix);
    return GolemCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'ACTIVE',
                    style: TextStyle(
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.accent,
                        context,
                      ),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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
          LabeledRow(label: 'Revision', value: entry.revision.substring(0, 12)),
          const SizedBox(height: 6),
          LabeledRow(
            label: 'Size',
            value:
                '${_gigabytes(entry.totalBytes)} · '
                '${entry.files.length} ${entry.files.length == 1 ? 'file' : 'files'}',
          ),
          ..._buttons(context, controller),
        ],
      ),
    );
  }

  List<Widget> _buttons(BuildContext context, ModelController controller) {
    final download = CupertinoButton.filled(
      key: Key('model-download-${entry.key}'),
      minimumSize: const Size.fromHeight(48),
      onPressed: otherDownloadActive
          ? null
          : () => controller.download(entry.key),
      child: Text(switch (status.phase) {
        ArtifactPhase.paused => 'Resume Download',
        ArtifactPhase.failed => 'Retry Download',
        _ => 'Download',
      }),
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
        CupertinoButton.filled(
          key: Key('model-pause-${entry.key}'),
          minimumSize: const Size.fromHeight(48),
          onPressed: () => controller.pause(entry.key),
          child: const Text('Pause'),
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
  ) => showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      key: const Key('model-delete-dialog'),
      title: Text('Delete ${entry.displayName}?'),
      content: Text(
        'Removes ${_gigabytes(entry.totalBytes)} from this device. '
        'The model can be downloaded again later.',
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Keep'),
        ),
        CupertinoDialogAction(
          key: const Key('confirm-model-delete'),
          isDestructiveAction: true,
          onPressed: () {
            Navigator.of(dialogContext).pop();
            controller.delete(entry.key);
          },
          child: const Text('Delete'),
        ),
      ],
    ),
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

/// Display names for the profile-keyed generation sections; the profile
/// registry is the source of which sections exist.
const _profileDisplayNames = {'gemma4': 'Gemma 4 E2B', 'qwen35': 'Qwen 3.5 4B'};

/// Context tokens the budget controls must always leave for the rendered
/// prompt: the engines reject any request whose prompt plus budget exceeds
/// the context, so a budget equal to the context would fail every send.
/// The reserve keeps short prompts working by construction; very long
/// chats can still exhaust it and surface the engines' budget error.
const _promptReserveTokens = 512;

class _GenerationCard extends ConsumerWidget {
  const _GenerationCard({required this.profileKey});

  final String profileKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = modelProfiles[profileKey]!;
    // The direct-mode defaults are the editable surface; thinking-mode
    // sampling can be pinned by the profile (see the footnote).
    final defaults = profile.sampling(reasoningEnabled: false);
    final thinking = profile.sampling(reasoningEnabled: true);
    final thinkingPinned = thinking.pinned;
    final overrides =
        ref.watch(settingsControllerProvider).value?.overridesFor(profileKey) ??
        const SamplingOverrides();
    final maxTokens = overrides.maxTokens ?? defaults.maxTokens;
    final contextLength = overrides.contextLength ?? defaults.contextLength;
    // A maxTokens override applies to both reasoning modes, but with no
    // override each mode keeps its own default — the clamp below must
    // satisfy the largest of them (Qwen's thinking budget is 4096 while
    // its direct budget is 2048).
    final effectiveBudget =
        overrides.maxTokens ?? max(defaults.maxTokens, thinking.maxTokens);

    Future<void> update(SamplingOverrides next) => ref
        .read(settingsControllerProvider.notifier)
        .updateModel(profileKey, next);

    return GolemCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _profileDisplayNames[profileKey] ?? profileKey,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (!overrides.isEmpty)
                CupertinoButton(
                  key: Key('gen-reset-$profileKey'),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 30),
                  onPressed: () => ref
                      .read(settingsControllerProvider.notifier)
                      .resetModel(profileKey),
                  child: const Text('Reset', style: TextStyle(fontSize: 14)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          _SliderRow(
            sliderKey: Key('gen-temperature-$profileKey'),
            label: 'Temperature',
            value: overrides.temperature ?? defaults.temperature,
            isDefault: overrides.temperature == null,
            min: 0,
            max: 2,
            display: (value) => value.toStringAsFixed(2),
            onCommit: (value) =>
                update(overrides.copyWith(temperature: () => value)),
          ),
          _SliderRow(
            sliderKey: Key('gen-top-p-$profileKey'),
            label: 'Top-p',
            value: overrides.topP ?? defaults.topP,
            isDefault: overrides.topP == null,
            min: 0.05,
            max: 1,
            display: (value) => value.toStringAsFixed(2),
            onCommit: (value) => update(overrides.copyWith(topP: () => value)),
          ),
          _SliderRow(
            sliderKey: Key('gen-top-k-$profileKey'),
            label: 'Top-k',
            value: (overrides.topK ?? defaults.topK ?? 0).toDouble(),
            isDefault: overrides.topK == null,
            min: 0,
            max: 100,
            display: (value) => value.round() == 0 ? 'Off' : '${value.round()}',
            onCommit: (value) => update(
              overrides.copyWith(
                topK: () => value.round() == 0 ? null : value.round(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _StepperRow(
            stepperKey: ValueKey<String>('gen-max-tokens-$profileKey'),
            label: 'Max tokens',
            value: maxTokens,
            isDefault: overrides.maxTokens == null,
            step: 256,
            min: 256,
            // The engines reject prompt + budget over the context, so the
            // budget must leave the prompt reserve free.
            max: contextLength - _promptReserveTokens,
            onCommit: (value) =>
                update(overrides.copyWith(maxTokens: () => value)),
          ),
          const SizedBox(height: 6),
          _StepperRow(
            stepperKey: ValueKey<String>('gen-context-$profileKey'),
            label: 'Context length',
            value: contextLength,
            isDefault: overrides.contextLength == null,
            step: 1024,
            min: 1024,
            max: 8192,
            onCommit: (value) => update(
              overrides.copyWith(
                contextLength: () => value,
                // Shrinking the context must keep every mode's effective
                // budget under it, prompt reserve included, or generation
                // in that mode would fail its budget check on every send.
                maxTokens: effectiveBudget > value - _promptReserveTokens
                    ? () => value - _promptReserveTokens
                    : null,
              ),
            ),
          ),
          if (thinkingPinned) ...[
            const SizedBox(height: 10),
            Text(
              'Thinking mode keeps this model\'s pinned sampling '
              '(temperature 0.6 · top-p 0.95); token budgets apply to both '
              'modes.',
              style: TextStyle(
                color: CupertinoDynamicColor.resolve(
                  GolemTheme.mutedInk,
                  context,
                ),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A labeled slider whose value commits on drag end; the drag position is
/// widget-local state so a drag never spams persisted saves.
class _SliderRow extends StatefulWidget {
  const _SliderRow({
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.isDefault,
    required this.min,
    required this.max,
    required this.display,
    required this.onCommit,
  });

  final Key sliderKey;
  final String label;
  final double value;
  final bool isDefault;
  final double min;
  final double max;
  final String Function(double value) display;
  final ValueChanged<double> onCommit;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final value = (_drag ?? widget.value).clamp(widget.min, widget.max);
    final muted = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.label, style: const TextStyle(fontSize: 14)),
            ),
            Text(widget.display(value), style: const TextStyle(fontSize: 14)),
            if (widget.isDefault && _drag == null)
              Text(' · default', style: TextStyle(fontSize: 14, color: muted)),
          ],
        ),
        SizedBox(
          height: 34,
          child: CupertinoSlider(
            key: widget.sliderKey,
            value: value,
            min: widget.min,
            max: widget.max,
            onChanged: (next) => setState(() => _drag = next),
            onChangeEnd: (next) {
              setState(() => _drag = null);
              widget.onCommit(next);
            },
          ),
        ),
      ],
    );
  }
}

/// A labeled stepped value with minus/plus buttons; steps snap to the
/// nearest multiple so a default like 2048 stays on the grid.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.stepperKey,
    required this.label,
    required this.value,
    required this.isDefault,
    required this.step,
    required this.min,
    required this.max,
    required this.onCommit,
  });

  final ValueKey<String> stepperKey;
  final String label;
  final int value;
  final bool isDefault;
  final int step;
  final int min;
  final int max;
  final ValueChanged<int> onCommit;

  @override
  Widget build(BuildContext context) {
    final muted = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    final lower = ((value - step) ~/ step) * step;
    final higher = ((value + step) ~/ step) * step;
    return Row(
      key: stepperKey,
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        CupertinoButton(
          key: Key('${stepperKey.value}-minus'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(38, 30),
          onPressed: value <= min
              ? null
              : () => onCommit(lower.clamp(min, max)),
          child: const Icon(CupertinoIcons.minus_circle, size: 22),
        ),
        SizedBox(
          width: 64,
          child: Column(
            children: [
              Text('$value', style: const TextStyle(fontSize: 14)),
              if (isDefault)
                Text('default', style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
        ),
        CupertinoButton(
          key: Key('${stepperKey.value}-plus'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(38, 30),
          onPressed: value >= max
              ? null
              : () => onCommit(higher.clamp(min, max)),
          child: const Icon(CupertinoIcons.plus_circle, size: 22),
        ),
      ],
    );
  }
}
