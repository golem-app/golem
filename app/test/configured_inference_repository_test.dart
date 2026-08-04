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
  }) async {}

  @override
  Future<void> unload() async {}

  @override
  Future<void> cancel() async {}

  @override
  Stream<BrokerRuntimeEvent> generate(BrokerGenerationRequest request) =>
      const Stream.empty();
}

InferenceRepository _select({required String backend, String modelPath = ''}) =>
    selectInferenceRepository(
      backend: backend,
      modelPath: modelPath,
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
}
