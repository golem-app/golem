import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../broker/runtime.dart' show llamaCppRelease, mlxSwiftVersion;
import '../../../core/app_identity.dart';
import '../../../core/app_version.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../core/widgets/section_header.dart';
import '../../../l10n/bidi.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/presentation_messages.dart';
import '../application/lab_bench_controller.dart';
import '../application/lab_providers.dart';
import '../domain/lab_configuration.dart';
import '../lab_copy.dart';
import '../lab_theme.dart';
import 'lab_controls.dart';

/// The lab's sidebar: identity, the one surface this ticket ships, the
/// model library, and the engine pins every measurement is made under.
class LabSidebar extends ConsumerWidget {
  const LabSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final (armed, locked, runCount) = ref.watch(
      labBenchControllerProvider.select(
        (s) => (s.armed, s.locked, s.session.runCount),
      ),
    );
    final families = ref.watch(labModelFamiliesProvider);
    final resident = ref.watch(residentModelKeyProvider);
    final residentConfiguration = families
        .expand((f) => f.configurations)
        .where((c) => c.key == resident)
        .firstOrNull;
    final device = ref.watch(labDeviceProvenanceProvider).value;
    return Container(
      key: const Key('lab-sidebar'),
      width: LabSize.sidebar,
      padding: const EdgeInsets.fromLTRB(
        LabSpace.s4,
        LabSpace.s6,
        LabSpace.s4,
        LabSpace.s4,
      ),
      decoration: BoxDecoration(
        color: labResolve(LabColors.sidebar, context),
        border: Border(right: BorderSide(color: context.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LabSpace.s2,
              0,
              LabSpace.s2,
              LabSpace.s7,
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    AppIdentity.lab.iconAsset,
                    width: 22,
                    height: 22,
                    // The tile ships in lab bundles only (flavors: [lab]);
                    // the host suite runs unflavored and draws the swatch.
                    errorBuilder: (_, _, _) => Container(
                      width: 22,
                      height: 22,
                      color: GolemTheme.userBubble,
                    ),
                  ),
                ),
                const SizedBox(width: LabSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.labAppName,
                        style: LabText.bodyStrong.copyWith(color: context.ink),
                      ),
                      Text(
                        l10n.labVersion(ltrIsolate(appVersion)),
                        style: LabText.detail.copyWith(color: context.mutedInk),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            selected: true,
            child: Container(
              key: const Key('lab-nav-bench'),
              height: LabSize.chip,
              padding: const EdgeInsets.symmetric(horizontal: LabSpace.s3),
              decoration: BoxDecoration(
                color: context.accentSoft,
                borderRadius: BorderRadius.circular(LabRadius.chip),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.lab_flask,
                    size: 14,
                    color: context.accentIcon,
                  ),
                  const SizedBox(width: LabSpace.s3),
                  Expanded(
                    child: Text(
                      l10n.labNavBench,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LabText.label.copyWith(color: context.accentIcon),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LabSpace.s3,
              LabSpace.s8,
              LabSpace.s3,
              LabSpace.s2,
            ),
            child: SectionHeader(l10n.labLibrary, style: LabText.overline),
          ),
          for (final family in families)
            _FamilyRow(
              family: family,
              armed: armed,
              // Resident on the engine a click here would arm — the family's
              // other engine being resident is a cold load, not a warm one.
              resident:
                  residentConfiguration != null &&
                  family
                          .on(
                            armed?.engine ?? family.configurations.first.engine,
                          )
                          ?.key ==
                      residentConfiguration.key,
              locked: locked,
            ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.only(top: LabSpace.s4),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.divider)),
            ),
            child: Column(
              children: [
                _PinRow(label: 'llama.cpp', value: llamaCppRelease),
                _PinRow(label: 'MLX', value: mlxSwiftVersion),
                _PinRow(
                  label: l10n.labResidentLabel,
                  value: residentConfiguration == null
                      ? (resident ?? l10n.labResidentNone)
                      : '${residentConfiguration.displayName} · '
                            '${engineLabel(residentConfiguration.engine)}',
                ),
                _PinRow(
                  label: l10n.labRunsThisSession,
                  value: runCount.toString(),
                ),
                // Provenance beside the pins: a Mac's numbers are not a
                // phone's, and every measurement is made under both.
                _PinRow(
                  key: const Key('lab-device'),
                  label: l10n.labMachineLabel,
                  value: device?.chip ?? device?.model ?? l10n.labDeviceUnknown,
                ),
                if (device?.memoryBytes case final bytes?)
                  _PinRow(
                    label: l10n.labMemoryLabel,
                    value: l10n.labDeviceMemory(
                      LabFormat.memoryGigabytes(bytes),
                    ),
                  ),
                if (device?.thermalState case final thermal?
                    when thermal != 'nominal')
                  _PinRow(label: l10n.thermal, value: thermal),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyRow extends ConsumerWidget {
  const _FamilyRow({
    required this.family,
    required this.armed,
    required this.resident,
    required this.locked,
  });

  final LabModelFamily family;
  final LabConfiguration? armed;
  final bool resident;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selected = armed?.displayName == family.displayName;
    final first = family.configurations.first;
    // The variant a click here arms — and so the size it shows.
    final target = family.on(armed?.engine ?? first.engine) ?? first;
    return LabFocusable(
      key: Key('lab-library-${family.id}'),
      semanticLabel: family.displayName,
      semanticValue: resident ? l10n.labResidentLabel : null,
      selected: selected,
      onPressed: locked
          ? null
          : () => ref.read(labBenchControllerProvider.notifier).arm(target.key),
      borderRadius: LabRadius.chip,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: LabSpace.s3),
        decoration: BoxDecoration(
          color: selected ? context.accentSoft : null,
          borderRadius: BorderRadius.circular(LabRadius.chip),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: resident ? context.accent : context.mutedInk,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: LabSpace.s3),
            Expanded(
              child: Text(
                family.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LabText.row.copyWith(
                  color: selected ? context.accentIcon : context.ink,
                ),
              ),
            ),
            Text(
              LabFormat.bytes(target.entry.totalBytes),
              style: LabText.detail.copyWith(color: context.mutedInk),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinRow extends StatelessWidget {
  const _PinRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: LabSpace.s3,
      vertical: LabSpace.s1 / 2,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LabText.detail.copyWith(color: context.mutedInk),
          ),
        ),
        const SizedBox(width: LabSpace.s2),
        // The value keeps its width up to a cap; the label takes the rest.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 104),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: LabText.detail.copyWith(color: context.mutedInk),
          ),
        ),
      ],
    ),
  );
}
