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
    // Chat-side switching UX is gated until #20, so every label must keep
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

  test('a real engine\'s labels follow actual residency', () {
    // The residency owner (#42) reports what the engine holds right now;
    // that outranks the boot-configured artifact and the per-chat choice.
    expect(
      effectiveModelKey(
        backend: real,
        catalog: modelCatalog,
        modelKey: 'gemma4-mlx',
        residentModelKey: 'qwen35-gguf',
      ),
      'qwen35-gguf',
    );
    expect(
      chatModelSubtitle(
        backend: real,
        catalog: modelCatalog,
        residentModelKey: 'qwen35-gguf',
      ),
      'Qwen 3.5 4B QAT · on device',
    );
    // An empty engine (lazy first load pending) falls back to the boot
    // artifact rather than blanking the chrome.
    expect(
      effectiveModelKey(
        backend: real,
        catalog: modelCatalog,
        residentModelKey: null,
      ),
      'gemma4-mlx',
    );
  });

  test('the fake\'s labels ignore residency and keep the per-chat key', () {
    const fake = InferenceBackendConfig.fake();
    expect(
      effectiveModelKey(
        backend: fake,
        catalog: modelCatalog,
        modelKey: 'qwen35-gguf',
        residentModelKey: 'gemma4-mlx',
      ),
      'qwen35-gguf',
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
