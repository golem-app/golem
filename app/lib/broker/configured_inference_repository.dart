import 'package:flutter/foundation.dart';

import '../core/repositories/contracts.dart';
import '../core/repositories/fake_inference_repository.dart';
import 'inferno_inference_repository.dart';
import 'runtime.dart';

/// Selects deterministic inference by default and a real local runtime only
/// when an explicit build configuration supplies both engine and model path.
InferenceRepository createConfiguredInferenceRepository({
  required Duration fakeStreamDelay,
  required String documentsDirectory,
}) => selectInferenceRepository(
  backend: const String.fromEnvironment(
    'GOLEM_INFERENCE_BACKEND',
    defaultValue: 'fake',
  ),
  modelPath: const String.fromEnvironment('GOLEM_MODEL_PATH'),
  fakeStreamDelay: fakeStreamDelay,
  documentsDirectory: documentsDirectory,
  createRuntime: InfernoRuntimeAdapter.native,
);

/// The dart-define values arrive as compile-time constants, so the selection
/// logic takes them as parameters to stay reachable from tests.
@visibleForTesting
InferenceRepository selectInferenceRepository({
  required String backend,
  required String modelPath,
  required Duration fakeStreamDelay,
  required String documentsDirectory,
  required BrokerRuntime Function() createRuntime,
}) {
  if (backend == 'fake') {
    return FakeInferenceRepository(eventDelay: fakeStreamDelay);
  }
  // A misconfigured build must fail at launch, loudly; there is no UI state
  // that could make a typo'd dart-define recoverable at runtime.
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
    createRuntime(),
    engine: engine,
    modelPath: resolvedModelPath,
  );
}
