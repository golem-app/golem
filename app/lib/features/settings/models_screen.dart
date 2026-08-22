import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/chrome/golem_alert.dart';
import '../../core/chrome/golem_badge.dart';
import '../../core/chrome/golem_button.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/domain/byte_format.dart';
import '../../core/domain/inference_backend.dart';
import '../../core/domain/model_activation.dart';
import '../../core/domain/model_catalog.dart';
import '../../core/domain/model_speed.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/labeled_row.dart';
import '../../core/widgets/retry_pane.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/settings_rows.dart';
import '../../l10n/l10n.dart';
import '../../l10n/presentation_messages.dart';
import '../chat/application/active_model_providers.dart';
import '../chat/application/chat_providers.dart';
import '../models/application/download_pace_providers.dart';
import '../models/application/model_providers.dart';
import '../models/artifact_transfer.dart';
import '../models/model_download_consent.dart';
import '../models/widgets/custom_repository_card.dart';
import '../models/widgets/download_note_banner.dart';
import '../models/widgets/transfer_card.dart';
import '../preferences/application/preferences_providers.dart';

enum _CatalogTab { all, installed }

/// Models & downloads: the catalog cards, the runtime, and — in Advanced
/// mode — the custom repository loader.
class ModelsScreen extends ConsumerStatefulWidget {
  const ModelsScreen({super.key});

  @override
  ConsumerState<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends ConsumerState<ModelsScreen> {
  // The tab is the only ephemeral state left here; the custom-repository draft
  // outlived this screen's own lifetime and moved to a controller (#129).
  _CatalogTab _tab = _CatalogTab.all;

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
    // Matches the chat screen's own busy predicate: `failed` is sticky until
    // the user retries or discards, and must not disable these controls —
    // the failure copy sends them here to free memory (#124).
    final generating = ref.watch(
      chatControllerProvider.select((state) {
        final phase = state.value?.generation;
        return phase == GenerationPhase.preparing ||
            phase == GenerationPhase.streaming;
      }),
    );
    final catalog = ref.watch(effectiveModelCatalogProvider);
    final downloadableKeys = ref.watch(downloadableModelKeysProvider);
    final advanced =
        ref.watch(preferencesControllerProvider).value?.advancedMode ?? false;
    final simulatedInference = ref
        .watch(inferenceBackendProvider)
        .simulatedInference;
    // A device outside every supported tier may not start a transfer or a load
    // (#27); the cards say why instead of offering buttons that would refuse.
    final refusal = ref.watch(deviceRefusalProvider);
    final refusalMessage = refusal == null
        ? null
        : deviceRefusalMessage(context.l10n, refusal);
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
    // Storage all watch the one derivation (#20, #129).
    final activeKey = ref.watch(activeModelKeyProvider);
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
            generating: generating,
            active: entry.key == activeKey,
            resident: entry.key == residentKey,
            otherDownloadActive:
                downloadingKey != null && downloadingKey != entry.key,
            downloadable: downloadableKeys.contains(entry.key),
            refusalMessage: refusalMessage,
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
          generating: generating,
          activeKey: activeKey,
          refusalMessage: refusalMessage,
        ),
        if (advanced) ...[
          const SizedBox(height: 24),
          SectionHeader(context.l10n.customRepository),
          const SizedBox(height: 8),
          CustomRepositoryCard(
            // Keyed: adding a repository grows the list above this card, and
            // an unkeyed child at a shifted index is rebuilt from scratch.
            key: const Key('custom-repository-card'),
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
    required this.generating,
    required this.simulatedInference,
    required this.activeKey,
    this.refusalMessage,
  });
  final ModelState model;
  final bool simulatedInference;
  final String? activeKey;

  /// Unloading mid-answer would truncate it, so the controller refuses;
  /// disabling says so before the tap (#124).
  final bool generating;

