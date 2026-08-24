import '../domain/models.dart';
import '../repositories/contracts.dart';
import '../services/cache_probe.dart';
import '../services/device_storage.dart';

/// Storage accounting for the drawer meter and the Storage screen.
///
/// Lives in `core/application/` — not a feature — because two features
/// consume it (settings storage, chat drawer), and not `core/services/`,
/// which is the platform-adapter home. Stateless: probes are constructor
/// dependencies, so the orchestration is unit-testable without a container.
/// Null is a probe that failed, never an empty bucket (handbook v5.0 §10.5):
/// a surface omits what it cannot read rather than printing a zero it would
/// then act on.
typedef StorageBreakdown = ({
  int modelsBytes,
  int chatsBytes,
  int? attachmentsBytes,
  int? cacheBytes,
  int? freeBytes,
  int? totalBytes,
});

extension StorageBreakdownTotals on StorageBreakdown {
  /// The buckets that were read; an unknown one contributes nothing rather
  /// than a fictitious zero, so the figure is a floor when a probe failed.
  int get usedBytes =>
      modelsBytes + chatsBytes + (attachmentsBytes ?? 0) + (cacheBytes ?? 0);
}

final class StorageBreakdownService {
  const StorageBreakdownService({
    required this.history,
    this.attachments,
    this.cache,
    this.free,
    this.capacity,
    this.documentsPath,
  });

  final ChatHistoryRepository history;

  /// The optional platform probes. A probe that fails degrades to null —
  /// "unknown is not zero" is their documented contract, not swallowed
  /// failure. They stay nullable for direct construction in tests; the provider
  /// that builds this in the app supplies all of them (#127), so an absent seam
  /// there is a wiring mistake rather than a supported partial breakdown.
  final AttachmentRepository? attachments;
  final CacheProbe? cache;
  final DiskSpaceProbe? free;
  final DiskCapacityProbe? capacity;
  final String? documentsPath;

  /// Required inputs propagate: a chat store the process cannot read must
  /// error the whole computation — a swallowed failure here used to render
  /// as a plausible "0 MB".
  Future<StorageBreakdown> compute({required ModelState models}) async {
    final modelsBytes = models.artifacts.values.fold(
      0,
      (sum, status) => sum + status.downloadedBytes,
    );
    final chatsBytes = await history.storedBytes();
    int? attachmentsBytes;
    try {
      attachmentsBytes = await attachments?.storedBytes();
    } catch (_) {
      attachmentsBytes = null;
    }
    int? cacheBytes;
    try {
      cacheBytes = await cache?.sizeBytes();
    } catch (_) {
      cacheBytes = null;
    }
    final path = documentsPath;
    int? freeBytes;
    try {
      freeBytes = path == null ? null : await free?.freeBytes(path);
    } catch (_) {
      freeBytes = null;
    }
    int? totalBytes;
    try {
      totalBytes = path == null ? null : await capacity?.totalBytes(path);
    } catch (_) {
      totalBytes = null;
    }
    return (
      modelsBytes: modelsBytes,
      chatsBytes: chatsBytes,
      attachmentsBytes: attachmentsBytes,
      cacheBytes: cacheBytes,
      freeBytes: freeBytes,
      totalBytes: totalBytes,
    );
  }
}
