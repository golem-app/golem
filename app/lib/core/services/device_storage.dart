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

final class DeviceStorageChannel
    implements DiskSpaceProbe, BackupExclusion, DeviceMemoryProbe {
  const DeviceStorageChannel();

  static const _channel = MethodChannel('app.golem.flutter/storage');

  @override
  Future<int?> freeBytes(String path) =>
      _channel.invokeMethod<int>('freeBytes', {'path': path});

  @override
  Future<void> exclude(String path) =>
      _channel.invokeMethod<void>('excludeFromBackup', {'path': path});

  @override
  Future<int?> physicalMemoryBytes() =>
      _channel.invokeMethod<int>('physicalMemoryBytes');
}
