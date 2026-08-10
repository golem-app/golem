import '../core/domain/model_catalog.dart';
import 'runtime.dart';

/// The downloadable catalog: the pinned Inferno manifest artifacts mapped to
/// app-domain entries with display metadata. Keys follow
/// `<profile>-<engine>` so the active artifact derives from the
/// GOLEM_MODEL_PROFILE and GOLEM_INFERENCE_BACKEND dart-defines.
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
    displayName: 'Gemma 4 E2B QAT',
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

/// The catalog key implied by the inference dart-defines, or null for the
/// fake backend. The download surface and the inference configuration are
/// independent axes; this is the only bridge between them.
String? activeArtifactKeyFor({
  required String backend,
  required String modelProfile,
}) => switch (backend) {
  'mlx' => '$modelProfile-mlx',
  'llama' => '$modelProfile-gguf',
  _ => null,
};

/// The `documents:`-relative model path Inferno loads for an installed
/// catalog entry: the single `.gguf` file for llama, the install directory
/// for MLX. Derived from the pinned manifest so the path, profile, and
/// artifact can never disagree.
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

/// The `documents:`-relative path of an entry's multimodal projector, or null
/// when it pins none. A projector is only ever loaded alongside the weights it
/// was pinned with.
String? projectorPathForEntry(ModelCatalogEntry entry) {
  final projectors = entry.files
      .where((file) => file.role == ModelFileRole.projector)
      .toList();
  if (projectors.length != 1) return null;
  return 'documents:${entry.installDirectory}/${projectors.single.path}';
}

/// The `documents:`-relative path for any catalog entry — pinned or resolved
/// custom — or null when the entry does not describe one loadable artifact.
/// Runtime activation turns that null into a typed, actionable failure rather
/// than a raw [StateError]; see `model_runtime_config.dart`.
String? modelPathForEntry(ModelCatalogEntry entry) {
  switch (entry.engine) {
    case ModelEngine.gguf:
      // Role, not extension: a multimodal artifact pins two .gguf files and
      // only one of them is the language model.
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
