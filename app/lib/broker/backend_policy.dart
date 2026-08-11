import '../core/app_identity.dart';
import '../core/domain/device_eligibility.dart';
import '../core/domain/inference_backend.dart';
import '../core/domain/model_catalog.dart';
import 'model_catalog.dart';

/// Which engine this build composes, before any device is classified: the
/// dart-define when there is one, else the flavor default. Resolved on its own
/// because the capability probe has to know which engine to ask about, and the
/// full policy needs that probe's verdict.
String resolveBackendName({
  required String backendDefine,
  required AppIdentity identity,
}) => backendDefine.isNotEmpty
    ? backendDefine
    : switch (identity) {
        AppIdentity.production || AppIdentity.dev => 'auto',
        AppIdentity.qa || AppIdentity.flutter => 'fake',
      };

/// Pure. `auto` is the llama/GGUF artifact of the device-policy model (ADR 0002
/// makes llama.cpp the v0 engine); an operator-supplied `GOLEM_MODEL_PATH` is
/// the separate, capability-unproven sideload contract. Passing `auto`
/// explicitly lets a qa build exercise the exact production composition — the
/// only route on the physical iPhone, where production/dev bundle ids are
/// off-limits.
///
/// [backendName] is [resolveBackendName]'s answer, passed in rather than
/// re-derived: the engine that was probed and the engine that is composed must
/// be the same one by construction, for the same reason [tier] is.
///
/// [tier] comes from the one device classification the launch made, so the
/// model this build selects and the eligibility its surfaces report can never
/// disagree. An unsupported device still resolves the lighter model: nothing
/// will load it, but every label stays addressable.
InferenceBackendConfig resolveBackendPolicy({
  required String backendName,
  required String profileDefine,
  required String artifactDefine,
  required String modelPathDefine,
  required DeviceTier tier,
}) {
  final explicitProfile = profileDefine.isEmpty ? null : profileDefine;
  final explicitArtifact = artifactDefine.isEmpty ? null : artifactDefine;
  if (explicitArtifact != null && modelPathDefine.isNotEmpty) {
    throw StateError(
      'GOLEM_MODEL_ARTIFACT and GOLEM_MODEL_PATH are mutually exclusive.',
    );
  }
  switch (backendName) {
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
      final expectedEngine = backendName == 'llama'
          ? ModelEngine.gguf
          : ModelEngine.mlx;
      final selected = explicitArtifact == null
          ? null
          : _catalogArtifact(explicitArtifact, expectedEngine);
      final profileKey = explicitProfile ?? selected?.profileKey ?? 'gemma4';
      _requireMatchingProfile(selected, profileKey);
      final artifactKey =
          selected?.key ??
          activeArtifactKeyFor(backend: backendName, modelProfile: profileKey)!;
      return InferenceBackendConfig(
        kind: backendName == 'llama'
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
      final profileKey =
          explicitProfile ??
          selected?.profileKey ??
          (tier == DeviceTier.preferred ? 'gemma4' : 'qwen35');
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
