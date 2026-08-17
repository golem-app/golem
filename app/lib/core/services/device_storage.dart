import 'package:flutter/services.dart';

/// Free space on the volume containing a path, for download preflight.
/// Returns null when the platform cannot determine it — "unknown" must skip
/// the preflight rather than masquerade as zero free bytes.
abstract interface class DiskSpaceProbe {
  Future<int?> freeBytes(String path);
}

/// Marks a directory as excluded from platform backups. Downloaded models
/// are re-fetchable pinned content and must stay out of iCloud backups;
/// Android handles this statically via dataExtractionRules, so its
/// implementation is a no-op.
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

final class DeviceStorageChannel
    implements
        DiskSpaceProbe,
        BackupExclusion,
        DeviceMemoryProbe,
        AvailableMemoryProbe,
        DiskCapacityProbe {
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
}
