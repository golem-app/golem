import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/model_catalog.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/domain/models.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/presentation_messages.dart';
import '../../models/application/model_providers.dart';
import '../../models/artifact_transfer.dart';
import '../../models/model_download_consent.dart';
import '../application/lab_bench_controller.dart';
import '../application/lab_contract.dart';
import '../application/lab_providers.dart';
import '../domain/lab_configuration.dart';
import '../lab_copy.dart';
import '../lab_theme.dart';
import 'lab_controls.dart';

/// The Rig (#58): what is armed, whether its artifact is verified, and the
/// contract a run will carry — locked, all of it, while a run is in flight.
/// The machine it runs on sits with the engine pins in the sidebar.
class RigBar extends ConsumerWidget {
  const RigBar({required this.onOpenSettings, super.key});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Selected: the bench state is reassigned every publish, and neither
    // the armed configuration nor the lock can move while a run flies.
    final (armed, locked) = ref.watch(
      labBenchControllerProvider.select((s) => (s.armed, s.locked)),
    );
    final families = ref.watch(labModelFamiliesProvider);
    final groups = <Widget>[
      if (locked) ...[
        Container(
          key: const Key('lab-rig-locked'),
          height: LabSize.control,
          padding: const EdgeInsets.symmetric(horizontal: LabSpace.s4),
          decoration: BoxDecoration(
            color: labResolve(GolemTheme.cautionSurface, context),
            borderRadius: BorderRadius.circular(LabRadius.chip),
            border: Border.all(
              color: labResolve(GolemTheme.cautionBorder, context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.lock_fill,
                size: 13,
                color: labResolve(GolemTheme.cautionIcon, context),
              ),
              const SizedBox(width: LabSpace.s2),
              Text(
                l10n.labLocked,
                style: LabText.label.copyWith(color: context.ink),
              ),
              const SizedBox(width: LabSpace.s2),
              Flexible(
                child: Text(
                  l10n.labLockedDetail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LabText.row.copyWith(color: context.mutedInk),
                ),
              ),
            ],
          ),
        ),
        Text(
          '${armed!.displayName} · ${engineLabel(armed.engine)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LabText.label.copyWith(color: context.ink),
        ),
      ] else ...[
        _Chooser(
          key: const Key('lab-model-menu'),
          label: armed?.displayName ?? l10n.labChooseModel,
          semanticLabel: l10n.labChooseModel,
          placeholder: armed == null,
          items: [
            for (final family in families)
              _ChooserItem(
                key: Key('lab-model-${family.id}'),
                label: family.displayName,
                selected: family.displayName == armed?.displayName,
                onPressed: () => ref
                    .read(labBenchControllerProvider.notifier)
                    .arm(
                      (family.on(
                                armed?.engine ??
                                    family.configurations.first.engine,
                              ) ??
                              family.configurations.first)
                          .key,
                    ),
              ),
          ],
        ),
        _Chooser(
          key: const Key('lab-engine-menu'),
          label: armed == null
              ? l10n.labChooseEngine
              : engineLabel(armed.engine),
          semanticLabel: l10n.labChooseEngine,
          placeholder: armed == null,
          items: [
            for (final engine in ModelEngine.values)
              _ChooserItem(
                key: Key('lab-engine-${engine.name}'),
                label: engineLabel(engine),
                selected: engine == armed?.engine,
                onPressed: () {
                  final family = families
                      .where((f) => f.displayName == armed?.displayName)
                      .firstOrNull;
                  final target =
                      family?.on(engine) ??
                      families.map((f) => f.on(engine)).nonNulls.firstOrNull;
                  if (target != null) {
                    ref
                        .read(labBenchControllerProvider.notifier)
                        .arm(target.key);
                  }
                },
              ),
          ],
        ),
      ],
      if (armed == null)
        Text(
          l10n.labNothingArmed,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LabText.detail.copyWith(color: context.mutedInk),
        )
      else
        _ArtifactChip(configuration: armed, locked: locked),
      // Settings take a profile to validate against: nothing armed, nothing
      // to edit — a draft with no defaults could commit a value no model
      // takes and leave Run silently refused.
      _ContractChip(
        onOpenSettings: locked || armed == null ? null : onOpenSettings,
      ),
    ];
    // A Wrap, not a Row: every group truncates to the window's width on its
    // own and the Rig grows a line rather than overflowing when the window
    // is narrow or the copy is long.
    return Container(
      key: const Key('lab-rig'),
      constraints: const BoxConstraints(minHeight: LabSize.rig),
      padding: const EdgeInsets.symmetric(
        horizontal: LabSpace.gutter,
        vertical: LabSpace.s5,
      ),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(bottom: BorderSide(color: context.divider)),
      ),
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: LabSpace.s3,
        runSpacing: LabSpace.s2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: groups,
      ),
    );
  }
}

