import '../core/app_identity.dart';
import '../core/domain/inference_backend.dart';
import '../core/domain/model_catalog.dart';
import '../core/repositories/contracts.dart';
import '../core/repositories/fake_inference_repository.dart';
import '../core/services/device_storage.dart';
import 'backend_policy.dart';
import 'inferno_inference_repository.dart';
import 'model_catalog.dart';
import 'model_profile.dart';
import 'model_runtime_config.dart';
import 'runtime.dart';

/// Called once in main(); the result is the single source of truth for the
/// inference repository, the active artifact, and the backend signal provider.
Future<InferenceBackendConfig> resolveConfiguredBackend() =>
    resolveBackendPolicy(
      backendDefine: const String.fromEnvironment('GOLEM_INFERENCE_BACKEND'),
      profileDefine: const String.fromEnvironment('GOLEM_MODEL_PROFILE'),
      artifactDefine: const String.fromEnvironment('GOLEM_MODEL_ARTIFACT'),
      modelPathDefine: const String.fromEnvironment('GOLEM_MODEL_PATH'),
      identity: AppIdentity.current,
      // Test-only: both test phones report over 8 GB, so the Qwen branch is
      // otherwise unreachable. 0 = unset.
      memoryOverrideBytes: const int.fromEnvironment(
        'GOLEM_DEVICE_MEMORY_BYTES',
      ),
      physicalMemoryBytes: const DeviceStorageChannel().physicalMemoryBytes,
    );

InferenceRepository createConfiguredInferenceRepository({
  required InferenceBackendConfig config,
  required Duration fakeStreamDelay,
  required String documentsDirectory,
  Future<List<int>?> Function(String attachmentId)? readAttachment,
  List<ModelCatalogEntry> Function()? activationCatalog,
}) {
  // Only a catalog-derived path inherits the projector and its capability
  // proof; a sideload stays text-only until its own pairing is validated.
  final initialRuntime =
      config.modelPathFromCatalog && config.artifactKey != null
      ? resolveModelRuntimeConfig(config.artifactKey!)
      : null;
  return selectInferenceRepository(
    backend: config.kind.name,
    modelPath: config.modelPath ?? '',
    modelProfile: config.profileKey,
    initialCatalogKey: config.artifactKey,
    sideloaded: config.sideloaded,
    initialProjectorPath: initialRuntime?.projectorPath,
    initialSupportsImages: initialRuntime?.supportsImages ?? false,
    activationCatalog: activationCatalog,
    // A fixed seed pins sampling for determinism probes (0 = engine default).
    samplingSeed: const int.fromEnvironment('GOLEM_SAMPLING_SEED'),
    fakeStreamDelay: fakeStreamDelay,
    documentsDirectory: documentsDirectory,
    createRuntime: InfernoRuntimeAdapter.native,
    readAttachment: readAttachment,
    // Measurement and triage hatches: dart-defines, no UI — evidence decides
    // defaults before a knob earns a settings row.
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

/// Takes the dart-defines as parameters — they are compile-time constants — so
/// tests and the eval harness can construct the app's own repository (#42).
InferenceRepository selectInferenceRepository({
  required String backend,
  required String modelPath,
  required String modelProfile,
  String? initialCatalogKey,
  String? initialProjectorPath,
  bool initialSupportsImages = false,

  /// A real engine on an operator's own path. No catalog key is inferred for
  /// it, so residency reports nothing rather than naming a pinned artifact the
  /// engine does not hold.
  bool sideloaded = false,

  /// The entries activation may resolve, read on every switch so a repository
  /// added after launch is reachable. Null keeps the pinned catalog.
  List<ModelCatalogEntry> Function()? activationCatalog,
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
  // A typo'd dart-define has no recoverable runtime state: fail at launch.
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
    initialCatalogKey: sideloaded
        ? null
        : initialCatalogKey ??
              activeArtifactKeyFor(
                backend: backend,
                modelProfile: modelProfile,
              ),
    initialProjectorPath: initialProjectorPath,
    initialSupportsImages: initialSupportsImages,
    resolveConfig: activationCatalog == null
        ? resolveModelRuntimeConfig
        : (key) => resolveModelRuntimeConfig(key, catalog: activationCatalog()),
    documentsDirectory: documentsDirectory,
    availableMemoryBytes: const DeviceStorageChannel().availableMemoryBytes,
    loadOptions: loadOptions,
    seed: samplingSeed == 0 ? null : samplingSeed,
    readAttachment: readAttachment,
  );
}
