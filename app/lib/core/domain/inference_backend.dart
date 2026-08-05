/// Which inference backend this process runs. `fake` is the deterministic
/// simulation; `llama`/`mlx` are the real local engines.
enum InferenceBackendKind { fake, llama, mlx }

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
  });

  const InferenceBackendConfig.fake()
    : kind = InferenceBackendKind.fake,
      profileKey = 'gemma4',
      artifactKey = null,
      modelPath = null;

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

  bool get simulatedInference => kind == InferenceBackendKind.fake;
}