class _ChooserItem {
  const _ChooserItem({
    required this.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final Key key;
  final String label;
  final bool selected;
  final VoidCallback onPressed;
}

/// A pull-down chooser: a focusable trigger over a Cupertino menu, so the
/// keyboard reaches both the trigger and the rows.
class _Chooser extends StatelessWidget {
  const _Chooser({
    required this.label,
    required this.semanticLabel,
    required this.items,
    required this.placeholder,
    super.key,
  });

  final String label;
  final String semanticLabel;
  final List<_ChooserItem> items;
  final bool placeholder;

  @override
  Widget build(BuildContext context) => CupertinoMenuAnchor(
    menuChildren: [
      for (final item in items)
        CupertinoMenuItem(
          key: item.key,
          trailing: item.selected
              ? const Icon(CupertinoIcons.checkmark, size: 14)
              : null,
          onPressed: item.onPressed,
          child: Text(item.label),
        ),
    ],
    builder: (context, controller, child) => LabFocusable(
      semanticLabel: semanticLabel,
      semanticValue: placeholder ? null : label,
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
      child: Container(
        height: LabSize.control,
        padding: const EdgeInsetsDirectional.only(
          start: LabSpace.s4,
          end: LabSpace.s3,
        ),
        decoration: BoxDecoration(
          color: context.surfaceRaised,
          borderRadius: BorderRadius.circular(LabRadius.chip),
          border: Border.all(color: context.borderStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: LabText.label.copyWith(
                color: placeholder ? context.mutedInk : context.ink,
              ),
            ),
            const SizedBox(width: LabSpace.s2),
            Icon(
              CupertinoIcons.chevron_up_chevron_down,
              size: 13,
              color: context.mutedInk,
            ),
          ],
        ),
      ),
    ),
  );
}

/// The artifact as the model store reports it, with the transfer actions the
/// existing model manager offers — explicit every time, never on arming.
class _ArtifactChip extends ConsumerWidget {
  const _ArtifactChip({required this.configuration, required this.locked});

