import '../core/app_identity.dart';
import '../core/domain/inference_backend.dart';
import '../core/domain/model_catalog.dart';
import 'model_catalog.dart';

/// 7 GiB rather than a literal 8 GB because Android's totalMem reports net of
/// kernel/firmware reservations (a nominal 8 GB phone reads ~7.5 GB): the
/// policy classifies nominal capacity, not reported bytes
/// (docs/decisions/0003-flavor-backend-defaults.md).
const int deviceMemoryThresholdBytes = 7 * 1024 * 1024 * 1024;

/// Pure apart from the injected memory probe. `auto` is the llama/GGUF artifact
/// of the device-policy model (ADR 0002 makes llama.cpp the v0 engine); an
/// operator-supplied `GOLEM_MODEL_PATH` is the separate, capability-unproven
/// sideload contract. Passing `auto` explicitly lets a qa build exercise the
/// exact production composition — the only route on the physical iPhone, where
/// production/dev bundle ids are off-limits.
Future<InferenceBackendConfig> resolveBackendPolicy({
  required String backendDefine,
  required String profileDefine,
  required String artifactDefine,
  required String modelPathDefine,
  required AppIdentity identity,
  required int memoryOverrideBytes,
  required Future<int?> Function() physicalMemoryBytes,
}) async {
  final backend = backendDefine.isNotEmpty
      ? backendDefine
      : switch (identity) {
          AppIdentity.production || AppIdentity.dev => 'auto',
          AppIdentity.qa || AppIdentity.flutter => 'fake',
        };
  final explicitProfile = profileDefine.isEmpty ? null : profileDefine;
  final explicitArtifact = artifactDefine.isEmpty ? null : artifactDefine;
  if (explicitArtifact != null && modelPathDefine.isNotEmpty) {
    throw StateError(
      'GOLEM_MODEL_ARTIFACT and GOLEM_MODEL_PATH are mutually exclusive.',
    );
  }
  switch (backend) {
    case 'fake':
      if (explicitArtifact != null) {
        throw StateError(
          'GOLEM_MODEL_ARTIFACT requires a real inference backend.',
        );
      }
      return InferenceBackendConfig(
        kind: InferenceBackendKind.fake,
        profileKey: explicitProfile ?? 'gemma4',
      );
    case 'llama' || 'mlx':
      final expectedEngine = backend == 'llama'
          ? ModelEngine.gguf
          : ModelEngine.mlx;
      final selected = explicitArtifact == null
          ? null
          : _catalogArtifact(explicitArtifact, expectedEngine);
      final profileKey = explicitProfile ?? selected?.profileKey ?? 'gemma4';
      _requireMatchingProfile(selected, profileKey);
      final artifactKey =
          selected?.key ??
          activeArtifactKeyFor(backend: backend, modelProfile: profileKey)!;
      return InferenceBackendConfig(
        kind: backend == 'llama'
            ? InferenceBackendKind.llama
            : InferenceBackendKind.mlx,
        profileKey: profileKey,
        artifactKey: artifactKey,
        // An engine override without a path still names an exact pinned
        // artifact: use its catalog path so capability provenance survives.
        modelPath: modelPathDefine.isEmpty
            ? primaryModelPathFor(artifactKey)
            : modelPathDefine,
        modelPathFromCatalog: modelPathDefine.isEmpty,
      );
    case 'auto':
      final selected = explicitArtifact == null
          ? null
          : _catalogArtifact(explicitArtifact, ModelEngine.gguf);
      final memory = selected == null && explicitProfile == null
          ? memoryOverrideBytes > 0
                ? memoryOverrideBytes
                : await _guardedProbe(physicalMemoryBytes)
          : null;
      final profileKey =
          explicitProfile ??
          selected?.profileKey ??
          (memory != null && memory >= deviceMemoryThresholdBytes
              ? 'gemma4'
              : 'qwen35');
      _requireMatchingProfile(selected, profileKey);
      // Explicit qwen35 remains the established 4B choice. Only the
      // automatic low-memory branch opts into the new 2B artifact.
      final artifactKey =
          selected?.key ??
          (explicitProfile == null && profileKey == 'qwen35'
              ? 'qwen35-2b-gguf'
              : '$profileKey-gguf');
      return InferenceBackendConfig(
        kind: InferenceBackendKind.llama,
        profileKey: profileKey,
        artifactKey: artifactKey,
        modelPath: modelPathDefine.isNotEmpty
            ? modelPathDefine
            : primaryModelPathFor(artifactKey),
        modelPathFromCatalog: modelPathDefine.isEmpty,
      );
    default:
      throw StateError(
        'GOLEM_INFERENCE_BACKEND must be fake, llama, mlx, or auto.',
      );
  }
}

ModelCatalogEntry _catalogArtifact(String key, ModelEngine expectedEngine) {
  final matches = modelCatalog.where((entry) => entry.key == key);
  if (matches.isEmpty) {
    throw StateError('GOLEM_MODEL_ARTIFACT does not name a catalog artifact.');
  }
  final entry = matches.single;
  if (entry.engine != expectedEngine) {
    throw StateError(
      'GOLEM_MODEL_ARTIFACT does not match GOLEM_INFERENCE_BACKEND.',
    );
  }
  return entry;
}

void _requireMatchingProfile(ModelCatalogEntry? entry, String profileKey) {
  if (entry != null && entry.profileKey != profileKey) {
    throw StateError(
      'GOLEM_MODEL_ARTIFACT does not match GOLEM_MODEL_PROFILE.',
    );
  }
}

/// Unknown memory must select the lighter model, never block launch.
Future<int?> _guardedProbe(Future<int?> Function() probe) async {
  try {
    return await probe().timeout(const Duration(seconds: 1));
  } catch (_) {
    return null;
  }
}
