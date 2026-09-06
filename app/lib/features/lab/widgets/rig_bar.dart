import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/model_catalog.dart';
import '../../../core/domain/models.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/presentation_messages.dart';
import '../../models/application/model_providers.dart';
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
    final bench = ref.watch(labBenchControllerProvider);
    final armed = bench.armed;
    final locked = bench.locked;
    final families = labModelFamilies(ref.watch(labConfigurationListProvider));
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
      _ContractChip(onOpenSettings: locked ? null : onOpenSettings),
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
    final status = ref
        .watch(modelControllerProvider)
        .value
        ?.statusOf(configuration.key);
    final phase = status?.phase ?? ArtifactPhase.notDownloaded;
    final entry = configuration.entry;
    final simulated =
        ref.watch(modelControllerProvider).value?.simulated ?? false;
    final controller = ref.read(modelControllerProvider.notifier);
    final verified = phase == ArtifactPhase.installed;
    final inFlight =
        phase == ArtifactPhase.downloading || phase == ArtifactPhase.verifying;
    final meta = inFlight
        ? l10n.percentValue(
            entry.totalBytes == 0
                ? 0
                : ((status!.progressBytes / entry.totalBytes) * 100).round(),
          )
        : l10n.labArtifactMeta(
            LabFormat.bytes(entry.totalBytes),
            entry.files.length,
          );
    final caution = !verified && !inFlight;
    return Row(
      key: const Key('lab-artifact-chip'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: LabChip(
            lead: labArtifactPhaseLabel(l10n, phase),
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
          switch (phase) {
            ArtifactPhase.notDownloaded => LabButton(
              key: const Key('lab-artifact-download'),
              label: l10n.download,
              style: LabButtonStyle.filled,
              height: LabSize.tapMinimum,
              onPressed: () async {
                final approved = await confirmModelDownload(
                  context: context,
                  entry: entry,
                  simulated: simulated,
                );
                if (approved) await controller.download(entry.key);
              },
            ),
            ArtifactPhase.downloading => LabButton(
              key: const Key('lab-artifact-pause'),
              label: l10n.pause,
              height: LabSize.tapMinimum,
              onPressed: () => controller.pause(entry.key),
            ),
            ArtifactPhase.paused => LabButton(
              key: const Key('lab-artifact-resume'),
              label: l10n.resume,
              style: LabButtonStyle.filled,
              height: LabSize.tapMinimum,
              onPressed: () => controller.download(entry.key),
            ),
            ArtifactPhase.failed => LabButton(
              key: const Key('lab-artifact-retry'),
              label: l10n.retry,
              style: LabButtonStyle.filled,
              height: LabSize.tapMinimum,
              onPressed: () => controller.download(entry.key),
            ),
            ArtifactPhase.installed => LabButton(
              key: const Key('lab-artifact-delete'),
              label: l10n.delete,
              style: LabButtonStyle.quiet,
              destructive: true,
              height: LabSize.tapMinimum,
              onPressed: () => controller.delete(entry.key),
            ),
            ArtifactPhase.verifying => const SizedBox.shrink(),
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
    final bench = ref.watch(labBenchControllerProvider);
    final contract = ref.watch(labContractProvider);
    final parts = <String>[];
    if (contract != null) {
      final sampling = contract.sampling;
      parts.add(l10n.labContractContext(sampling.contextLength ?? 0));
      parts.add(l10n.labContractMax(sampling.maxTokens));
      parts.add(l10n.labContractTemperature(sampling.temperature.toString()));
      parts.add(l10n.labContractTopP(sampling.topP.toString()));
      if (sampling.topK case final k?) parts.add(l10n.labContractTopK(k));
      parts.add(
        bench.settings.reasoningEnabled
            ? l10n.labReasoningOn
            : l10n.labReasoningOff,
      );
      parts.add(
        sampling.seed == null
            ? l10n.labContractSeedFree
            : l10n.labContractSeed(sampling.seed!),
      );
      parts.add(l10n.labContractBatch(l10n.labNotReported));
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
        textColor: contract == null ? context.mutedInk : context.ink,
        ellipsize: true,
      ),
    );
  }
}
