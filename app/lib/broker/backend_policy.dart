import '../core/app_identity.dart';
import '../core/domain/inference_backend.dart';
import 'model_catalog.dart';

/// Devices reporting at least this much physical memory default to
/// Gemma 4 E2B; below it — or when memory is unknown — the lighter
/// Qwen 3.5 4B. The threshold is 7 GiB rather than a literal 8 GB because
/// Android's totalMem reports net of kernel/firmware reservations (a
/// nominal 8 GB phone reads ~7.5 GB); the policy classifies nominal
/// capacity, not reported bytes. Rationale:
/// docs/decisions/0003-flavor-backend-defaults.md.
const int deviceMemoryThresholdBytes = 7 * 1024 * 1024 * 1024;

/// Resolves the effective inference backend from the dart-defines and the
/// flavor policy. Pure apart from the injected memory probe, so the whole
/// flavor x define x memory matrix is unit-testable.
///
/// Precedence: an explicit `GOLEM_INFERENCE_BACKEND` always wins
/// (`fake|llama|mlx|auto`); unset falls to the flavor default —
/// `production`/`dev` run `auto`, `qa` and the flavorless test identity
/// stay `fake`. `auto` is the flavor-default composition: the llama/GGUF
/// artifact of the device-policy model (ADR 0002 makes llama.cpp the v0
/// engine), with `GOLEM_MODEL_PROFILE` / `GOLEM_MODEL_PATH` overriding the
/// policy's model choice and install-derived path when set. Passing `auto`
/// explicitly lets a qa build exercise the exact production composition —
/// the only route on the physical iPhone, where production/dev bundle ids
/// are off-limits.
Future<InferenceBackendConfig> resolveBackendPolicy({
  required String backendDefine,
  required String profileDefine,
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
  switch (backend) {
    case 'fake':
      return InferenceBackendConfig(
        kind: InferenceBackendKind.fake,
        profileKey: explicitProfile ?? 'gemma4',
      );
    case 'llama' || 'mlx':
      final profileKey = explicitProfile ?? 'gemma4';
      return InferenceBackendConfig(
        kind: backend == 'llama'
            ? InferenceBackendKind.llama
            : InferenceBackendKind.mlx,
        profileKey: profileKey,
        artifactKey: activeArtifactKeyFor(
          backend: backend,
          modelProfile: profileKey,
        ),
        // Deliberately not defaulted: today's explicit opt-in contract
        // requires the operator to supply the path, and a missing one
        // stays a loud launch-time error.
        modelPath: modelPathDefine,
      );
    case 'auto':
      final memory = memoryOverrideBytes > 0
          ? memoryOverrideBytes
          : await _guardedProbe(physicalMemoryBytes);
      final profileKey =
          explicitProfile ??
          (memory != null && memory >= deviceMemoryThresholdBytes
              ? 'gemma4'
              : 'qwen35');
      final artifactKey = '$profileKey-gguf';
      return InferenceBackendConfig(
        kind: InferenceBackendKind.llama,
        profileKey: profileKey,
        artifactKey: artifactKey,
        modelPath: modelPathDefine.isNotEmpty
            ? modelPathDefine
            : primaryModelPathFor(artifactKey),
      );
    default:
      throw StateError(
        'GOLEM_INFERENCE_BACKEND must be fake, llama, mlx, or auto.',
      );
  }
}

/// Unknown memory must select the lighter model, never block launch: cap
/// the probe at one second and fold every failure into null.
Future<int?> _guardedProbe(Future<int?> Function() probe) async {
  try {
    return await probe().timeout(const Duration(seconds: 1));
  } catch (_) {
    return null;
  }
}
