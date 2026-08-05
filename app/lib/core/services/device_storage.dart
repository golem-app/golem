import 'package:flutter/services.dart';

/// Free space on the volume containing a path, for download preflight.
abstract interface class DiskSpaceProbe {
  Future<int> freeBytes(String path);
}

/// Marks a directory as excluded from platform backups. Downloaded models
/// are re-fetchable pinned content and must stay out of iCloud backups;
/// Android handles this statically via dataExtractionRules, so its
/// implementation is a no-op.
abstract interface class BackupExclusion {
  Future<void> exclude(String path);
}

final class DeviceStorageChannel implements DiskSpaceProbe, BackupExclusion {
  const DeviceStorageChannel();

  static const _channel = MethodChannel('app.golem.flutter/storage');

  @override
  Future<int> freeBytes(String path) async =>
      await _channel.invokeMethod<int>('freeBytes', {'path': path}) ?? 0;

  @override
  Future<void> exclude(String path) =>
      _channel.invokeMethod<void>('excludeFromBackup', {'path': path});
}
