import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/configured_inference_repository.dart';
import 'package:golem_flutter/broker/inferno_inference_repository.dart';
import 'package:golem_flutter/broker/runtime.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';

final class _StubRuntime implements BrokerRuntime {
  @override
  Future<void> load({
    required BrokerEngine engine,
    required String modelPath,
    BrokerLoadOptions options = const BrokerLoadOptions(),
  }) async {}

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
}) => selectInferenceRepository(
  backend: backend,
  modelPath: modelPath,
  modelProfile: modelProfile,
  samplingSeed: samplingSeed,
  fakeStreamDelay: Duration.zero,
  documentsDirectory: '/documents',
  createRuntime: _StubRuntime.new,
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
