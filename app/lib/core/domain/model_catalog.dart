/// Pure-data description of the downloadable model catalog. Core stays
/// inference-package-free: values are built in `lib/broker/model_catalog.dart`
/// from the pinned Inferno manifest, the single source of model knowledge.
library;

import 'model_profile_spec.dart' show ModelInputModality;

export 'model_profile_spec.dart' show ModelInputModality;

enum ModelEngine { mlx, gguf }

/// [ModelCatalogEntry.profileKey] for an entry not yet resolved to a supported
/// broker profile: it lists and deletes normally but refuses activation.
const unresolvedProfileKey = 'unresolved';

/// A GGUF artifact names exactly one [weights] file and at most one
/// [projector]; an MLX artifact is a directory of [snapshot] files.
enum ModelFileRole { weights, projector, snapshot }

/// The catalog key a hand-added repository takes.
///
/// Hashed on top of a slug so two repositories differing only in punctuation
/// (`org/foo_bar`, `org/foo-bar`) cannot collapse onto one install directory and
/// replace each other's card and download state. Hand-rolled FNV-1a rather than
/// `hashCode`, which is not stable across runs or platforms.
String customCatalogKeyFor(String repository) {
  final slug = repository.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
  var hash = 0x811c9dc5;
  for (final unit in repository.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return 'custom-$slug-${hash.toRadixString(16).padLeft(8, '0')}';
}

final class ModelArtifactFile {
  const ModelArtifactFile({
    required this.path,
    required this.bytes,
    this.sha256,
    this.role = ModelFileRole.snapshot,
    this.repository,
    this.revision,
  });

  final String path;
  final int bytes;

  /// Null when none was published: Hugging Face returns an LFS hash for large
  /// files but nothing for small metadata ones (#52), so those are trusted via
  /// the immutable commit, their declared size, and the receipt's digest.
  final String? sha256;
  final ModelFileRole role;

  /// Set when this file lives in another repository — common for projectors.
  final String? repository;
  final String? revision;
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

  /// Stable identifier, also the on-disk directory name under `models/`. Pinned
  /// keys keep the `<profile>-<engine>` shape so GOLEM_MODEL_PROFILE and
  /// GOLEM_INFERENCE_BACKEND can name the active artifact, but activation reads
  /// [profileKey], never a slice of this string — a custom key has no profile.
  final String key;
  final String displayName;
  final ModelEngine engine;
  final String quantization;
  final String repository;
  final String revision;
  final List<ModelArtifactFile> files;

  /// The broker profile to render and sample with. Explicit, never inferred: a
  /// slug, file name or engine is no proof of a chat template (#43).
  final String profileKey;

  /// What this artifact on this engine is *proven* to accept: a profile can be
  /// image-capable on one engine and text-only on another (#18).
  final Set<ModelInputModality> inputModalities;

  bool get supportsImages => inputModalities.contains(ModelInputModality.image);

  int get totalBytes => files.fold(0, (sum, file) => sum + file.bytes);

  Uri get repositoryUrl =>
      Uri.https('huggingface.co', '/$repository/tree/$revision');

  /// Immutable download location for one file — per-file, so a projector's own
  /// source is not accidentally taken from the language-model repository.
  Uri resolveUrlFor(ModelArtifactFile file) => Uri.https(
    'huggingface.co',
    '/${file.repository ?? repository}'
        '/resolve/${file.revision ?? revision}/${file.path}',
  );

  /// Relative to app documents, per the `documents:` model-path convention.
  String get installDirectory => 'models/$key';
}