  final LabConfiguration configuration;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final entry = configuration.entry;
    final models = ref.watch(modelControllerProvider).value;
    final status =
        models?.statusOf(configuration.key) ?? const ArtifactStatus();
    final simulated = models?.simulated ?? false;
    final controller = ref.read(modelControllerProvider.notifier);
    // The shared projection every transfer surface renders from (#131): the
    // phase's own counter, and an affordance that already knows the single
    // transfer slot, the device refusal and the repository's answer — so a
    // Download here is never a dead tap.
    final transfer = artifactTransfer(
      entry: entry,
      status: status,
      localizations: l10n,
      simulated: simulated,
      deviceRefusal: ref.watch(deviceRefusalProvider),
      downloadable: ref
          .watch(downloadableModelKeysProvider)
          .contains(entry.key),
      transferringKey: models?.artifacts.entries
          .where(
            (e) =>
                e.value.phase == ArtifactPhase.downloading ||
                e.value.phase == ArtifactPhase.verifying,
          )
          .map((e) => e.key)
          .firstOrNull,
    );
    final affordance = transfer.affordance;
    final verified = affordance == null;
    final inFlight = affordance is TransferInFlight;
    final blocked = affordance is TransferOffer && !affordance.enabled;
    final caution = !verified && !inFlight;
    final meta = inFlight
        ? l10n.percentValue(transfer.percent)
        : blocked && affordance.note != null
        ? affordance.note!
        : l10n.labArtifactMeta(
            LabFormat.bytes(entry.totalBytes),
            entry.files.length,
          );
    return Row(
      key: const Key('lab-artifact-chip'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: LabChip(
            lead: transfer.chip,
            text: meta,
            dotColor: verified ? context.accent : null,
            icon: caution ? CupertinoIcons.exclamationmark_triangle_fill : null,
            fill: caution
                ? labResolve(GolemTheme.cautionSurface, context)
                : null,
            border: caution
                ? labResolve(GolemTheme.cautionBorder, context)
                : null,
            ellipsize: true,
          ),
        ),
        if (!locked) ...[
          const SizedBox(width: LabSpace.s2),
          switch (affordance) {
            null => LabButton(
              key: const Key('lab-artifact-delete'),
              label: l10n.delete,
              style: LabButtonStyle.quiet,
              destructive: true,
              height: LabSize.tapMinimum,
              onPressed: () => controller.delete(entry.key),
            ),
            TransferInFlight(:final pausable) => LabButton(
              key: const Key('lab-artifact-pause'),
              label: l10n.pause,
              height: LabSize.tapMinimum,
              onPressed: pausable ? () => controller.pause(entry.key) : null,
            ),
            TransferOffer(:final action, :final enabled) => LabButton(
              key: Key(switch (action) {
                TransferAction.start => 'lab-artifact-download',
                TransferAction.resume => 'lab-artifact-resume',
                TransferAction.retry => 'lab-artifact-retry',
              }),
              label: switch (action) {
                TransferAction.start => l10n.download,
                TransferAction.resume => l10n.resume,
                TransferAction.retry => l10n.retry,
              },
              style: LabButtonStyle.filled,
              height: LabSize.tapMinimum,
              onPressed: !enabled
                  ? null
                  : () async {
                      final approved =
                          action != TransferAction.start ||
                          await confirmModelDownload(
                            context: context,
                            entry: entry,
                            simulated: simulated,
                          );
                      if (approved) await controller.download(entry.key);
                    },
            ),
          },
        ],
      ],
    );
  }
}

/// The contract a run will carry — the broker's effective merge, computed
/// the same way the run computes it, so what is shown is what is sent.
class _ContractChip extends ConsumerWidget {
  const _ContractChip({required this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final (reasoning, lastBatch) = ref.watch(
      labBenchControllerProvider.select(
        (s) => (
          s.settings.reasoningEnabled,
          // The batch a run measured: the engine's, reported on completion,
          // so the chip says what the last run on this rig actually used.
          s.session.active?.runs.reversed
              .map((run) => run.metrics?.promptBatchSize)
              .nonNulls
              .firstOrNull,
        ),
      ),
    );
    final sampling = ref.watch(labContractProvider);
    final parts = <String>[];
    if (sampling != null) {
      parts.add(l10n.labContractContext(sampling.contextLength ?? 0));
      parts.add(l10n.labContractMax(sampling.maxTokens));
      parts.add(l10n.labContractTemperature(sampling.temperature.toString()));
      parts.add(l10n.labContractTopP(sampling.topP.toString()));
      if (sampling.topK case final k?) parts.add(l10n.labContractTopK(k));
      parts.add(reasoning ? l10n.labReasoningOn : l10n.labReasoningOff);
      parts.add(
        sampling.seed == null
            ? l10n.labContractSeedFree
            : l10n.labContractSeed(sampling.seed!),
      );
      parts.add(
        l10n.labContractBatch(
          lastBatch == null ? l10n.labNotReported : lastBatch.toString(),
        ),
      );
    }
    final text = parts.isEmpty ? l10n.labContractNone : parts.join(' · ');
    return LabFocusable(
      key: const Key('lab-settings-button'),
      semanticLabel: l10n.labRunSettings,
      semanticValue: text,
      onPressed: onOpenSettings,
      borderRadius: LabRadius.chip,
      child: LabChip(
        key: const Key('lab-contract-chip'),
        icon: onOpenSettings == null
            ? CupertinoIcons.lock_fill
            : CupertinoIcons.slider_horizontal_3,
        text: text,
        textColor: sampling == null ? context.mutedInk : context.ink,
        ellipsize: true,
      ),
    );
  }
}
