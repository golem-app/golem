import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../application/session_bridges.dart';
import '../domain/device_eligibility.dart';
import '../domain/inference_backend.dart';
import '../domain/model_catalog.dart';
import '../repositories/contracts.dart';
import '../services/cache_probe.dart';
import '../services/custom_repository_resolver.dart';
import '../services/device_storage.dart';
import 'retry.dart';

part 'app_providers.g.dart';

// Ownership (#88): this file holds only what is genuinely shared across
// features — the launch seams (mirroring LaunchDependencies, wired by
// launchOverrides), the boot-constant derivations, and the session bridges.
// Feature providers live in features/<name>/application/.
//
// Lifetime policy (#69): the repository/probe seams below are keepAlive
// because they are composition-injected process-lifetime dependencies —
// overridden once at launch, never recomputed; disposing one could only
// re-throw its seam. Providers with a narrower owner say so individually.

@Riverpod(keepAlive: true, retry: noRetry)
ChatHistoryRepository chatHistoryRepository(Ref ref) =>
    throw UnimplementedError(
      'Override chatHistoryRepositoryProvider at startup',
    );

@Riverpod(keepAlive: true, retry: noRetry)
InferenceRepository inferenceRepository(Ref ref) =>
    throw UnimplementedError('Override inferenceRepositoryProvider at startup');

@Riverpod(keepAlive: true, retry: noRetry)
ModelManagementRepository modelManagementRepository(Ref ref) =>
    throw UnimplementedError(
      'Override modelManagementRepositoryProvider at startup',
    );

@Riverpod(keepAlive: true, retry: noRetry)
BenchmarkRepository benchmarkRepository(Ref ref) =>
    throw UnimplementedError('Override benchmarkRepositoryProvider at startup');

@Riverpod(keepAlive: true, retry: noRetry)
List<ModelCatalogEntry> modelCatalogEntries(Ref ref) =>
    throw UnimplementedError('Override modelCatalogEntriesProvider at startup');

@Riverpod(keepAlive: true, retry: noRetry)
CustomRepositoryResolver customRepositoryResolver(Ref ref) =>
    throw UnimplementedError(
      'Override customRepositoryResolverProvider at startup',
    );

@Riverpod(keepAlive: true, retry: noRetry)
SettingsRepository settingsRepository(Ref ref) =>
    throw UnimplementedError('Override settingsRepositoryProvider at startup');

@Riverpod(keepAlive: true, retry: noRetry)
PreferencesRepository preferencesRepository(Ref ref) =>
    throw UnimplementedError(
      'Override preferencesRepositoryProvider at startup',
    );

@Riverpod(keepAlive: true, retry: noRetry)
AttachmentRepository attachmentRepository(Ref ref) => throw UnimplementedError(
  'Override attachmentRepositoryProvider at startup',
);

@Riverpod(keepAlive: true, retry: noRetry)
CacheProbe cacheProbe(Ref ref) =>
    throw UnimplementedError('Override cacheProbeProvider at startup');

@Riverpod(keepAlive: true, retry: noRetry)
DiskSpaceProbe diskFreeSpaceProbe(Ref ref) =>
    throw UnimplementedError('Override diskFreeSpaceProbeProvider at startup');

/// The resolved inference backend for this process. A fake default rather than
/// a throwing seam — a documented exception to the repository-provider
/// discipline: dozens of widgets read it for honest "simulated" labeling, and
/// host tests (the dev flavor) must see the fake without every container
/// overriding it. main() always overrides it with the resolved config.
/// KeepAlive: process-constant boot configuration.
@Riverpod(keepAlive: true, retry: noRetry)
InferenceBackendConfig inferenceBackend(Ref ref) =>
    const InferenceBackendConfig.fake();

/// What this device is allowed to run, classified once at launch (#27). A
/// permitting default rather than a throwing seam, for the same reason
/// [inferenceBackend] has one: surfaces across chat and Settings read it, and a
/// container that never classified a device must not refuse anything. main()
/// always overrides it with the real verdict.
/// KeepAlive: process-constant boot configuration.
@Riverpod(keepAlive: true, retry: noRetry)
DeviceEligibility deviceEligibility(Ref ref) =>
    const DeviceEligibility.unclassified();

/// The refusal an unsupported device must present before any download or load,
/// or null when this device may run models. Derived once and watched by every
/// surface that gates on it, so the rule — including that a simulated backend
/// is never gated, since it loads no weights and gating it would only make QA
/// depend on hardware — exists in exactly one place.
/// KeepAlive: derived from two process-constant boot values.
@Riverpod(keepAlive: true, retry: noRetry)
String? deviceRefusal(Ref ref) =>
    ref.watch(inferenceBackendProvider).simulatedInference
    ? null
    : ref.watch(deviceEligibilityProvider).refusal;

/// The catalog key of the model resident in the engine, straight from the
/// residency owner (#42). Null while the engine is empty — label helpers fall
/// back to the configured artifact, so a lazy first load does not blank the
/// chrome. Always null under a simulated backend, without touching the
/// repository seam: label-only containers must not need one.
/// KeepAlive: holds the live ValueListenable subscription onto #42's
/// residency owner; autoDispose would churn that listener per route.
@Riverpod(keepAlive: true, retry: noRetry)
InferenceResidency inferenceResidency(Ref ref) {
  if (ref.watch(inferenceBackendProvider).simulatedInference) {
    return const InferenceResidency.unloaded();
  }
  final listenable = ref.watch(inferenceRepositoryProvider).residency;
  void onChange() => ref.invalidateSelf();
  listenable.addListener(onChange);
  ref.onDispose(() => listenable.removeListener(onChange));
  return listenable.value;
}

@Riverpod(keepAlive: true, retry: noRetry)
String? residentModelKey(Ref ref) =>
    ref.watch(inferenceResidencyProvider).catalogKey;

/// The chat session's capabilities offered across feature boundaries (#88):
/// ChatController binds itself in during `build()`, and the model feature
/// reads session facts here instead of the chat provider.
/// KeepAlive: the binding must outlive route transitions, like its owner.
@Riverpod(keepAlive: true, retry: noRetry)
ChatSessionBridge chatSessionBridge(Ref ref) => ChatSessionBridge();

/// The model feature's counterpart to [chatSessionBridge] (#88): chat and
/// preferences command the model controller through this seam.
/// KeepAlive: the binding must outlive route transitions, like its owner.
@Riverpod(keepAlive: true, retry: noRetry)
ModelSessionBridge modelSessionBridge(Ref ref) => ModelSessionBridge();

@Riverpod(keepAlive: true, retry: noRetry)
DiskCapacityProbe deviceCapacityProbe(Ref ref) =>
    throw UnimplementedError('Override deviceCapacityProbeProvider at startup');

@Riverpod(keepAlive: true, retry: noRetry)
String documentsPath(Ref ref) =>
    throw UnimplementedError('Override documentsPathProvider at startup');
