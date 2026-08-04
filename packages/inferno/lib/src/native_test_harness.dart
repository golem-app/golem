import 'models.dart';
import 'native_backend.dart';

/// Native tokenization access kept outside Inferno's production API.
final class NativeInfernoTestHarness {
  NativeInfernoTestHarness() : _backend = NativeInfernoBackend();

  final NativeInfernoBackend _backend;

  Future<void> load({
    required InfernoEngineKind engine,
    required String modelPath,
  }) => _backend.load(engine: engine, modelPath: modelPath);

  Future<List<int>> tokenize(String renderedPrompt) =>
      _backend.tokenizeForTesting(renderedPrompt);

  Future<void> unload() => _backend.unload();
}
