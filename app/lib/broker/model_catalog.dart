import '../core/domain/model_catalog.dart';
import 'runtime.dart';

/// The pinned Inferno manifest artifacts as app-domain entries. Keys follow
/// `<profile>-<engine>`, so the active artifact derives from the
/// GOLEM_MODEL_PROFILE and GOLEM_INFERENCE_BACKEND dart-defines.
///
/// Display names are the family and its parameter size and nothing else. The
/// quantization one name used to carry ("Gemma 4 E2B QAT") is an artifact fact,
/// and artifact facts belong behind Advanced mode (#79,
/// `docs/decisions/0008-model-presentation.md`). Two entries of one family may
/// therefore share a name; the picker disambiguates by engine when both are on
/// screen at once.
///
/// What each model is *for* lives in the ARB catalogs, keyed off this entry's
/// key prefix (`model_choice.dart`), not on the entry: a `summary` field here
/// would be the English one nobody translates (#130). Those sentences describe
/// shape and speed, never quality — the only comparative evidence this project
/// holds is decode rates and the records under `docs/evals/`, and Qwen 3.5 2B's
/// accuracy caveats in `docs/real-model-matrix.md` are exactly why no entry
/// claims to be the better answerer.
final List<ModelCatalogEntry> modelCatalog = [
  _entry(
    key: 'gemma4-mlx',
    displayName: 'Gemma 4 E2B',
    engine: ModelEngine.mlx,
    quantization: '4-bit',
    artifact: gemma4E2BMlx4Bit,
    profileKey: 'gemma4',
    inputModalities: const {ModelInputModality.text, ModelInputModality.image},
  ),
  _entry(
    key: 'gemma4-gguf',
    displayName: 'Gemma 4 E2B',
    engine: ModelEngine.gguf,
    quantization: 'Q4_K_XL',
    artifact: gemma4E2BGgufQ4,
    profileKey: 'gemma4',
    // llama.cpp/libmtmd with the pinned projector passed the #18 bake-off.
    // Capability belongs to this exact artifact, not the whole family.
    inputModalities: const {ModelInputModality.text, ModelInputModality.image},
  ),
  _entry(
    key: 'qwen35-2b-mlx',
    displayName: 'Qwen 3.5 2B',
    engine: ModelEngine.mlx,
    quantization: '4-bit',
    artifact: qwen35TwoBMlx4Bit,
    profileKey: 'qwen35',
    inputModalities: const {ModelInputModality.text, ModelInputModality.image},
  ),
  _entry(
    key: 'qwen35-2b-gguf',
    displayName: 'Qwen 3.5 2B',
    engine: ModelEngine.gguf,
    quantization: 'Q4_0',
    artifact: qwen35TwoBGgufQ4,
    profileKey: 'qwen35',
    inputModalities: const {ModelInputModality.text, ModelInputModality.image},
  ),
  _entry(
    key: 'qwen35-mlx',
    displayName: 'Qwen 3.5 4B',
    engine: ModelEngine.mlx,
    quantization: '4-bit',
    artifact: qwen35Mlx4Bit,
    profileKey: 'qwen35',
    inputModalities: const {ModelInputModality.text, ModelInputModality.image},
  ),
  _entry(
    key: 'qwen35-gguf',
    displayName: 'Qwen 3.5 4B',
    engine: ModelEngine.gguf,
    quantization: 'Q4_0',
    artifact: qwen35GgufQ4,
    profileKey: 'qwen35',
    inputModalities: const {ModelInputModality.text, ModelInputModality.image},
  ),
];

/// The download surface and the inference configuration are independent axes;
/// this is the only bridge between them.
String? activeArtifactKeyFor({
  required String backend,
  required String modelProfile,
}) => switch (backend) {
  'mlx' => '$modelProfile-mlx',
  'llama' => '$modelProfile-gguf',
  _ => null,
};

/// The `documents:`-relative path Inferno loads for an installed entry, derived
/// from the pinned manifest so path, profile, and artifact cannot disagree.
String primaryModelPathFor(String key) {
  final entry = modelCatalog.firstWhere(
    (item) => item.key == key,
    orElse: () => throw ArgumentError.value(key, 'key', 'Unknown catalog key'),
  );
  final path = modelPathForEntry(entry);
  if (path == null) {
    final weights = entry.files.where((file) => file.path.endsWith('.gguf'));
    throw StateError(
      'Catalog entry $key must pin exactly one .gguf file, '
      'found ${weights.length}.',
    );
  }
  return path;
}

/// Null when the entry pins no projector — or, defensively, more than one.
String? projectorPathForEntry(ModelCatalogEntry entry) {
  final projectors = entry.files
      .where((file) => file.role == ModelFileRole.projector)
      .toList();
  if (projectors.length != 1) return null;
  return 'documents:${entry.installDirectory}/${projectors.single.path}';
}

/// Null when the entry does not describe exactly one loadable artifact;
/// activation turns that into a typed failure, not a raw [StateError].
String? modelPathForEntry(ModelCatalogEntry entry) {
  switch (entry.engine) {
    case ModelEngine.gguf:
      // Role, not extension: a multimodal artifact pins two .gguf files.
      final weights = entry.files
          .where((file) => file.role == ModelFileRole.weights)
          .toList();
      if (weights.isEmpty) {
        final unroled = entry.files
            .where((file) => file.path.endsWith('.gguf'))
            .toList();
        if (unroled.length != 1) return null;
        return 'documents:${entry.installDirectory}/${unroled.single.path}';
      }
      if (weights.length != 1) return null;
      return 'documents:${entry.installDirectory}/${weights.single.path}';
    case ModelEngine.mlx:
      return 'documents:${entry.installDirectory}';
  }
}

ModelCatalogEntry _entry({
  required String key,
  required String displayName,
  required ModelEngine engine,
  required String quantization,
  required InfernoModelArtifact artifact,
  required String profileKey,
  Set<ModelInputModality> inputModalities = const {ModelInputModality.text},
}) => ModelCatalogEntry(
  key: key,
  displayName: displayName,
  engine: engine,
  quantization: quantization,
  repository: artifact.repository,
  revision: artifact.revision,
  profileKey: profileKey,
  inputModalities: inputModalities,
  files: [
    for (final file in artifact.files)
      ModelArtifactFile(
        path: file.path,
        bytes: file.bytes,
        sha256: file.sha256,
        repository: file.repository,
        revision: file.revision,
        role: switch (file.role) {
          InfernoFileRole.weights => ModelFileRole.weights,
          InfernoFileRole.projector => ModelFileRole.projector,
          InfernoFileRole.snapshot => ModelFileRole.snapshot,
        },
      ),
  ],
);
