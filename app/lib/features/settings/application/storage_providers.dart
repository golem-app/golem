import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/application/storage_breakdown_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';
import '../../../core/repositories/contracts.dart';
import '../../../core/services/cache_probe.dart';
import '../../../core/services/device_storage.dart';
import '../../chat/application/chat_providers.dart';
import '../../models/application/model_providers.dart';

// The breakdown types stay importable beside the provider that produces them.
export '../../../core/application/storage_breakdown_service.dart'
    show StorageBreakdown, StorageBreakdownTotals;

part 'storage_providers.g.dart';

/// Storage accounting for the drawer meter and the Storage screen. Free and
/// total bytes are null whenever the platform cannot report them (or the seams
/// are unwired) — surfaces hide those figures instead of inventing them. The
/// provider owns seam tolerance; the service owns the computation and its
/// required-vs-optional failure policy.
/// KeepAlive, deliberately (#69): the always-mounted drawer meter watches it
/// continuously anyway, and the 3.3.2 scope-swap hazard (see
/// chatStorageSignature) rules autoDispose out. Staleness is owned by
/// invalidation — the storage signature upstream and `ref.invalidate` after
/// a cache clear — never by a `KeepAliveLink` TTL (§4.4, a silent no-op on
/// keepAlive providers). Revisit when the pin crosses 3.4.0.
@Riverpod(keepAlive: true, retry: noRetry)
Future<StorageBreakdown> storageBreakdown(Ref ref) async {
  // Every dependency registers before the first await: a watch first taken
  // mid-computation would race its own invalidation.
  ref.watch(chatStorageSignatureProvider);
  final history = ref.watch(chatHistoryRepositoryProvider);
  AttachmentRepository? attachments;
  try {
    attachments = ref.watch(attachmentRepositoryProvider);
  } catch (_) {}
  CacheProbe? cache;
  try {
    cache = ref.watch(cacheProbeProvider);
  } catch (_) {}
  DiskSpaceProbe? free;
  try {
    free = ref.watch(diskFreeSpaceProbeProvider);
  } catch (_) {}
  DiskCapacityProbe? capacity;
  try {
    capacity = ref.watch(deviceCapacityProbeProvider);
  } catch (_) {}
  String? path;
  try {
    path = ref.watch(documentsPathProvider);
  } catch (_) {}
  final models = await ref.watch(modelControllerProvider.future);
  return StorageBreakdownService(
    history: history,
    attachments: attachments,
    cache: cache,
    free: free,
    capacity: capacity,
    documentsPath: path,
  ).compute(models: models);
}