  /// Why this device may not load a model, or null when it may.
  final String? refusalMessage;

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
              if (refusalMessage == null ||
                  model.runtime == RuntimePhase.loaded)
                GolemButton.tinted(
                  key: const Key('runtime-toggle-button'),
                  label: model.runtime == RuntimePhase.loaded
                      ? simulatedInference
                            ? context.l10n.unloadSimulatedRuntime
                            : context.l10n.unloadRuntime
                      : simulatedInference
                      ? context.l10n.loadSimulatedRuntime
                      : context.l10n.loadRuntime,
                  // Withheld in either direction while an answer streams: the
                  // controller refuses both arms then, and a simulated backend
                  // streams its whole answer on an `unloaded` phase (#124).
                  onPressed: model.runtime == RuntimePhase.loading || generating
                      ? null
                      : () => ref
                            .read(modelControllerProvider.notifier)
                            .toggleRuntime(),
                ),
              if (refusalMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    refusalMessage!,
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

class _ModelCard extends ConsumerWidget {
  const _ModelCard({
    required this.entry,
    required this.status,
    required this.simulated,
    required this.generating,
    required this.active,
    required this.resident,
    required this.otherDownloadActive,
    required this.downloadable,
    required this.defaultMeasuredKey,
    this.refusalMessage,
  });

  final ModelCatalogEntry entry;

  /// Deleting or unloading the resident weights mid-answer would truncate it,
  /// so the controller refuses; disabling says so before the tap (#124).
  final bool generating;
  final ArtifactStatus status;
  final bool simulated;
  final bool active;
  final bool resident;
  final bool otherDownloadActive;

  /// False for hand-added entries on a real download backend, whose
  /// repository would reject the unknown key.
  final bool downloadable;

  /// Why this device may not fetch any weights at all, or null when it may.
  final String? refusalMessage;

  /// What an unattributed metric belongs to, resolved once by the list rather
  /// than re-derived — and re-subscribed — per card.
  final String? defaultMeasuredKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(modelControllerProvider.notifier);
    final suffix = simulated ? ' · ${context.l10n.simulated}' : '';
    final statusLabel = _statusLabel(context, suffix);
    // The bar names its own phase: "Download" over a hash read as a download
    // regressing from 100 % to 27 %.
    final barLabel = status.phase == ArtifactPhase.verifying
        ? context.l10n.verifyingStatus(suffix)
        : context.l10n.downloadProgressLabel(suffix);
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
                if (active) GolemBadge(label: context.l10n.activeBadge),
                if (resident) GolemBadge.quiet(label: context.l10n.loadedBadge),
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
              status.phase == ArtifactPhase.verifying ||
              status.phase == ArtifactPhase.paused) ...[
            const SizedBox(height: 14),
            TransferCard(
              key: Key('model-progress-${entry.key}'),
              transfer: artifactTransfer(
                entry: entry,
                status: status,
                localizations: context.l10n,
                // Only a running phase has a pace; watching it while paused
                // would rebuild this card on every tick of a transfer
                // belonging to another one.
                pace: status.phase == ArtifactPhase.paused
                    ? null
                    : ref.watch(downloadPaceProvider),
                simulated: simulated,
              ),
              density: TransferDensity.dense,
              semanticsLabel: barLabel,
              caption: barLabel,
              // The status row above already reads "Downloading 1.42 GB of
              // 3.30 GB · simulated"; the card does not say it twice.
              showBytes: false,
            ),
          ],
          // Inside the card, not hoisted above the list: slotted at the top it
          // appeared and vanished with the phase — on every pause, and on every
          // file boundary of a multi-file artifact — and shifted every card
          // beneath it under a reader who had scrolled (#125). Here nothing
          // above the card it describes can move.
          // A mount guard, not a second visibility rule: `downloadNoteVisible`
          // stays the one statement of when the note renders, and this is
          // deliberately wider than it, so widening that rule can never be
          // hidden here. It exists because this is the only surface with a
          // card per catalog entry — mounting the note on all of them costs a
          // note provider each, and the churn strands provider-dispose timers
          // in the widget tests.
          if (status.phase == ArtifactPhase.downloading ||
              status.phase == ArtifactPhase.verifying ||
              status.phase == ArtifactPhase.paused)
            DownloadNoteBanner(
              key: Key('model-download-note-${entry.key}'),
              entry: entry,
              margin: const EdgeInsetsDirectional.only(top: 14),
            ),
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
        if (refusalMessage == null)
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
        if (!downloadable || refusalMessage != null)
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
                  ? refusalMessage!
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
    final cancel = GolemButton.destructive(
      key: Key('model-cancel-${entry.key}'),
      label: context.l10n.cancelAndDiscard,
      onPressed: () => controller.cancel(entry.key),
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
        GolemButton.destructive(
          key: Key('model-delete-${entry.key}'),
          label: context.l10n.deleteDownload,
          onPressed: generating
              ? null
              : () => _confirmDelete(context, controller),
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
