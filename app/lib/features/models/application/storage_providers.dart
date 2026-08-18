import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/application/storage_breakdown_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';
import 'model_providers.dart';

// The breakdown types stay importable beside the provider that produces them.
export '../../../core/application/storage_breakdown_service.dart'
    show StorageBreakdown, StorageBreakdownTotals;

part 'storage_providers.g.dart';

// It counts chats but does not watch chat: it lives one layer below chat in
// the feature direction (#129), so ChatController invalidates it once a write
// has reached disk. Every other input is a core seam or this feature's own
// controller. Staleness is owned entirely by invalidation — that signal and
// `ref.invalidate` after a cache clear — never by a KeepAliveLink TTL
// (handbook v5.0 §4.4, a silent no-op on keepAlive providers).
//
// KeepAlive, deliberately (#69): the always-mounted drawer meter watches it
// continuously anyway, and autoDispose is ruled out besides — on the pinned
// flutter_riverpod (3.3.2) a widget-watched derivation over an async
// controller trips Flutter's element-update invariant when a provider scope is
// swapped mid-test, the class of bug fixed upstream in 3.4.0 ("markNeedsBuild
// ... inside Widget lifecycle"). The pin cannot move on this SDK —
// flutter_test's test_api caps analyzer below the ^13 the newer generator
// needs, and the family is exact-pinned end to end (docs/notes/dependencies.md).
// Revisit on the SDK bump (#38).
//
// All of it kept out of the doc comment, as in chat_providers.dart:
// riverpod_generator copies those into three places in the .g.dart.
/// Storage accounting for the drawer meter and the Storage screen. Free and
/// total bytes are null whenever the platform cannot report them (or the seams
/// are unwired) — surfaces hide those figures instead of inventing them. The
/// provider owns seam tolerance; the service owns the computation and its
/// required-vs-optional failure policy.
@Riverpod(keepAlive: true, retry: noRetry)
Future<StorageBreakdown> storageBreakdown(Ref ref) async {
  // Every dependency registers before the first await: a watch first taken
  // mid-computation would race its own invalidation.
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
