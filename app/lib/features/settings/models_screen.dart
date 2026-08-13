import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/chrome/golem_alert.dart';
import '../../core/chrome/golem_button.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/chrome/golem_toast.dart';
import '../../core/domain/app_preferences.dart';
import '../../core/domain/byte_format.dart';
import '../../core/domain/inference_backend.dart';
import '../../core/domain/model_activation.dart';
import '../../core/domain/model_catalog.dart';
import '../../core/domain/model_speed.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/repository_resolver.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/labeled_row.dart';
import '../../core/widgets/progress_track.dart';
import '../../core/widgets/retry_pane.dart';
import '../../core/widgets/section_header.dart';
import '../../l10n/l10n.dart';
import '../../l10n/presentation_messages.dart';
import '../chat/application/chat_providers.dart';
import '../models/application/model_providers.dart';
import '../onboarding/model_download_consent.dart';
import 'application/custom_repository_workflow.dart';
import 'application/preferences_providers.dart';
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
        title: context.l10n.models,
        previousPageTitle: context.l10n.settings,
      ),
      child: SafeArea(
        bottom: false,
        child: model.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (error, stack) => RetryPane(
            key: const Key('models-load-error'),
            message: context.l10n.modelsLoadFailed,
            actionLabel: context.l10n.tryAgain,
            onRetry: () => ref.invalidate(modelControllerProvider),
          ),
          data: (value) => _body(context, value),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ModelState model) {
    final catalog = ref.watch(effectiveModelCatalogProvider);
    final downloadableKeys = ref.watch(downloadableModelKeysProvider);
    final advanced =
        ref.watch(preferencesControllerProvider).value?.advancedMode ?? false;
    final simulatedInference = ref
        .watch(inferenceBackendProvider)
        .simulatedInference;
    // A device outside every supported tier may not start a transfer or a load
    // (#27); the cards say why instead of offering buttons that would refuse.
    final deviceRefusal = ref.watch(deviceRefusalProvider);
    final refusalMessage = deviceRefusal == null
        ? null
        : deviceRefusalMessage(
            context.l10n,
            ref.watch(deviceEligibilityProvider).reason,
          );
    // Verification holds the slot as surely as the transfer does — it runs
    // inside the same download() stream, behind the same busy guard — so a
    // button offered during it would do nothing when tapped. The chat picker
    // counts it; these cards must agree.
    final downloadingKey = model.artifacts.entries
        .where(
          (entry) =>
              entry.value.phase == ArtifactPhase.downloading ||
              entry.value.phase == ArtifactPhase.verifying,
        )
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
    final residentKey = ref.watch(inferenceResidencyProvider).catalogKey;
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
          segments: {
            _CatalogTab.all: Text(
              context.l10n.allModelsTitle,
              key: const Key('models-tab-all'),
              style: GolemText.footnoteStrong,
            ),
            _CatalogTab.installed: Text(
              context.l10n.installedModels,
              key: const Key('models-tab-installed'),
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
                  ? context.l10n.nothingInstalledSimulated
                  : context.l10n.nothingInstalled,
              key: const Key('models-empty'),
            ),
          ),
        for (final entry in visible) ...[
          _ModelCard(
            entry: entry,
            status: model.statusOf(entry.key),
            simulated: model.simulated,
            active: entry.key == activeKey,
            resident: entry.key == residentKey,
            otherDownloadActive:
                downloadingKey != null && downloadingKey != entry.key,
            downloadable: downloadableKeys.contains(entry.key),
            deviceRefusal: refusalMessage,
            defaultMeasuredKey: defaultMeasuredModelKey(backend, model),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        SectionHeader(context.l10n.runtime),
        const SizedBox(height: 8),
        _RuntimeCard(
          model: model,
          simulatedInference: simulatedInference,
          activeKey: activeKey,
          deviceRefusal: refusalMessage,
        ),
        if (advanced) ...[
          const SizedBox(height: 24),
          SectionHeader(context.l10n.customRepository),
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
              ? context.l10n.modelDownloadsSimulated
              : context.l10n.modelDownloadsReal,
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
                label: context.l10n.activeModel,
                value:
                    active?.displayName ??
                    // A sideload has no entry to name, so name its file.
                    (backend.sideloaded
                        ? sideloadedModelLabel(backend.modelPath!)
                        : simulatedInference
                        ? context.l10n.noneSimulatedInference
                        : context.l10n.none),
              ),
              const SizedBox(height: 10),
              LabeledRow(
                label: context.l10n.state,
                value: _runtimeLabel(
                  context,
                  model.runtime,
                  simulatedInference,
                ),
              ),
              if (model.failure != null) ...[
                const SizedBox(height: 10),
                Text(
                  context.l10n.modelRuntimeFailed,
                  style: const TextStyle(color: GolemTheme.destructive),
                ),
              ],
              const SizedBox(height: 14),
              // Withheld for loading only: a runtime phase persisted as loaded
              // by an earlier build must stay correctable, and toggleRuntime
              // permits that direction for the same reason.
              if (deviceRefusal == null || model.runtime == RuntimePhase.loaded)
                GolemButton.tinted(
                  key: const Key('runtime-toggle-button'),
                  label: model.runtime == RuntimePhase.loaded
                      ? simulatedInference
                            ? context.l10n.unloadSimulatedRuntime
                            : context.l10n.unloadRuntime
                      : simulatedInference
                      ? context.l10n.loadSimulatedRuntime
                      : context.l10n.loadRuntime,
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
  const _Refused(this.reason);

  final RepositoryRejection reason;
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
      RepositoryRejected(:final reason) => _Refused(reason),
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
        showGolemToast(context, context.l10n.modelSaveFailed);
      }
      return;
    }
    // The controllers and the draft state belong to the screen, which may be
    // gone: only it can decide whether resetting them is still meaningful.
    onAdded();
    if (context.mounted) showGolemToast(context, context.l10n.modelAdded);
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
                placeholder: context.l10n.repositoryRevisionPlaceholder,
                muted: muted,
              ),
              const SizedBox(height: 16),
              ..._outcome(context, ref, muted),
              const SizedBox(height: 12),
              Text(switch (state) {
                _Resolved(:final outcome) when outcome.profile == null =>
                  context.l10n.unknownTemplateWarning,
                _ when simulatedDownloads =>
                  context.l10n.simulatedRepositoryDetail,
                _ => context.l10n.publicRepositoryDetail,
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
    textDirection: TextDirection.ltr,
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
              context.l10n.readingRepository,
              style: GolemText.footnote.copyWith(color: muted),
            ),
          ),
        ],
      ),
    ],
    _Refused(:final reason) => [
      Text(
        key: const Key('custom-repo-error'),
        repositoryRejectionMessage(context.l10n, reason),
        style: GolemText.footnote.copyWith(
          color: CupertinoDynamicColor.resolve(GolemTheme.destructive, context),
        ),
      ),
      const SizedBox(height: 14),
      _resolveButton(ref, label: context.l10n.tryAgain),
    ],
    _WeightChoice(:final candidates) => [
      Text(
        context.l10n.chooseWeightFile,
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
                gigabytes(candidate.bytes),
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
            label: context.l10n.revision,
            // The commit, not the ref that was typed: this is what installs.
            value: outcome.resolved.commitSha.substring(0, 12),
          ),
          const SizedBox(height: 8),
          LabeledRow(
            label: context.l10n.quantization,
            value: outcome.resolved.quantization,
          ),
          const SizedBox(height: 8),
          LabeledRow(
            label: context.l10n.size,
            value: gigabytes(outcome.resolved.totalBytes),
          ),
          const SizedBox(height: 8),
          LabeledRow(
            label: context.l10n.promptProfile,
            value: outcome.profile?.key ?? context.l10n.notRecognized,
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
                    gigabytes(file.bytes),
                    style: GolemText.footnote.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          if (outcome.resolved.files.length > 5)
            Text(
              context.l10n.moreFiles(outcome.resolved.files.length - 5),
              style: GolemText.footnote.copyWith(color: muted),
            ),
        ],
      ),
      const SizedBox(height: 16),
      Builder(
        builder: (context) => GolemButton.filled(
          key: const Key('custom-repo-add'),
          label: context.l10n.addModel,
          onPressed: () => _add(context, ref, outcome),
        ),
      ),
    ],
  };

  Widget _resolveButton(WidgetRef ref, {String? label}) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => GolemButton.filled(
          key: const Key('custom-repo-resolve'),
          label: label ?? context.l10n.resolveRepository,
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
    required this.resident,
    required this.otherDownloadActive,
    required this.downloadable,
    required this.defaultMeasuredKey,
    this.deviceRefusal,
  });

  final ModelCatalogEntry entry;
  final ArtifactStatus status;
  final bool simulated;
  final bool active;
  final bool resident;
  final bool otherDownloadActive;

  /// False for hand-added entries on a real download backend, whose
  /// repository would reject the unknown key.
  final bool downloadable;

  /// Why this device may not fetch any weights at all, or null when it may.
  final String? deviceRefusal;

  /// What an unattributed metric belongs to, resolved once by the list rather
  /// than re-derived — and re-subscribed — per card.
  final String? defaultMeasuredKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(modelControllerProvider.notifier);
    final suffix = simulated ? ' · ${context.l10n.simulated}' : '';
    final statusLabel = _statusLabel(context, suffix);
    final chats = ref.watch(chatControllerProvider).value?.conversations;
    // Attribution comes from the shared helper, not a local fallback: the
    // picker quotes the same numbers, and a different default had one surface
    // showing a rate the other did not (#79).
    final measured = chats == null
        ? null
        : measuredTokensPerSecond(
            chats,
            modelKey: entry.key,
            defaultModelKey: defaultMeasuredKey,
          );
    return GolemCard(
      child: Column(
        key: Key('model-card-${entry.key}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.displayName, style: GolemText.cardTitle),
          const SizedBox(height: 5),
          Text(
            '${engineLabel(entry.engine)} · ${entry.quantization}',
            style: TextStyle(
              color: CupertinoDynamicColor.resolve(
                GolemTheme.mutedInk,
                context,
              ),
            ),
          ),
          if (active || resident) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (active)
                  _ModelStateBadge(
                    label: context.l10n.activeBadge,
                    emphasized: true,
                  ),
                if (resident) _ModelStateBadge(label: context.l10n.loadedBadge),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Semantics(
            key: Key('model-status-${entry.key}'),
            label: context.l10n.modelStatusLabel(
              entry.displayName,
              engineLabel(entry.engine),
            ),
            value: statusLabel,
            child: _Status(icon: _statusIcon(), label: statusLabel),
          ),
          if (status.phase == ArtifactPhase.downloading ||
              status.phase == ArtifactPhase.paused) ...[
            const SizedBox(height: 14),
            _Progress(
              progressKey: Key('model-progress-${entry.key}'),
              value: entry.totalBytes == 0
                  ? 0
                  : (status.downloadedBytes / entry.totalBytes).clamp(0, 1),
              label: context.l10n.downloadProgressLabel(suffix),
            ),
          ],
          if (status.phase == ArtifactPhase.verifying) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const CupertinoActivityIndicator(),
                const SizedBox(width: 10),
                Text(context.l10n.verifyingFilesStatus(suffix)),
              ],
            ),
          ],
          if (status.phase == ArtifactPhase.failed) ...[
            const SizedBox(height: 10),
            Text(
              artifactFailureMessage(context.l10n, status),
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
              label: context.l10n.openRepository(entry.repository),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: LabeledRow(
                        label: context.l10n.repository,
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
            label: context.l10n.revision,
            value: entry.revision.length > 12
                ? entry.revision.substring(0, 12)
                : entry.revision,
          ),
          const SizedBox(height: 6),
          LabeledRow(
            label: context.l10n.size,
            value: context.l10n.modelSizeAndFiles(
              gigabytes(entry.totalBytes),
              entry.files.length,
            ),
          ),
          if (measured != null) ...[
            const SizedBox(height: 6),
            LabeledRow(
              label: context.l10n.measured,
              // Honesty: the fake's canned rate is never sold as hardware.
              value: simulated
                  ? context.l10n.measuredSimulated(measured.toStringAsFixed(1))
                  : context.l10n.measuredOnPhone(measured.toStringAsFixed(1)),
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
              ArtifactPhase.paused => context.l10n.resumeDownload,
              ArtifactPhase.failed => context.l10n.retryDownload,
              _ => context.l10n.downloadSizeAction(gigabytes(entry.totalBytes)),
            },
            onPressed: otherDownloadActive || !downloadable
                ? null
                : () async {
                    if (status.phase == ArtifactPhase.notDownloaded) {
                      final approved = await confirmModelDownload(
                        context: context,
                        entry: entry,
                        simulated: simulated,
                      );
                      if (!approved || !context.mounted) return;
                    }
                    controller.download(entry.key);
                  },
          ),
        if (!downloadable || deviceRefusal != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              // An unresolved repository is the more specific problem: it can
              // be fixed here, while the device verdict cannot. One predicate
              // decides the copy and the key together, or a card ends up
              // labelled as one refusal while reading as the other.
              key: downloadable
                  ? Key('model-device-refusal-${entry.key}')
                  : null,
              downloadable
                  ? deviceRefusal!
                  : context.l10n.unresolvedRepositoryReason,
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
      child: Text(
        context.l10n.cancelAndDiscard,
        style: const TextStyle(color: GolemTheme.destructive),
      ),
    );
    return switch (status.phase) {
      ArtifactPhase.notDownloaded => [const SizedBox(height: 14), download],
      ArtifactPhase.downloading => [
        const SizedBox(height: 14),
        GolemButton.tinted(
          key: Key('model-pause-${entry.key}'),
          label: context.l10n.pause,
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
          child: Text(
            context.l10n.deleteDownload,
            style: const TextStyle(color: GolemTheme.destructive),
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
    // Display names no longer carry a quantization, so two artifacts of one
    // family share one (#79). A destructive dialog must still say which.
    title: context.l10n.deleteModelArtifactTitle(
      entry.displayName,
      engineFormat(entry.engine),
    ),
    message: context.l10n.deleteModelStorageMessage(
      gigabytes(entry.totalBytes),
    ),
    actions: [
      GolemAlertAction(
        label: context.l10n.keep,
        onPressed: () => Navigator.pop(context),
      ),
      GolemAlertAction(
        key: const Key('confirm-model-delete'),
        label: context.l10n.delete,
        isDestructive: true,
        onPressed: () {
          Navigator.pop(context);
          controller.delete(entry.key);
        },
      ),
    ],
  );

  String _statusLabel(BuildContext context, String suffix) =>
      switch (status.phase) {
        ArtifactPhase.notDownloaded => context.l10n.notDownloaded,
        ArtifactPhase.downloading => context.l10n.downloadingAmountStatus(
          gigabytes(status.downloadedBytes),
          gigabytes(entry.totalBytes),
          suffix,
        ),
        ArtifactPhase.paused => context.l10n.pausedAtStatus(
          gigabytes(status.downloadedBytes),
          suffix,
        ),
        ArtifactPhase.verifying => context.l10n.verifyingStatus(suffix),
        ArtifactPhase.installed => context.l10n.installedVerifiedStatus(suffix),
        ArtifactPhase.failed => context.l10n.downloadFailed,
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

class _ModelStateBadge extends StatelessWidget {
  const _ModelStateBadge({required this.label, this.emphasized = false});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(
        emphasized ? GolemTheme.accentSoft : GolemTheme.fillQuiet,
        context,
      ),
      borderRadius: BorderRadius.circular(GolemRadius.badge),
    ),
    child: Text(
      label,
      style:
          localizedLabelStyle(
            GolemText.badge,
            Localizations.localeOf(context),
          ).copyWith(
            color: emphasized
                ? CupertinoDynamicColor.resolve(GolemTheme.accent, context)
                : null,
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
  const _Progress({required this.value, required this.label, this.progressKey});
  final double value;
  final String label;
  final Key? progressKey;

  @override
  // The bar carries no semantics of its own, and split across three nodes the
  // caption and the number read as unrelated fragments. Deliberately not a
  // live region: re-announcing every tick of a multi-gigabyte download would
  // talk over everything else on the screen.
  Widget build(BuildContext context) => Semantics(
    key: progressKey,
    container: true,
    label: label,
    value: context.l10n.percentValue((value * 100).round()),
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 13)),
              ),
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
      ),
    ),
  );
}

String _runtimeLabel(
  BuildContext context,
  RuntimePhase phase,
  bool simulated,
) => switch (phase) {
  RuntimePhase.unloaded => context.l10n.unloaded,
  RuntimePhase.loading =>
    simulated ? context.l10n.loadingSimulation : context.l10n.loading,
  RuntimePhase.loaded =>
    simulated ? context.l10n.readySimulated : context.l10n.ready,
  RuntimePhase.failed => context.l10n.stopped,
};
