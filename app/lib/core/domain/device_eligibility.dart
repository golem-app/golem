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

/// The floor for the platform this process runs on; the caller supplies the
/// platform so the policy itself stays free of `dart:io`.
int deviceMemoryFloorBytes({required bool apple}) =>
    apple ? appleMemoryFloorBytes : androidMemoryFloorBytes;

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

/// A classified device: the tier, why it was refused when it was, and the copy
/// that refusal presents. Value-equal so widgets can select on it.
final class DeviceEligibility {
  const DeviceEligibility({required this.tier, this.reason, this.message})
    : assert(
        (tier == DeviceTier.unsupported) == (reason != null),
        'an unsupported device carries its reason, a supported one has none',
      );

  /// What an unclassified process assumes: supported, nothing refused. The
  /// simulated backend and host tests never reach a real probe, and absence of
  /// evidence must not gate anything.
  const DeviceEligibility.unclassified() : this(tier: DeviceTier.light);

  final DeviceTier tier;
  final DeviceIneligibilityReason? reason;

  /// User-presentable copy for the refusal; null while the device is supported.
  final String? message;

  bool get runsModels => tier != DeviceTier.unsupported;

  @override
  bool operator ==(Object other) =>
      other is DeviceEligibility &&
      other.tier == tier &&
      other.reason == reason &&
      other.message == message;

  @override
  int get hashCode => Object.hash(tier, reason, message);
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
      // The same sentence the native load guard uses, so a device that somehow
      // reaches the engine anyway is told the same thing twice, not two things.
      message:
          'This device’s processor is missing an instruction set the local '
          'engine needs, so it cannot run models here.',
    );
  }
  final memory = capabilities.physicalMemoryBytes;
  if (memory == null) return const DeviceEligibility(tier: DeviceTier.light);
  if (memory < memoryFloorBytes) {
    return const DeviceEligibility(
      tier: DeviceTier.unsupported,
      reason: DeviceIneligibilityReason.belowMemoryFloor,
      message:
          'This device has less memory than the smallest model Golem ships '
          'needs to run, so downloads are turned off here. Your chats and '
          'settings are unaffected.',
    );
  }
  return DeviceEligibility(
    tier: memory >= preferredThresholdBytes
        ? DeviceTier.preferred
        : DeviceTier.light,
  );
}
