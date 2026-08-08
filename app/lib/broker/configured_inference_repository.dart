import '../core/app_identity.dart';
import '../core/domain/inference_backend.dart';
import '../core/repositories/contracts.dart';
import '../core/repositories/fake_inference_repository.dart';
import '../core/services/device_storage.dart';
import 'backend_policy.dart';
import 'inferno_inference_repository.dart';
import 'model_catalog.dart';
import 'model_profile.dart';
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
}) => selectInferenceRepository(
  backend: config.kind.name,
  modelPath: config.modelPath ?? '',
  modelProfile: config.profileKey,
  // A fixed seed pins sampling for cross-device determinism probes; regular
  // builds leave it unset (0 sentinel -> engine-default seeding).
  samplingSeed: const int.fromEnvironment('GOLEM_SAMPLING_SEED'),
  fakeStreamDelay: fakeStreamDelay,
  documentsDirectory: documentsDirectory,
  createRuntime: InfernoRuntimeAdapter.native,
);

/// The dart-define values arrive as compile-time constants, so the selection
/// logic takes them as parameters — reachable from tests, and the
/// construction surface the eval harness uses to run combos through the
/// app's own repository (#42).
InferenceRepository selectInferenceRepository({
  required String backend,
  required String modelPath,
  required String modelProfile,
  required Duration fakeStreamDelay,
  required String documentsDirectory,
  required BrokerRuntime Function() createRuntime,
  required int samplingSeed,
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
    initialCatalogKey: activeArtifactKeyFor(
      backend: backend,
      modelProfile: modelProfile,
    ),
    documentsDirectory: documentsDirectory,
    availableMemoryBytes: const DeviceStorageChannel().availableMemoryBytes,
    seed: samplingSeed == 0 ? null : samplingSeed,
  );
}
