import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_activation.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/chat/model_label.dart';

void main() {
  const real = InferenceBackendConfig(
    kind: InferenceBackendKind.mlx,
    profileKey: 'gemma4',
    artifactKey: 'gemma4-mlx',
    modelPath: '/models/gemma',
    modelPathFromCatalog: true,
  );

  ModelState installed(Set<String> keys) {
    var state = const ModelState();
    for (final key in keys) {
      state = state.withArtifact(
        key,
        const ArtifactStatus(phase: ArtifactPhase.installed),
      );
    }
    return state;
  }

  test('the per-chat choice wins once it is loadable', () {
    expect(
      effectiveModelKey(
        backend: real,
        catalog: modelCatalog,
        modelKey: 'qwen35-mlx',
        residentModelKey: 'gemma4-mlx',
        loadableKeys: {'gemma4-mlx', 'qwen35-mlx'},
      ),
      'qwen35-mlx',
      reason:
          'the choice outranks residency, which is what makes the chip flip '
          'the moment a model is picked',
    );
    expect(
      chatModelSubtitle(
        backend: real,
        catalog: modelCatalog,
        modelKey: 'qwen35-mlx',
        residentModelKey: 'gemma4-mlx',
        loadableKeys: {'gemma4-mlx', 'qwen35-mlx'},
      ),
      'Qwen 3.5 4B · on device',
    );
  });

  test('an unloadable choice never reaches a label', () {
    // The invariant the whole labelling rule rests on: a choice the engine
    // could not load must not be named, or the chip promises a model the next
    // send would refuse. Both failure modes, one assertion each.
    expect(
      effectiveModelKey(
        backend: real,
        catalog: modelCatalog,
        // Right engine, not installed.
        modelKey: 'qwen35-mlx',
        residentModelKey: 'gemma4-mlx',
        loadableKeys: {'gemma4-mlx'},
      ),
      'gemma4-mlx',
    );
    expect(
      effectiveModelKey(
        backend: real,
        catalog: modelCatalog,
        // Installed, wrong engine for this build.
        modelKey: 'qwen35-gguf',
        residentModelKey: 'gemma4-mlx',
        loadableKeys: loadableModelKeys(
          backend: real,
          catalog: modelCatalog,
          models: installed({'gemma4-mlx', 'qwen35-gguf'}),
        ),
      ),
      'gemma4-mlx',
    );
  });

  test('startup falls back from stale iOS GGUF state to verified MLX', () {
    final loadable = loadableModelKeys(
      backend: real,
      catalog: modelCatalog,
      models: installed({'gemma4-gguf', 'qwen35-mlx'}),
    );

    expect(loadable, {'qwen35-mlx'});
    expect(
      startupModelKey(
        backend: real,
        catalog: modelCatalog,
        loadableKeys: loadable,
        preferredKey: 'gemma4-gguf',
      ),
      'qwen35-mlx',
    );
    expect(
      effectiveModelKey(
        backend: real,
        catalog: modelCatalog,
        modelKey: 'gemma4-gguf',
        residentModelKey: 'gemma4-gguf',
        loadableKeys: loadable,
      ),
      'qwen35-mlx',
      reason: 'neither stored chat state nor stale residency crosses engines',
    );
  });

  test('startup has no model when only incompatible weights are installed', () {
    final loadable = loadableModelKeys(
      backend: real,
      catalog: modelCatalog,
      models: installed({'gemma4-gguf', 'qwen35-gguf'}),
    );

    expect(loadable, isEmpty);
    expect(
      startupModelKey(
        backend: real,
        catalog: modelCatalog,
        loadableKeys: loadable,
        preferredKey: 'gemma4-gguf',
      ),
      isNull,
    );
  });

  test('loadable keys are installed and of the composed engine', () {
    expect(
      loadableModelKeys(
        backend: real,
        catalog: modelCatalog,
        models: installed({'gemma4-mlx', 'qwen35-mlx', 'qwen35-gguf'}),
      ),
      {'gemma4-mlx', 'qwen35-mlx'},
    );
    // No model state at all (label-only containers) claims nothing loadable.
    expect(
      loadableModelKeys(backend: real, catalog: modelCatalog, models: null),
      isEmpty,
    );
  });

  test('an installed entry with no recognized template is not loadable', () {
    // A custom repository whose chat template matched no fingerprint resolves,
    // downloads and installs — resolveModelRuntimeConfig is what refuses it.
    // Offering it as a selection would put that refusal one send in the future,
    // which is exactly what the loadable set exists to prevent.
    const unrecognized = ModelCatalogEntry(
      key: 'custom-someones-build-0000002a',
      displayName: 'Someone Else',
      engine: ModelEngine.mlx,
      quantization: '4-bit',
      repository: 'someone/their-model',
      revision: 'c0ffee',
      files: [ModelArtifactFile(path: 'model.safetensors', bytes: 1)],
      profileKey: unresolvedProfileKey,
    );
    expect(
      loadableModelKeys(
        backend: real,
        catalog: [...modelCatalog, unrecognized],
        models: installed({'gemma4-mlx', unrecognized.key}),
      ),
      {'gemma4-mlx'},
    );
    expect(
      effectiveModelKey(
        backend: real,
        catalog: [...modelCatalog, unrecognized],
        modelKey: unrecognized.key,
        residentModelKey: 'gemma4-mlx',
        loadableKeys: loadableModelKeys(
          backend: real,
          catalog: [...modelCatalog, unrecognized],
          models: installed({'gemma4-mlx', unrecognized.key}),
        ),
      ),
      'gemma4-mlx',
      reason: 'the label falls back to residency rather than naming it',
    );
  });

  test('a real engine\'s labels follow residency without a choice', () {
    // The residency owner (#42) reports what the engine holds right now; that
    // still outranks the boot-configured artifact.
    expect(
      effectiveModelKey(
        backend: real,
        catalog: modelCatalog,
        residentModelKey: 'qwen35-mlx',
      ),
      'qwen35-mlx',
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

  test('a sideload claims no catalog key, and no capability with it', () {
    const sideload = InferenceBackendConfig(
      kind: InferenceBackendKind.llama,
      profileKey: 'gemma4',
      // The policy still derives an artifact key; a sideload must not inherit
      // it, or the header names a pinned model the engine does not hold.
      artifactKey: 'gemma4-gguf',
      modelPath: 'documents:models/my-own-build.gguf',
    );
    expect(effectiveModelKey(backend: sideload, catalog: modelCatalog), isNull);
    expect(
      chatModelSubtitle(backend: sideload, catalog: modelCatalog),
      'my-own-build.gguf · on device',
    );
    // gemma4-gguf is image-capable; the sideload must not borrow that proof.
    expect(
      chatModelSupportsImages(backend: sideload, catalog: modelCatalog),
      isFalse,
    );
  });

  test('a sideloaded label degrades to a fixed name, never a path', () {
    expect(sideloadedModelLabel('/abs/path/weights.gguf'), 'weights.gguf');
    expect(sideloadedModelLabel('documents:models/mlx-dir/'), 'mlx-dir');
    expect(sideloadedModelLabel('/'), 'Sideloaded model');
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
      'Qwen 3.5 4B · simulated',
    );
    expect(
      chatModelSubtitle(backend: fake, catalog: modelCatalog, modelKey: null),
      'Gemma 4 E2B · simulated',
    );
  });

  test('an unsupported device names no model at all', () {
    // "on device" is a claim about residency, and nothing will ever be
    // resident here; the subtitle drops the model rather than imply one.
    expect(
      chatModelSubtitle(
        backend: const InferenceBackendConfig(
          kind: InferenceBackendKind.llama,
          profileKey: 'qwen35',
          artifactKey: 'qwen35-2b-gguf',
          modelPath: 'documents:models/qwen35-2b-gguf/model.gguf',
          modelPathFromCatalog: true,
        ),
        catalog: modelCatalog,
        runsModels: false,
      ),
      'Unsupported device',
    );
    // The fake is never refused, so it keeps saying what it is.
    expect(
      chatModelSubtitle(
        backend: const InferenceBackendConfig.fake(),
        catalog: modelCatalog,
        runsModels: false,
      ),
      contains('simulated'),
    );
  });
}
