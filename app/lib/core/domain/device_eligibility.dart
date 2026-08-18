/// Nominal device admission: whether this device belongs to a tier Golem ships
/// a model for, decided once at launch from facts that do not change while the
/// app runs. Deliberately distinct from the load preflight (#62), which asks
/// whether the memory free *right now* fits the weights — the floor governs
/// what we ship to, the preflight governs the moment of load.
library;

/// Which shipping tier a device falls in. [unsupported] is the admission
/// refusal: no model may be downloaded or loaded, while chats, settings, and
/// every non-model surface keep working.
enum DeviceTier { preferred, light, unsupported }

/// Why a device sits outside every supported tier; null while it is inside one.
enum DeviceIneligibilityReason { belowMemoryFloor, missingInstructionSet }

/// At or above this reported physical memory the preferred model is selected;
/// below it, the lighter one. 7 GiB rather than a literal 8 GB because
/// Android's totalMem reports net of kernel/firmware reservations (a nominal
/// 8 GB phone reads ~7.5 GB): the policy classifies nominal capacity, not
/// reported bytes (docs/decisions/0003-flavor-backend-defaults.md).
const int deviceMemoryThresholdBytes = 7 * 1024 * 1024 * 1024;

/// Apple's floor: the iPhone 12 and its 4 GB. `ProcessInfo.physicalMemory`
/// reports installed DRAM, so a 4 GB device reads exactly 4 GiB and the
/// threshold can be the nominal figure itself.
const int appleMemoryFloorBytes = 4 * 1024 * 1024 * 1024;

/// Android's floor is the same nominal 4 GB, spelled 3 GiB: `totalMem` is net
/// of reservations and nominal 4 GB phones report anywhere from 3.4 to 3.7
/// GiB, while nominal 3 GB phones report around 2.7 GiB. One rule, two
/// numbers, for the same reason [deviceMemoryThresholdBytes] is not 8 GiB.
const int androidMemoryFloorBytes = 3 * 1024 * 1024 * 1024;

/// The floor for the reporting convention this platform uses, which is what
/// the two constants actually differ over — the caller supplies it so the
/// policy itself stays free of `dart:io`.
int deviceMemoryFloorBytes({required bool reportsInstalledMemory}) =>
    reportsInstalledMemory ? appleMemoryFloorBytes : androidMemoryFloorBytes;

/// The stable device facts the policy reads. A null field is genuinely unknown
/// — a probe the platform refused — and must never be read as a low value.
final class DeviceCapabilities {
  const DeviceCapabilities({this.physicalMemoryBytes, this.engineSupported});

  final int? physicalMemoryBytes;

  /// Whether this build's compiled engine can execute on this CPU at all, from
  /// Inferno's device probe. Null under a simulated backend and wherever the
  /// probe could not be reached.
  final bool? engineSupported;

  @override
  bool operator ==(Object other) =>
      other is DeviceCapabilities &&
      other.physicalMemoryBytes == physicalMemoryBytes &&
      other.engineSupported == engineSupported;

  @override
  int get hashCode => Object.hash(physicalMemoryBytes, engineSupported);
}

/// A classified device: the tier, and why it was refused when it was. Carries
/// no copy — the sentence for a refusal is one of thirteen catalogs and belongs
/// to `l10n/presentation_messages.dart` (#130). Value-equal so widgets can
/// select on it.
final class DeviceEligibility {
  const DeviceEligibility({
    required this.tier,
    this.reason,
    this.memoryKnown = true,
  }) : assert(
         (tier == DeviceTier.unsupported) == (reason != null),
         'an unsupported device carries its reason, a supported one has none',
       );

  /// What an unclassified process assumes: supported, nothing refused. The
  /// simulated backend and host tests never reach a real probe, and absence of
  /// evidence must not gate anything.
  const DeviceEligibility.unclassified()
    : this(tier: DeviceTier.light, memoryKnown: false);

  final DeviceTier tier;
  final DeviceIneligibilityReason? reason;

  /// Whether the memory reading behind [tier] actually happened. The light tier
  /// is reached two ways — a small phone, and a probe that answered nothing —
  /// and copy that explains the tier must not describe the second as if it were
  /// the first. Absence of evidence is not a low reading (#79).
  final bool memoryKnown;

  bool get runsModels => tier != DeviceTier.unsupported;

  /// Why a refused device is refused — non-null exactly when it is, which is
  /// what every gate keys on. `classifyDevice` is the only producer and sets
  /// both halves on both refusal branches, so the tier and the reason cannot
  /// disagree in a build where the assert above is compiled out; presentation
  /// words a null reason generically all the same.
  DeviceIneligibilityReason? get refusal => runsModels ? null : reason;

  @override
  bool operator ==(Object other) =>
      other is DeviceEligibility &&
      other.tier == tier &&
      other.reason == reason &&
      other.memoryKnown == memoryKnown;

  @override
  int get hashCode => Object.hash(tier, reason, memoryKnown);
}

/// The whole admission policy, pure. Instruction set decides first: a CPU that
/// cannot execute the compiled kernels is out regardless of how much memory it
/// has. Unknown never refuses — the native load guard and the #62 preflight
/// stay behind this, so absence of evidence costs a wasted download at worst,
/// while a wrong refusal costs a usable device.
DeviceEligibility classifyDevice({
  required DeviceCapabilities capabilities,
  required int memoryFloorBytes,
  int preferredThresholdBytes = deviceMemoryThresholdBytes,
}) {
  if (capabilities.engineSupported == false) {
    return const DeviceEligibility(
      tier: DeviceTier.unsupported,
      reason: DeviceIneligibilityReason.missingInstructionSet,
    );
  }
  final memory = capabilities.physicalMemoryBytes;
  if (memory == null) {
    return const DeviceEligibility(tier: DeviceTier.light, memoryKnown: false);
  }
  if (memory < memoryFloorBytes) {
    return const DeviceEligibility(
      tier: DeviceTier.unsupported,
      reason: DeviceIneligibilityReason.belowMemoryFloor,
    );
  }
  return DeviceEligibility(
    tier: memory >= preferredThresholdBytes
        ? DeviceTier.preferred
        : DeviceTier.light,
  );
}
