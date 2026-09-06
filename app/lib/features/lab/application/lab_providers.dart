import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';
import '../../../core/services/device_storage.dart';
import '../domain/lab_configuration.dart';

part 'lab_providers.g.dart';

/// The configurations the bench offers, from the pinned catalog.
@Riverpod(keepAlive: true, retry: noRetry)
List<LabConfiguration> labConfigurationList(Ref ref) =>
    labConfigurations(ref.watch(modelCatalogEntriesProvider));

/// The readings the bench takes off the machine, behind one seam so tests
/// substitute both without a platform channel.
final class LabProbes {
  const LabProbes({required this.footprint, required this.provenance});

  final ProcessFootprintProbe footprint;
  final DeviceProvenanceProbe provenance;
}

@Riverpod(keepAlive: true, retry: noRetry)
LabProbes labProbes(Ref ref) => const LabProbes(
  footprint: DeviceStorageChannel(),
  provenance: DeviceStorageChannel(),
);

/// What this machine is, read once per session. A reading that fails or
/// stalls stays unknown — the Rig says so — rather than delaying a run.
@Riverpod(keepAlive: true, retry: noRetry)
Future<DeviceProvenance?> labDeviceProvenance(Ref ref) async {
  try {
    return await ref
        .watch(labProbesProvider)
        .provenance
        .deviceProvenance()
        .timeout(const Duration(seconds: 1));
  } on Object {
    return null;
  }
}
