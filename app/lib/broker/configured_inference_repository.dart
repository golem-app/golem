import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_identity.dart';
import '../core/domain/device_eligibility.dart';
import '../core/domain/inference_backend.dart';
import '../core/domain/model_catalog.dart';
import '../core/repositories/contracts.dart';
import '../core/repositories/fake_inference_repository.dart';
import '../core/services/device_storage.dart';
import 'backend_policy.dart';
import 'device_capability.dart';
import 'inferno_inference_repository.dart';
import 'model_catalog.dart';
import 'model_profile.dart';
import 'model_runtime_config.dart';
import 'runtime.dart';

/// Called once in main(); the result is the single source of truth for the
/// inference repository, the active artifact, the backend signal provider, and
/// what this device is allowed to run. The device is read once here: the model
/// the build selects and the eligibility its surfaces report come from the same
/// classification, so they cannot disagree.
Future<
  ({
    InferenceBackendConfig config,
    DeviceEligibility eligibility,
    bool virtualDevice,
  })
>
resolveConfiguredBackend({
  required AppIdentity identity,
  Future<bool?> Function()? isVirtualDevice,
}) async {
  const backendDefine = String.fromEnvironment('GOLEM_INFERENCE_BACKEND');
  // Ahead of the engine, because it can change which engine there is to probe.
  final virtualDevice = await probeVirtualDevice(
    isVirtualDevice ?? const DeviceStorageChannel().isVirtualDevice,
  );
  final backendName = resolveBackendName(
    backendDefine: backendDefine,
    identity: identity,
    virtualDevice: virtualDevice ?? false,
  );
  final platform = switch ((
    Platform.isIOS,
    Platform.isAndroid,
    Platform.isMacOS,
  )) {
    (true, _, _) => HostPlatform.ios,
    (_, true, _) => HostPlatform.android,
    (_, _, true) => HostPlatform.macos,
    _ => HostPlatform.other,
  };
  final engineName = resolvedEngineName(
    backendName: backendName,
    platform: platform,
  );
  final overrides = deviceCapabilityOverridesFor(
    identity: identity,
    memoryOverrideBytes: const int.fromEnvironment('GOLEM_DEVICE_MEMORY_BYTES'),
    forceEngineUnsupported: const bool.fromEnvironment(
      'GOLEM_DEVICE_ENGINE_UNSUPPORTED',
    ),
  );
  final capabilities = await probeDeviceCapabilities(
    backendName: engineName,
    physicalMemoryBytes: const DeviceStorageChannel().physicalMemoryBytes,
    // Test-only: both test phones report over 8 GB, so neither the Qwen branch
    // nor the floor is otherwise reachable on hardware. 0 = unset.
    memoryOverrideBytes: overrides.memoryOverrideBytes,
    // Test-only counterpart for the instruction-set refusal, which no device
    // here can produce: every one of them carries the extension.
    forceEngineUnsupported: overrides.forceEngineUnsupported,
    virtualDevice: virtualDevice,
  );
  final eligibility = classifyDevice(
    capabilities: capabilities,
    memoryFloorBytes: deviceMemoryFloorBytes(
      reportsInstalledMemory: Platform.isIOS || Platform.isMacOS,
    ),
  );
  return (
    config: resolveBackendPolicy(
      backendName: backendName,
      profileDefine: const String.fromEnvironment('GOLEM_MODEL_PROFILE'),
      artifactDefine: const String.fromEnvironment('GOLEM_MODEL_ARTIFACT'),
      modelPathDefine: const String.fromEnvironment('GOLEM_MODEL_PATH'),
      tier: eligibility.tier,
      platform: platform,
    ),
    eligibility: eligibility,
    virtualDevice: virtualDevice ?? false,
  );
}

({int memoryOverrideBytes, bool forceEngineUnsupported})
deviceCapabilityOverridesFor({
  required AppIdentity identity,
  required int memoryOverrideBytes,
  required bool forceEngineUnsupported,
}) => identity.internalToolsEnabled
    ? (
        memoryOverrideBytes: memoryOverrideBytes,
        forceEngineUnsupported: forceEngineUnsupported,
      )
    : (memoryOverrideBytes: 0, forceEngineUnsupported: false);

InferenceRepository createConfiguredInferenceRepository({
  required AppIdentity identity,
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
    identity: identity,
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
    diagnosticSink: identity.internalToolsEnabled ? debugPrint : null,
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
  required AppIdentity identity,
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
  InferenceDiagnosticSink? diagnosticSink,
}) {
  if (backend == 'fake') {
    return FakeInferenceRepository(
      eventDelay: fakeStreamDelay,
      // The same seam activation reads, not the pinned list: the simulation
      // must be able to name a repository added after launch, which is a
      // flow QA supports.
      catalog: activationCatalog ?? () => modelCatalog,
    );
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
    diagnosticSink: identity.internalToolsEnabled ? diagnosticSink : null,
  );
}
