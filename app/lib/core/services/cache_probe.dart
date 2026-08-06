import 'dart:io';

/// The "inference cache" surfaced in Settings ▸ Storage: transient bytes the
/// app can drop without losing models or chats. Concretely, the app's
/// temporary directory — downloader scratch and engine spill land there.
abstract interface class CacheProbe {
  Future<int> sizeBytes();
  Future<void> clear();
}

/// Sums and clears the contents of one directory. The directory itself is
/// preserved; unreadable entries are skipped rather than failing the whole
/// measurement.
final class DirectoryCacheProbe implements CacheProbe {
  const DirectoryCacheProbe(this.path);
  final String path;

  @override
  Future<int> sizeBytes() async {
    final directory = Directory(path);
    if (!await directory.exists()) return 0;
    var total = 0;
    try {
      await for (final entry in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is File) {
          try {
            total += await entry.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  @override
  Future<void> clear() async {
    final directory = Directory(path);
    if (!await directory.exists()) return;
    await for (final entry in directory.list(followLinks: false)) {
      try {
        await entry.delete(recursive: true);
      } catch (_) {
        // A file the OS still holds open stays; the next clear gets it.
      }
    }
  }
}

/// Deterministic simulation for qa and test builds: a fixed size that
/// clears to zero, so the Storage screen is provable without real spill.
final class FakeCacheProbe implements CacheProbe {
  FakeCacheProbe({int sizeBytes = 104 * 1000 * 1000}) : _size = sizeBytes;
  int _size;

  @override
  Future<int> sizeBytes() async => _size;

  @override
  Future<void> clear() async => _size = 0;
}
