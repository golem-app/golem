import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/application/storage_breakdown_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';
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
/// a cache clear — never by a `KeepAliveLink` TTL (handbook v5.0 §4.4, a
/// silent no-op on keepAlive providers).
@Riverpod(keepAlive: true, retry: noRetry)
Future<StorageBreakdown> storageBreakdown(Ref ref) async {
  // Every dependency registers before the first await: a watch first taken
  // mid-computation would race its own invalidation.
  ref.watch(chatStorageSignatureProvider);
  final history = ref.watch(chatHistoryRepositoryProvider);
  // Read straight, no tolerance for an absent seam (#127): launchOverrides
  // wires all five, so a missing one is a wiring mistake that should say so
  // rather than render as a plausible partial breakdown. The service's fields
  // stay nullable — a probe that *fails* still degrades to null.
  final attachments = ref.watch(attachmentRepositoryProvider);
  final cache = ref.watch(cacheProbeProvider);
  final free = ref.watch(diskFreeSpaceProbeProvider);
  final capacity = ref.watch(deviceCapacityProbeProvider);
  final path = ref.watch(documentsPathProvider);
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
