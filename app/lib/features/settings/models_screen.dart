import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/chrome/golem_alert.dart';
import '../../core/chrome/golem_button.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/chrome/golem_toast.dart';
import '../../core/domain/app_preferences.dart';
import '../../core/domain/inference_backend.dart';
import '../../core/domain/model_activation.dart';
import '../../core/domain/model_catalog.dart';
import 'domain/model_speed.dart';
import '../../core/domain/models.dart';
import '../../core/services/repository_resolver.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/labeled_row.dart';
import '../../core/widgets/progress_track.dart';
import '../../core/widgets/retry_pane.dart';
import '../../core/widgets/section_header.dart';
import 'application/custom_repository_workflow.dart';
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
  // Ephemeral screen state stays widget-local: the tab, the custom repository
  // draft, its engine chip, and what resolving it found. The resolution lives
  // here rather than in the card because the list disposes off-screen children
  // — scrolling away and back would otherwise silently discard it.
  _CatalogTab _tab = _CatalogTab.all;
  final _repositoryController = TextEditingController();
  final _revisionController = TextEditingController();
  ModelEngine _customEngine = ModelEngine.mlx;
  _AddState _addState = const _Unresolved();

  @override
  void dispose() {
    _repositoryController.dispose();
    _revisionController.dispose();
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
          error: (error, stack) => RetryPane(
            key: const Key('models-load-error'),
            message: "Couldn't load model state.",
            onRetry: () => ref.invalidate(modelControllerProvider),
          ),
          data: (value) => _body(context, value),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ModelState model) {
    final catalog = ref.watch(effectiveModelCatalogProvider);
    final pinnedKeys = {
      for (final entry in ref.watch(modelCatalogEntriesProvider)) entry.key,
    };
    // A hand-added repository can be fetched once it has resolved: its file
    // list is then real. An unresolved one still cannot, because its files are
    // synthesized and nothing would be on the other end of the request.
    final resolvedKeys = {
      for (final spec
          in ref.watch(preferencesControllerProvider).value?.customModels ??
              const <CustomModelSpec>[])
        if (spec.resolved != null) spec.key,
    };
    final advanced =
        ref.watch(preferencesControllerProvider).value?.advancedMode ?? false;
    final simulatedInference = ref
        .watch(inferenceBackendProvider)
        .simulatedInference;
    // A device outside every supported tier may not start a transfer or a load
    // (#27); the cards say why instead of offering buttons that would refuse.
    final eligibility = ref.watch(deviceEligibilityProvider);
    final deviceRefusal = simulatedInference || eligibility.runsModels
        ? null
        : eligibility.message;
    final downloadingKey = model.artifacts.entries
        .where((entry) => entry.value.phase == ArtifactPhase.downloading)
        .map((entry) => entry.key)
        .firstOrNull;
    // Real builds hide artifacts their composed engine can never load —
    // an enabled multi-gigabyte MLX download on a llama-only build would
    // be dead disk (#63). Installed leftovers stay visible (and
    // deletable) here and in Storage; the fake keeps the whole catalog.
    final backend = ref.watch(inferenceBackendProvider);
    // Which artifact is live must read the same everywhere: chat, here, and
    // Storage all resolve it through the one helper (#20).
    final activeKey = effectiveModelKey(
      backend: backend,
      catalog: catalog,
      modelKey: ref.watch(
        chatControllerProvider.select((state) => state.value?.active?.modelKey),
      ),
      residentModelKey: ref.watch(residentModelKeyProvider),
      loadableKeys: ref.watch(loadableModelKeysProvider),
    );
    final loadable = catalog
        .where(
          (entry) =>
              simulatedInference ||
              model.statusOf(entry.key).phase == ArtifactPhase.installed ||
              backend.kind.loads(entry.engine),
        )
        .toList();
    final visible = _tab == _CatalogTab.all
        ? loadable
        : loadable
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
            active: entry.key == activeKey,
            otherDownloadActive:
                downloadingKey != null && downloadingKey != entry.key,
            downloadable:
                model.simulated ||
                pinnedKeys.contains(entry.key) ||
                resolvedKeys.contains(entry.key),
            deviceRefusal: deviceRefusal,
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        const SectionHeader('Runtime'),
        const SizedBox(height: 8),
        _RuntimeCard(
          model: model,
          simulatedInference: simulatedInference,
          activeKey: activeKey,
          deviceRefusal: deviceRefusal,
        ),
        if (advanced) ...[
          const SizedBox(height: 24),
          const SectionHeader('Custom repository'),
          const SizedBox(height: 8),
          _CustomRepositoryCard(
            controller: _repositoryController,
            revisionController: _revisionController,
            state: _addState,
            // Resolving a repository takes seconds of network, and Back is one
            // tap: both callbacks can land after this screen is gone.
            onState: (state) {
              if (mounted) setState(() => _addState = state);
            },
            onAdded: () {
              if (!mounted) return;
              _repositoryController.clear();
              _revisionController.clear();
              setState(() => _addState = const _Unresolved());
            },
            engine: _customEngine,
            onEngine: (engine) => setState(() {
              _customEngine = engine;
              // A resolution belongs to one engine's file selection.
              _addState = const _Unresolved();
            }),
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
  const _RuntimeCard({
    required this.model,
    required this.simulatedInference,
    required this.activeKey,
    this.deviceRefusal,
  });
  final ModelState model;
  final bool simulatedInference;
  final String? activeKey;

  /// Why this device may not load a model, or null when it may.
  final String? deviceRefusal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(effectiveModelCatalogProvider);
    final backend = ref.watch(inferenceBackendProvider);
    final active = catalog.where((entry) => entry.key == activeKey).firstOrNull;
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
                    // A sideload has no entry to name, so name its file.
                    (backend.sideloaded
                        ? sideloadedModelLabel(backend.modelPath!)
                        : simulatedInference
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
              if (deviceRefusal == null)
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
              if (deviceRefusal != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    deviceRefusal!,
                    key: const Key('runtime-device-refusal'),
                    style: GolemText.footnote.copyWith(
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.mutedInk,
                        context,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What the Add flow has learned about the repository currently in the field.
sealed class _AddState {
  const _AddState();
}

final class _Unresolved extends _AddState {
  const _Unresolved();
}

final class _Resolving extends _AddState {
  const _Resolving();
}

final class _Resolved extends _AddState {
  const _Resolved(this.outcome);

  final RepositoryResolved outcome;
}

final class _WeightChoice extends _AddState {
  const _WeightChoice(this.candidates);

  final List<ResolvedWeightCandidate> candidates;
}

final class _Refused extends _AddState {
  const _Refused(this.message);

  final String message;
}

class _CustomRepositoryCard extends ConsumerWidget {
  const _CustomRepositoryCard({
    required this.controller,
    required this.revisionController,
    required this.state,
    required this.onState,
    required this.onAdded,
    required this.engine,
    required this.onEngine,
    required this.simulatedDownloads,
  });

  final TextEditingController controller;
  final TextEditingController revisionController;

  /// Owned by the screen, so scrolling this card off-list cannot discard it.
  final _AddState state;
  final ValueChanged<_AddState> onState;

  /// Clears the draft once a spec is persisted. Owned by the screen for the
  /// same reason [state] is, and because it touches the two controllers.
  final VoidCallback onAdded;

  final ModelEngine engine;
  final ValueChanged<ModelEngine> onEngine;

  /// Both backends resolve, so only the copy differs — a simulated size is
  /// never presented as something that was measured.
  final bool simulatedDownloads;

  String get _ref => revisionController.text.trim().isEmpty
      ? 'main'
      : revisionController.text.trim();

  /// Any edit makes an existing resolution stale, and showing a commit and file
  /// list for a repository the user has since retyped is worse than nothing.
  void _invalidate() {
    if (state is! _Unresolved) onState(const _Unresolved());
  }

  Future<void> _resolve(WidgetRef ref, {String? weightsFile}) async {
    final repository = controller.text.trim();
    if (repository.isEmpty) return;
    // Every seam is read before the first await; the workflow owns the
    // collision derivation and the resolver's failure contract.
    final workflow = CustomRepositoryWorkflow(
      resolver: ref.read(customRepositoryResolverProvider),
    );
    final pinned = ref.read(modelCatalogEntriesProvider);
    final custom =
        ref.read(preferencesControllerProvider).value?.customModels ??
        const <CustomModelSpec>[];
    onState(const _Resolving());
    final outcome = await workflow.resolve(
      repository: repository,
      engine: engine,
      ref: _ref,
      weightsFile: weightsFile,
      pinned: pinned,
      custom: custom,
    );
    onState(switch (outcome) {
      RepositoryResolved() => _Resolved(outcome),
      RepositoryNeedsWeightChoice(:final candidates) => _WeightChoice(
        candidates,
      ),
      RepositoryRejected(:final message) => _Refused(message),
    });
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    RepositoryResolved outcome,
  ) async {
    final preferences = ref.read(preferencesControllerProvider.notifier);
    final added = await preferences.addCustomModel(
      CustomModelSpec(
        repository: controller.text.trim(),
        engine: engine,
        revision: _ref,
        profile: outcome.profile,
        resolved: outcome.resolved,
      ),
    );
    if (!added) {
      // The preference write failed and rolled back; the resolution card is
      // still on screen, so Add remains the retry affordance.
      if (context.mounted) {
        showGolemToast(context, "Couldn't save the model. Try again.");
      }
      return;
    }
    // The controllers and the draft state belong to the screen, which may be
    // gone: only it can decide whether resetting them is still meaningful.
    onAdded();
    if (context.mounted) showGolemToast(context, 'Model added');
  }

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
              _field(
                context,
                key: const Key('custom-repo-field'),
                controller: controller,
                placeholder: engine == ModelEngine.mlx
                    ? 'mlx-community/model-name'
                    : 'org/model-name-GGUF',
                muted: muted,
              ),
              const SizedBox(height: 10),
              _field(
                context,
                key: const Key('custom-repo-revision'),
                controller: revisionController,
                placeholder: 'main — or a branch, tag, or commit',
                muted: muted,
              ),
              const SizedBox(height: 16),
              ..._outcome(context, ref, muted),
              const SizedBox(height: 12),
              Text(switch (state) {
                _Resolved(:final outcome) when outcome.profile == null =>
                  'This will download and can be deleted, but Golem cannot '
                      'prompt it: its chat template is not one this version '
                      'recognizes.',
                _ when simulatedDownloads =>
                  'This build simulates downloads, so the revision and size '
                      'below are synthesized rather than read from Hugging '
                      'Face.',
                _ =>
                  'Only public repositories are supported. Nothing downloads '
                      'until you have seen what resolving found.',
              }, style: GolemText.footnote.copyWith(color: muted)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(
    BuildContext context, {
    required Key key,
    required TextEditingController controller,
    required String placeholder,
    required Color muted,
  }) => CupertinoTextField(
    key: key,
    controller: controller,
    placeholder: placeholder,
    autocorrect: false,
    enableSuggestions: false,
    onChanged: (_) => _invalidate(),
    style: GolemText.code,
    placeholderStyle: GolemText.code.copyWith(color: muted),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    decoration: BoxDecoration(
      border: Border.all(
        color: CupertinoDynamicColor.resolve(GolemTheme.borderStrong, context),
      ),
      borderRadius: BorderRadius.circular(GolemRadius.field),
    ),
  );

  List<Widget> _outcome(
    BuildContext context,
    WidgetRef ref,
    Color muted,
  ) => switch (state) {
    _Unresolved() => [_resolveButton(ref)],
    _Resolving() => [
      Row(
        children: [
          const CupertinoActivityIndicator(radius: 8),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Reading the repository…',
              style: GolemText.footnote.copyWith(color: muted),
            ),
          ),
        ],
      ),
    ],
    _Refused(:final message) => [
      Text(
        key: const Key('custom-repo-error'),
        message,
        style: GolemText.footnote.copyWith(
          color: CupertinoDynamicColor.resolve(GolemTheme.destructive, context),
        ),
      ),
      const SizedBox(height: 14),
      _resolveButton(ref, label: 'Try again'),
    ],
    _WeightChoice(:final candidates) => [
      Text(
        'This repository holds several weight files. Choose the one to '
        'install:',
        style: GolemText.footnote.copyWith(color: muted),
      ),
      const SizedBox(height: 10),
      for (final candidate in candidates)
        CupertinoButton(
          key: Key('custom-repo-candidate-${candidate.path}'),
          padding: const EdgeInsets.symmetric(vertical: 6),
          minimumSize: const Size(44, 44),
          onPressed: () => _resolve(ref, weightsFile: candidate.path),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  candidate.path,
                  style: GolemText.code,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _gigabytes(candidate.bytes),
                style: GolemText.footnote.copyWith(color: muted),
              ),
            ],
          ),
        ),
    ],
    _Resolved(:final outcome) => [
      Column(
        key: const Key('custom-repo-detail'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabeledRow(
            label: 'Revision',
            // The commit, not the ref that was typed: this is what installs.
            value: outcome.resolved.commitSha.substring(0, 12),
          ),
          const SizedBox(height: 8),
          LabeledRow(
            label: 'Quantization',
            value: outcome.resolved.quantization,
          ),
          const SizedBox(height: 8),
          LabeledRow(
            label: 'Size',
            value: _gigabytes(outcome.resolved.totalBytes),
          ),
          const SizedBox(height: 8),
          LabeledRow(
            label: 'Prompt profile',
            value: outcome.profile?.key ?? 'Not recognized',
          ),
          const SizedBox(height: 12),
          for (final file in outcome.resolved.files.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      file.path,
                      style: GolemText.code.copyWith(color: muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _gigabytes(file.bytes),
                    style: GolemText.footnote.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          if (outcome.resolved.files.length > 5)
            Text(
              '+ ${outcome.resolved.files.length - 5} more files',
              style: GolemText.footnote.copyWith(color: muted),
            ),
        ],
      ),
      const SizedBox(height: 16),
      Builder(
        builder: (context) => GolemButton.filled(
          key: const Key('custom-repo-add'),
          label: 'Add model',
          onPressed: () => _add(context, ref, outcome),
        ),
      ),
    ],
  };

  Widget _resolveButton(WidgetRef ref, {String label = 'Resolve'}) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => GolemButton.filled(
          key: const Key('custom-repo-resolve'),
          label: label,
          onPressed: value.text.trim().isEmpty ? null : () => _resolve(ref),
        ),
      );
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
    this.deviceRefusal,
  });

  final ModelCatalogEntry entry;
  final ArtifactStatus status;
  final bool simulated;
  final bool active;
  final bool otherDownloadActive;

  /// False for hand-added entries on a real download backend, whose
  /// repository would reject the unknown key.
  final bool downloadable;

  /// Why this device may not fetch any weights at all, or null when it may.
  final String? deviceRefusal;

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
        // A refused device gets the explanation in place of the button rather
        // than beneath it: a full-width accent CTA that does nothing when
        // tapped would undo the honesty the copy is there to provide.
        if (deviceRefusal == null)
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
        if (!downloadable || deviceRefusal != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              key: deviceRefusal == null
                  ? null
                  : Key('model-device-refusal-${entry.key}'),
              // An unresolved repository is the more specific problem: it can
              // be fixed here, while the device verdict cannot.
              downloadable
                  ? deviceRefusal!
                  : 'This repository has not been resolved against Hugging '
                        'Face, so its files are unknown. Add it again to '
                        'resolve it.',
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
