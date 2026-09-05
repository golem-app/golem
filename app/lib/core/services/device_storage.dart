import 'package:flutter/services.dart';

/// Free space on the volume containing a path, for download preflight.
/// Returns null when the platform cannot determine it — "unknown" must skip
/// the preflight rather than masquerade as zero free bytes.
abstract interface class DiskSpaceProbe {
  Future<int?> freeBytes(String path);
}

/// Marks a directory as excluded from platform backups. Nothing Golem stores
/// leaves the phone (ADR 0016): launch composition marks both storage roots.
/// Android handles this statically in the manifest, so its implementation is
/// a no-op.
abstract interface class BackupExclusion {
  Future<void> exclude(String path);
}

/// The device's physical memory, for the default-model policy. Returns null
/// when the platform cannot report it — "unknown" must select the lighter
/// model, never masquerade as plenty.
abstract interface class DeviceMemoryProbe {
  Future<int?> physicalMemoryBytes();
}

/// Memory the process can still allocate right now, for the model-load
/// preflight: `os_proc_available_memory` (the jetsam headroom) on iOS,
/// `ActivityManager.MemoryInfo.availMem` on Android. Returns null when the
/// platform cannot report it — "unknown" must let the load proceed and
/// keep the engine's own failure the loud path, never invent a refusal.
abstract interface class AvailableMemoryProbe {
  Future<int?> availableMemoryBytes();
}

/// Total capacity of the volume containing a path, for the drawer's
/// storage meter. Returns null when the platform cannot report it — the
/// meter hides rather than invent a denominator.
abstract interface class DiskCapacityProbe {
  Future<int?> totalBytes(String path);
}

/// This process's resident footprint right now, for the bench's live memory
/// reading (#58): the same `phys_footprint` the engines' peak figure samples.
/// Null where the platform does not answer — the bench shows "not reported".
abstract interface class ProcessFootprintProbe {
  Future<int?> physicalFootprintBytes();
}

/// What the machine is, for the provenance every bench measurement carries
/// (#58). Every field is nullable: an unknown reading stays unknown.
final class DeviceProvenance {
  const DeviceProvenance({
    this.model,
    this.chip,
    this.memoryBytes,
    this.osVersion,
    this.thermalState,
  });

  /// The hardware model identifier (`MacBookPro18,3`).
  final String? model;

  /// The processor's marketing name (`Apple M1 Pro`).
  final String? chip;
  final int? memoryBytes;
  final String? osVersion;

  /// `nominal`, `fair`, `serious` or `critical`, as the OS reports it.
  final String? thermalState;

  factory DeviceProvenance.fromChannel(Map<Object?, Object?> values) =>
      DeviceProvenance(
        model: values['model'] as String?,
        chip: values['chip'] as String?,
        memoryBytes: values['memoryBytes'] as int?,
        osVersion: values['osVersion'] as String?,
        thermalState: values['thermalState'] as String?,
      );
}

abstract interface class DeviceProvenanceProbe {
  Future<DeviceProvenance?> deviceProvenance();
}

final class DeviceStorageChannel
    implements
        DiskSpaceProbe,
        BackupExclusion,
        DeviceMemoryProbe,
        AvailableMemoryProbe,
        DiskCapacityProbe,
        ProcessFootprintProbe,
        DeviceProvenanceProbe {
  const DeviceStorageChannel();

  static const _channel = MethodChannel('app.golem/storage');

  @override
  Future<int?> freeBytes(String path) =>
      _channel.invokeMethod<int>('freeBytes', {'path': path});

  @override
  Future<void> exclude(String path) =>
      _channel.invokeMethod<void>('excludeFromBackup', {'path': path});

  @override
  Future<int?> physicalMemoryBytes() =>
      _channel.invokeMethod<int>('physicalMemoryBytes');

  @override
  Future<int?> availableMemoryBytes() =>
      _channel.invokeMethod<int>('availableMemoryBytes');

  @override
  Future<int?> totalBytes(String path) =>
      _channel.invokeMethod<int>('totalBytes', {'path': path});

  @override
  Future<int?> physicalFootprintBytes() =>
      _channel.invokeMethod<int>('physicalFootprintBytes');

  @override
  Future<DeviceProvenance?> deviceProvenance() async {
    final values = await _channel.invokeMethod<Map<Object?, Object?>>(
      'deviceProvenance',
    );
    return values == null ? null : DeviceProvenance.fromChannel(values);
  }

  /// Whether this is a simulator or emulator rather than a phone, for the
  /// admission policy. Null when the platform cannot answer — "unknown" must
  /// let the device try, never refuse it.
  Future<bool?> isVirtualDevice() =>
      _channel.invokeMethod<bool>('isVirtualDevice');
}
