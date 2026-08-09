/// Pure-data description of the downloadable model catalog.
///
/// Core stays inference-package-free: the values are built in
/// `lib/broker/model_catalog.dart` from the pinned Inferno manifest and
/// injected into repositories, so the manifest remains the single source of
/// model knowledge.
library;

import 'model_profile_spec.dart' show ModelInputModality;

export 'model_profile_spec.dart' show ModelInputModality;

enum ModelEngine { mlx, gguf }

/// [ModelCatalogEntry.profileKey] for an entry that has not yet been resolved
/// to a supported broker profile. Such an entry lists and deletes normally but
/// refuses activation with actionable copy — capability is never assumed.
const unresolvedProfileKey = 'unresolved';

/// What a downloaded file is for. A GGUF artifact names exactly one
/// [weights] file and at most one [projector]; an MLX artifact is a directory
/// of [snapshot] files.
enum ModelFileRole { weights, projector, snapshot }

final class ModelArtifactFile {
  const ModelArtifactFile({
    required this.path,
    required this.bytes,
    required this.sha256,
    this.role = ModelFileRole.snapshot,
  });

  final String path;
  final int bytes;
  final String sha256;
  final ModelFileRole role;
}

final class ModelCatalogEntry {
  const ModelCatalogEntry({
    required this.key,
    required this.displayName,
    required this.engine,
    required this.quantization,
    required this.repository,
    required this.revision,
    required this.files,
    required this.profileKey,
    this.inputModalities = const {ModelInputModality.text},
  });

  /// Stable identifier, also the on-disk directory name under `models/`.
  /// Pinned keys keep the `<profile>-<engine>` shape so the active artifact
  /// can be derived from the GOLEM_MODEL_PROFILE and GOLEM_INFERENCE_BACKEND
  /// dart-defines, but runtime activation reads [profileKey] rather than
  /// slicing this string — a custom entry's key encodes no profile.
  final String key;
  final String displayName;
  final ModelEngine engine;
  final String quantization;
  final String repository;
  final String revision;
  final List<ModelArtifactFile> files;

  /// The broker profile this artifact must be rendered and sampled with.
  /// Explicit rather than inferred: a repository slug, file name, or engine
  /// is never proof of a chat template (#43).
  final String profileKey;

  /// What this exact artifact on this exact engine has been *proven* to
  /// accept. Capability belongs to the artifact, not the model family: the
  /// same profile can be image-capable through one engine and text-only
  /// through another until that second path is validated (#18).
  final Set<ModelInputModality> inputModalities;

  bool get supportsImages => inputModalities.contains(ModelInputModality.image);

  int get totalBytes => files.fold(0, (sum, file) => sum + file.bytes);

  Uri get repositoryUrl =>
      Uri.https('huggingface.co', '/$repository/tree/$revision');

  /// Install location relative to the app documents directory, matching the
  /// `documents:` model-path convention used by the inference configuration.
  String get installDirectory => 'models/$key';
}
