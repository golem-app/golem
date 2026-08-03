import '../core/repositories/contracts.dart';
import '../core/repositories/fake_inference_repository.dart';
import 'inferno_inference_repository.dart';
import 'runtime.dart';

/// Selects deterministic inference by default and a real local runtime only
/// when an explicit build configuration supplies both engine and model path.
InferenceRepository createConfiguredInferenceRepository({
  required Duration fakeStreamDelay,
  required String documentsDirectory,
}) {
  const backend = String.fromEnvironment(
    'GOLEM_INFERENCE_BACKEND',
    defaultValue: 'fake',
  );
  if (backend == 'fake') {
    return FakeInferenceRepository(eventDelay: fakeStreamDelay);
  }
  const modelPath = String.fromEnvironment('GOLEM_MODEL_PATH');
  if (modelPath.isEmpty) {
    throw StateError(
      'GOLEM_MODEL_PATH is required for the $backend inference backend.',
    );
  }
  final resolvedModelPath = modelPath.startsWith('documents:')
      ? '$documentsDirectory/${modelPath.substring('documents:'.length)}'
      : modelPath;
  final engine = switch (backend) {
    'llama' => BrokerEngine.llamaCpp,
    'mlx' => BrokerEngine.mlx,
    _ => throw StateError(
      'GOLEM_INFERENCE_BACKEND must be fake, llama, or mlx.',
    ),
  };
  return InfernoInferenceRepository(
    InfernoRuntimeAdapter.native(),
    engine: engine,
    modelPath: resolvedModelPath,
  );
}
