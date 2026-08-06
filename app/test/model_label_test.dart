import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/features/chat/model_label.dart';

void main() {
  const real = InferenceBackendConfig(
    kind: InferenceBackendKind.mlx,
    profileKey: 'gemma4',
    artifactKey: 'gemma4-mlx',
    modelPath: '/models/gemma',
    modelPathFromCatalog: true,
  );

  test('a real engine\'s labels never follow the per-chat choice', () {
    // The engine ignores modelKey until #20, so every label must keep
    // naming the running artifact — anything else lies on-screen.
    expect(
      effectiveModelKey(
        backend: real,
        catalog: modelCatalog,
        modelKey: 'qwen35-gguf',
      ),
      'gemma4-mlx',
    );
    expect(
      chatModelSubtitle(
        backend: real,
        catalog: modelCatalog,
        modelKey: 'qwen35-gguf',
      ),
      'Gemma 4 E2B · on device',
    );
  });

  test('the fake honors the per-chat choice end to end', () {
    const fake = InferenceBackendConfig.fake();
    expect(
      effectiveModelKey(
        backend: fake,
        catalog: modelCatalog,
        modelKey: 'qwen35-gguf',
      ),
      'qwen35-gguf',
    );
    expect(
      chatModelSubtitle(
        backend: fake,
        catalog: modelCatalog,
        modelKey: 'qwen35-gguf',
      ),
      'Qwen 3.5 4B QAT · simulated',
    );
    expect(
      chatModelSubtitle(backend: fake, catalog: modelCatalog, modelKey: null),
      'Gemma 4 E2B · simulated',
    );
  });
}
