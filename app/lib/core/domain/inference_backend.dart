import 'model_catalog.dart';

/// Which inference backend this process runs. `fake` is the deterministic
/// simulation; `llama`/`mlx` are the real local engines.
enum InferenceBackendKind { fake, llama, mlx }

extension InferenceBackendKindEngines on InferenceBackendKind {
  /// Whether this process could load [engine] at all. The engine is a
  /// build-time composition, so an artifact of the other kind is dead disk
  /// rather than a runtime choice.
  bool loads(ModelEngine engine) => switch (this) {
    InferenceBackendKind.fake => true,
    InferenceBackendKind.llama => engine == ModelEngine.gguf,
    InferenceBackendKind.mlx => engine == ModelEngine.mlx,
  };
}

/// The resolved inference configuration for this process: one immutable
/// value derived at startup from dart-defines, flavor policy, and the
/// device-memory policy. Every "simulated" label keys on it, and the model
/// path, profile, and active artifact always travel together so they can
/// never disagree (a mismatched profile silently renders the wrong chat
/// template).
final class InferenceBackendConfig {
  const InferenceBackendConfig({
    required this.kind,
    required this.profileKey,
    this.artifactKey,
    this.modelPath,
    this.modelPathFromCatalog = false,
    this.artifactFromDevicePolicy = false,
    this.simulatedEngine,
  });

  const InferenceBackendConfig.fake()
    : kind = InferenceBackendKind.fake,
      profileKey = 'gemma4',
      artifactKey = null,
      artifactFromDevicePolicy = false,
      modelPath = null,
      modelPathFromCatalog = false,
      simulatedEngine = null;

  final InferenceBackendKind kind;

  /// Broker profile key (`gemma4`, `qwen35`); meaningful even under the
  /// fake backend so settings sections stay addressable.
  final String profileKey;

  /// Catalog key of the active downloadable artifact; null under the fake
  /// backend.
  final String? artifactKey;

  /// Model path, possibly `documents:`-prefixed; null under the fake
  /// backend. Empty means a real backend was requested without a path —
  /// the repository factory fails loudly on it at launch.
  final String? modelPath;

  /// True only when the policy derived [modelPath] from the catalog's
  /// install location. An operator-supplied `GOLEM_MODEL_PATH` (sideloads,
  /// the determinism probe) is the operator's responsibility and is validated
  /// by a real engine load before the consumer shell is exposed.
  final bool modelPathFromCatalog;

  /// Whether [artifactKey] came from the launch device classification rather
  /// than an operator define. Only the `auto` branch with no explicit artifact
  /// or profile consults the tier, so only then may copy credit it for the
  /// choice (#79).
  final bool artifactFromDevicePolicy;

  /// Under the fake only: the engine this platform's real build composes. The
  /// simulation carries no artifact, so its recommendation used to prefer MLX
  /// on every platform and QA on Android featured a model that build could
  /// never execute (#118). Resolved once, where every other engine answer is,
  /// so admission consumes a reading rather than taking a second one.
  final ModelEngine? simulatedEngine;

  bool get simulatedInference => kind == InferenceBackendKind.fake;

  /// A real engine pointed at an operator's own file. It has no catalog entry,
  /// so nothing may claim its capabilities, name it after a pinned artifact, or
  /// gate it behind a download.
  bool get sideloaded =>
      !simulatedInference && !modelPathFromCatalog && modelPath != null;
}
