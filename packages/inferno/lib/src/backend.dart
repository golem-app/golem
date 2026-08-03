import 'models.dart';

/// Internal engine contract shared by the native and deterministic backends.
abstract interface class InfernoBackend {
  Future<InfernoDeviceProbe> probe();

  Future<void> load({
    required InfernoEngineKind engine,
    required String modelPath,
  });

  Future<void> unload();

  Stream<InfernoGenerationEvent> generate(InfernoGenerationRequest request);

  Future<void> cancel();
}
