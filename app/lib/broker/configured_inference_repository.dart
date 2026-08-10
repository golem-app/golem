import '../core/app_identity.dart';
import '../core/domain/inference_backend.dart';
import '../core/repositories/contracts.dart';
import '../core/repositories/fake_inference_repository.dart';
import '../core/services/device_storage.dart';
import 'backend_policy.dart';
import 'inferno_inference_repository.dart';
import 'model_catalog.dart';
import 'model_profile.dart';
import 'model_runtime_config.dart';
import 'runtime.dart';

/// Resolves this process's effective backend from the dart-defines, the
/// flavor policy, and (only on the `auto` path) the device-memory probe.
/// Called once in main(); the result is the single source of truth for the
/// inference repository, the active artifact, and the backend signal
/// provider.
Future<InferenceBackendConfig> resolveConfiguredBackend() =>
    resolveBackendPolicy(
      backendDefine: const String.fromEnvironment('GOLEM_INFERENCE_BACKEND'),
      profileDefine: const String.fromEnvironment('GOLEM_MODEL_PROFILE'),
      artifactDefine: const String.fromEnvironment('GOLEM_MODEL_ARTIFACT'),
      modelPathDefine: const String.fromEnvironment('GOLEM_MODEL_PATH'),
      identity: AppIdentity.current,
      // Test-only escape hatch: forces the device-policy branch (both test
      // phones report over 8 GB, so the Qwen branch is unreachable
      // otherwise). 0 sentinel = unset.
      memoryOverrideBytes: const int.fromEnvironment(
        'GOLEM_DEVICE_MEMORY_BYTES',
      ),
      physicalMemoryBytes: const DeviceStorageChannel().physicalMemoryBytes,
    );

/// Builds the inference repository for a resolved backend config.
InferenceRepository createConfiguredInferenceRepository({
  required InferenceBackendConfig config,
  required Duration fakeStreamDelay,
  required String documentsDirectory,
  Future<List<int>?> Function(String attachmentId)? readAttachment,
}) {
  // Only a catalog-derived startup path inherits the catalog's projector and
  // capability proof. An operator-supplied sideload remains text-only until
  // its own artifact/profile pairing has been validated.
  final initialRuntime =
      config.modelPathFromCatalog && config.artifactKey != null
      ? resolveModelRuntimeConfig(config.artifactKey!)
      : null;
  return selectInferenceRepository(
    backend: config.kind.name,
    modelPath: config.modelPath ?? '',
    modelProfile: config.profileKey,
    initialCatalogKey: config.artifactKey,
    initialProjectorPath: initialRuntime?.projectorPath,
    initialSupportsImages: initialRuntime?.supportsImages ?? false,
    // A fixed seed pins sampling for cross-device determinism probes; regular
    // builds leave it unset (0 sentinel -> engine-default seeding).
    samplingSeed: const int.fromEnvironment('GOLEM_SAMPLING_SEED'),
    fakeStreamDelay: fakeStreamDelay,
    documentsDirectory: documentsDirectory,
    createRuntime: InfernoRuntimeAdapter.native,
    readAttachment: readAttachment,
    // Measurement and triage hatches (house pattern: dart-defines, no UI —
    // evidence decides defaults before any knob earns a settings row).
    loadOptions: const BrokerLoadOptions(
      checkTensors: bool.fromEnvironment('GOLEM_CHECK_TENSORS'),
      quantizedKvCache: String.fromEnvironment('GOLEM_KV_CACHE_TYPE') == 'q8_0',
      threadCount: int.fromEnvironment('GOLEM_THREAD_COUNT') == 0
          ? null
          : int.fromEnvironment('GOLEM_THREAD_COUNT'),
      forceCpu: bool.fromEnvironment('INFERNO_FORCE_CPU'),
    ),
  );
}

/// The dart-define values arrive as compile-time constants, so the selection
/// logic takes them as parameters — reachable from tests, and the
/// construction surface the eval harness uses to run combos through the
/// app's own repository (#42).
InferenceRepository selectInferenceRepository({
  required String backend,
  required String modelPath,
  required String modelProfile,
  String? initialCatalogKey,
  String? initialProjectorPath,
  bool initialSupportsImages = false,
  required Duration fakeStreamDelay,
  required String documentsDirectory,
  required BrokerRuntime Function() createRuntime,
  Future<List<int>?> Function(String attachmentId)? readAttachment,
  required int samplingSeed,
  BrokerLoadOptions loadOptions = const BrokerLoadOptions(),
}) {
  if (backend == 'fake') {
    return FakeInferenceRepository(eventDelay: fakeStreamDelay);
  }
  // A misconfigured build must fail at launch, loudly; there is no UI state
  // that could make a typo'd dart-define recoverable at runtime.
  if (modelPath.isEmpty) {
    throw StateError(
      'GOLEM_MODEL_PATH is required for the $backend inference backend.',
    );
  }
  final resolvedModelPath = modelPath.startsWith('documents:')
      ? '$documentsDirectory/${modelPath.substring('documents:'.length)}'
      : modelPath;
  final engine = switch (backend) {
    'llama' => BrokerEngine.llamaCpp,
    'mlx' => BrokerEngine.mlx,
    _ => throw StateError(
      'GOLEM_INFERENCE_BACKEND must be fake, llama, or mlx.',
    ),
  };
  final profile = modelProfiles[modelProfile];
  if (profile == null) {
    throw StateError(
      'GOLEM_MODEL_PROFILE must be one of: ${modelProfiles.keys.join(', ')}.',
    );
  }
  return InfernoInferenceRepository(
    createRuntime(),
    engine: engine,
    modelPath: resolvedModelPath,
    profile: profile,
    initialCatalogKey:
        initialCatalogKey ??
        activeArtifactKeyFor(backend: backend, modelProfile: modelProfile),
    initialProjectorPath: initialProjectorPath,
    initialSupportsImages: initialSupportsImages,
    documentsDirectory: documentsDirectory,
    availableMemoryBytes: const DeviceStorageChannel().availableMemoryBytes,
    loadOptions: loadOptions,
    seed: samplingSeed == 0 ? null : samplingSeed,
    readAttachment: readAttachment,
  );
}
