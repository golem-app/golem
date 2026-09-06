import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/configured_inference_repository.dart';
import 'package:golem_flutter/broker/inferno_inference_repository.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/broker/runtime.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';

final class _StubRuntime implements BrokerRuntime {
  String? loadedModelPath;
  String? loadedProjectorPath;

  @override
  void releaseEngine() {}

  @override
  Future<void> load({
    required BrokerEngine engine,
    required String modelPath,
    BrokerLoadOptions options = const BrokerLoadOptions(),
    String? projectorPath,
    BrokerLoadProgress? onProgress,
  }) async {
    loadedModelPath = modelPath;
    loadedProjectorPath = projectorPath;
  }

  @override
  Future<void> unload() async {}

  @override
  Future<void> cancel() async {}

  @override
  Stream<BrokerRuntimeEvent> generate(BrokerGenerationRequest request) =>
      const Stream.empty();
}

InferenceRepository _select({
  required String backend,
  String modelPath = '',
  String modelProfile = 'gemma4',
  int? samplingSeed,
  String? initialCatalogKey,
  String? initialProjectorPath,
  bool sideloaded = false,
  List<ModelCatalogEntry> Function()? activationCatalog,
  _StubRuntime? runtime,
  AppIdentity identity = AppIdentity.qa,
  InferenceDiagnosticSink? diagnosticSink,
}) => selectInferenceRepository(
  identity: identity,
  backend: backend,
  modelPath: modelPath,
  modelProfile: modelProfile,
  initialCatalogKey: initialCatalogKey,
  initialProjectorPath: initialProjectorPath,
  sideloaded: sideloaded,
  activationCatalog: activationCatalog,
  samplingSeed: samplingSeed,
  fakeStreamDelay: Duration.zero,
  documentsDirectory: '/documents',
  createRuntime: () => runtime ?? _StubRuntime(),
  diagnosticSink: diagnosticSink,
);

void main() {
  test('the fake backend stays the default', () {
    expect(_select(backend: 'fake'), isA<FakeInferenceRepository>());
  });

  test('llama and mlx select the Inferno repository', () {
    for (final backend in ['llama', 'mlx']) {
      expect(
        _select(backend: backend, modelPath: '/models/m'),
        isA<InfernoInferenceRepository>(),
        reason: backend,
      );
    }
  });

  test('production suppresses an explicitly supplied diagnostic sink', () {
    final sink = <String>[].add;
    final production =
        _select(
              backend: 'llama',
              modelPath: '/models/m',
              identity: AppIdentity.production,
              diagnosticSink: sink,
            )
            as InfernoInferenceRepository;
    final qa =
        _select(backend: 'llama', modelPath: '/models/m', diagnosticSink: sink)
            as InfernoInferenceRepository;

    expect(production.diagnosticSink, isNull);
    expect(qa.diagnosticSink, same(sink));
  });

  test('the documents prefix resolves against the documents directory', () {
    final repository =
        _select(backend: 'llama', modelPath: 'documents:models/m.gguf')
            as InfernoInferenceRepository;
    expect(repository.modelPath, '/documents/models/m.gguf');
  });

  test('the resolved startup artifact and projector stay together', () async {
    final runtime = _StubRuntime();
    final repository =
        _select(
              backend: 'llama',
              modelPath: 'documents:models/gemma4-gguf/model.gguf',
              initialCatalogKey: 'gemma4-gguf',
              initialProjectorPath:
                  'documents:models/gemma4-gguf/projector.gguf',
              runtime: runtime,
            )
            as InfernoInferenceRepository;

    await repository.prepare();

    expect(repository.residency.value.catalogKey, 'gemma4-gguf');
    expect(runtime.loadedModelPath, '/documents/models/gemma4-gguf/model.gguf');
    expect(
      runtime.loadedProjectorPath,
      '/documents/models/gemma4-gguf/projector.gguf',
    );
  });

  test('a sideloaded configuration claims no catalog key', () async {
    final runtime = _StubRuntime();
    final repository =
        _select(
              backend: 'llama',
              modelPath: '/operator/my-own-build.gguf',
              // The policy derives one anyway; a sideload must not adopt it.
              initialCatalogKey: 'gemma4-gguf',
              sideloaded: true,
              runtime: runtime,
            )
            as InfernoInferenceRepository;

    await repository.prepare();

    expect(
      repository.residency.value.catalogKey,
      isNull,
      reason:
          'reporting a pinned key here is what made the chat header name the '
          'wrong model',
    );
    expect(runtime.loadedModelPath, '/operator/my-own-build.gguf');
  });

  test('activation resolves against the catalog it is given', () async {
    // The #52 gap: a resolved custom repository downloads and verifies, then
    // could not be loaded because activation only ever saw the pinned list.
    final custom = ModelCatalogEntry(
      key: 'custom-example-repo',
      displayName: 'Example Repo',
      engine: ModelEngine.gguf,
      quantization: 'Q4_K_M',
      repository: 'example/repo',
      revision: 'a' * 40,
      profileKey: 'qwen35',
      files: const [
        ModelArtifactFile(
          path: 'model.gguf',
          bytes: 12,
          sha256: null,
          role: ModelFileRole.weights,
        ),
      ],
    );
    final runtime = _StubRuntime();
    final repository =
        _select(
              backend: 'llama',
              modelPath: 'documents:models/gemma4-gguf/model.gguf',
              initialCatalogKey: 'gemma4-gguf',
              activationCatalog: () => [...modelCatalog, custom],
              runtime: runtime,
            )
            as InfernoInferenceRepository;

    await repository.prepare(modelKey: custom.key);

    expect(repository.residency.value.catalogKey, custom.key);
    expect(
      runtime.loadedModelPath,
      '/documents/${custom.installDirectory}/model.gguf',
    );
  });

  test('sampling stays engine-seeded unless a probe seed is configured', () {
    final unseeded =
        _select(backend: 'llama', modelPath: '/models/m')
            as InfernoInferenceRepository;
    expect(unseeded.seed, isNull);

    // The dart-define arrives as an int with 0 as its unset sentinel.
    final seeded =
        _select(backend: 'mlx', modelPath: '/models/m', samplingSeed: 7)
            as InfernoInferenceRepository;
    expect(seeded.seed, 7);
  });

  test('a real backend without a model path fails at construction', () {
    expect(
      () => _select(backend: 'llama'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('GOLEM_MODEL_PATH'),
        ),
      ),
    );
  });

  test('an unknown backend name fails at construction', () {
    expect(
      () => _select(backend: 'llamma', modelPath: '/models/m'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('must be fake, llama, or mlx'),
        ),
      ),
    );
  });

  test('the default profile is gemma4 and unknown profiles fail loudly', () {
    final repository =
        _select(backend: 'llama', modelPath: '/models/m')
            as InfernoInferenceRepository;
    expect(repository.profile.key, 'gemma4');
    expect(
      () => _select(
        backend: 'llama',
        modelPath: '/models/m',
        modelProfile: 'gemma5',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('GOLEM_MODEL_PROFILE'),
        ),
      ),
    );
  });
}
