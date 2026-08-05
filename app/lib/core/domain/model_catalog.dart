/// Pure-data description of the downloadable model catalog.
///
/// Core stays inference-package-free: the values are built in
/// `lib/broker/model_catalog.dart` from the pinned Inferno manifest and
/// injected into repositories, so the manifest remains the single source of
/// model knowledge.
library;

enum ModelEngine { mlx, gguf }

final class ModelArtifactFile {
  const ModelArtifactFile({
    required this.path,
    required this.bytes,
    required this.sha256,
  });

  final String path;
  final int bytes;
  final String sha256;
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
  });

  /// Stable identifier, also the on-disk directory name under `models/`.
  /// The `<profile>-<engine>` shape lets the active artifact be derived from
  /// the GOLEM_MODEL_PROFILE and GOLEM_INFERENCE_BACKEND dart-defines.
  final String key;
  final String displayName;
  final ModelEngine engine;
  final String quantization;
  final String repository;
  final String revision;
  final List<ModelArtifactFile> files;

  int get totalBytes => files.fold(0, (sum, file) => sum + file.bytes);

  Uri get repositoryUrl =>
      Uri.https('huggingface.co', '/$repository/tree/$revision');

  /// Install location relative to the app documents directory, matching the
  /// `documents:` model-path convention used by the inference configuration.
  String get installDirectory => 'models/$key';
}
