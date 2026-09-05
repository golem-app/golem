import '../core/app_identity.dart';
import '../core/domain/device_eligibility.dart';
import '../core/domain/inference_backend.dart';
import '../core/domain/model_catalog.dart';
import 'model_catalog.dart';

/// The host family that decides the platform-owned automatic engine. Kept
/// independent of Flutter's platform enum so broker policy remains pure and
/// host tests can cover every branch without mutating global platform state.
enum HostPlatform { ios, android, macos, other }

String resolvedEngineName({
  required String backendName,
  required HostPlatform platform,
}) => backendName != 'auto'
    ? backendName
    : switch (platform) {
        HostPlatform.ios => 'mlx',
        HostPlatform.android ||
        HostPlatform.macos ||
        HostPlatform.other => 'llama',
      };

/// Which engine this build composes, before any device is classified: the
/// dart-define when there is one, else the flavor default. Resolved on its own
/// because the capability probe has to know which engine to ask about, and the
/// full policy needs that probe's verdict.
///
/// [virtualDevice] moves an internal build to the fake rather than letting it
/// compose an engine no simulator or emulator can run (#148), but only through
/// [virtualDeviceComposesFake] — a build that named any model configuration is
/// asking for the real path and keeps it.
String resolveBackendName({
  required String backendDefine,
  required AppIdentity identity,
  required bool virtualDevice,
  required String artifactDefine,
  required String modelPathDefine,
}) => backendDefine.isNotEmpty
    ? backendDefine
    : virtualDeviceComposesFake(
        identity: identity,
        virtualDevice: virtualDevice,
        artifactDefine: artifactDefine,
        modelPathDefine: modelPathDefine,
      )
    ? 'fake'
    : switch (identity) {
        // The lab composes the real engines like dev; `auto` only names the
        // inert initial target the repository is constructed around, and every
        // bench run activates its own configuration by key (ADR 0021).
        AppIdentity.production || AppIdentity.dev || AppIdentity.lab => 'auto',
        AppIdentity.qa => 'fake',
      };

/// Whether a virtual device may swap this build's composition for the fake.
///
/// Only `qa` and `dev`: production's composition stays a pure build-time fact,
/// so a device reading that ever answered wrong on a phone can refuse a
/// shipping build but never quietly simulate one.
///
/// And only a build that named no model configuration at all. An artifact or a
/// path define is an operator asking for the real path just as much as an
/// engine define is, and the fake branch of [resolveBackendPolicy] cannot honour
/// either — it throws on an artifact and ignores a path. Swapping under them
/// would turn `--dart-define=GOLEM_MODEL_ARTIFACT=…` into a terminal
/// misconfiguration pane and a sideload into a silent simulation.
bool virtualDeviceComposesFake({
  required AppIdentity identity,
  required bool virtualDevice,
  required String artifactDefine,
  required String modelPathDefine,
}) =>
    virtualDevice &&
    identity.internalToolsEnabled &&
    artifactDefine.isEmpty &&
    modelPathDefine.isEmpty;

/// Whether this launch composes the download simulation instead of the real
/// downloader. Simulated inference is the precondition in every case: a real
/// engine fed by a simulated install would "install" files that do not exist
/// (ADR 0003). Beyond that, `qa` is the deterministic-automation identity, and
/// a virtual device is the one where a real transfer could only ever produce
/// bytes nothing can load — under the same identity gate as
/// [virtualDeviceComposesFake], so production's model management stays a
/// build-time fact too.
bool useFakeModelManagement({
  required AppIdentity identity,
  required bool simulatedInference,
  required bool virtualDevice,
}) =>
    simulatedInference &&
    (identity == AppIdentity.qa ||
        (virtualDevice && identity.internalToolsEnabled));

/// Pure. `auto` is the platform engine's artifact of the device-policy model
/// (ADR 0012); an operator-supplied `GOLEM_MODEL_PATH` is the separate,
/// capability-unproven sideload contract. Passing `auto`
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
  HostPlatform platform = HostPlatform.other,
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
        // QA stays hardware-independent, but not platform-independent: the
        // engine is a build composition, identical for qa and production on
        // the same platform, so the simulation may as well feature what the
        // product would.
        simulatedEngine:
            resolvedEngineName(backendName: 'auto', platform: platform) == 'mlx'
            ? ModelEngine.mlx
            : ModelEngine.gguf,
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
      final engineName = resolvedEngineName(
        backendName: backendName,
        platform: platform,
      );
      final engine = engineName == 'mlx' ? ModelEngine.mlx : ModelEngine.gguf;
      final artifactSuffix = engine == ModelEngine.mlx ? 'mlx' : 'gguf';
      final selected = explicitArtifact == null
          ? null
          : _catalogArtifact(explicitArtifact, engine);
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
              ? 'qwen35-2b-$artifactSuffix'
              : '$profileKey-$artifactSuffix');
      return InferenceBackendConfig(
        kind: engineName == 'mlx'
            ? InferenceBackendKind.mlx
            : InferenceBackendKind.llama,
        profileKey: profileKey,
        artifactKey: artifactKey,
        modelPath: modelPathDefine.isNotEmpty
            ? modelPathDefine
            : primaryModelPathFor(artifactKey),
        modelPathFromCatalog: modelPathDefine.isEmpty,
        // The tier picked this only when nothing else did.
        artifactFromDevicePolicy:
            explicitArtifact == null && explicitProfile == null,
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
