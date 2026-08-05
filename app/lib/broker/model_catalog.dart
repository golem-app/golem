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
  ),
  _entry(
    key: 'gemma4-gguf',
    displayName: 'Gemma 4 E2B QAT',
    engine: ModelEngine.gguf,
    quantization: 'Q4_K_XL',
    artifact: gemma4E2BGgufQ4,
  ),
  _entry(
    key: 'qwen35-mlx',
    displayName: 'Qwen 3.5 4B QAT',
    engine: ModelEngine.mlx,
    quantization: '4-bit',
    artifact: qwen35Mlx4Bit,
  ),
  _entry(
    key: 'qwen35-gguf',
    displayName: 'Qwen 3.5 4B QAT',
    engine: ModelEngine.gguf,
    quantization: 'Q4_0',
    artifact: qwen35GgufQ4,
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

ModelCatalogEntry _entry({
  required String key,
  required String displayName,
  required ModelEngine engine,
  required String quantization,
  required InfernoModelArtifact artifact,
}) => ModelCatalogEntry(
  key: key,
  displayName: displayName,
  engine: engine,
  quantization: quantization,
  repository: artifact.repository,
  revision: artifact.revision,
  files: [
    for (final file in artifact.files)
      ModelArtifactFile(
        path: file.path,
        bytes: file.bytes,
        sha256: file.sha256,
      ),
  ],
);
