import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/configured_inference_repository.dart';
import 'package:golem_flutter/broker/inferno_inference_repository.dart';
import 'package:golem_flutter/broker/runtime.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';

final class _StubRuntime implements BrokerRuntime {
  String? loadedModelPath;
  String? loadedProjectorPath;

  @override
  Future<void> load({
    required BrokerEngine engine,
    required String modelPath,
    BrokerLoadOptions options = const BrokerLoadOptions(),
    String? projectorPath,
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
  int samplingSeed = 0,
  String? initialCatalogKey,
  String? initialProjectorPath,
  _StubRuntime? runtime,
}) => selectInferenceRepository(
  backend: backend,
  modelPath: modelPath,
  modelProfile: modelProfile,
  initialCatalogKey: initialCatalogKey,
  initialProjectorPath: initialProjectorPath,
  samplingSeed: samplingSeed,
  fakeStreamDelay: Duration.zero,
  documentsDirectory: '/documents',
  createRuntime: () => runtime ?? _StubRuntime(),
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

    expect(repository.residentModelKey.value, 'gemma4-gguf');
    expect(runtime.loadedModelPath, '/documents/models/gemma4-gguf/model.gguf');
    expect(
      runtime.loadedProjectorPath,
      '/documents/models/gemma4-gguf/projector.gguf',
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
