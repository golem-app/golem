import 'models.dart';

/// Internal engine contract shared by the native and deterministic backends.
abstract interface class InfernoBackend {
  Future<InfernoDeviceProbe> probe();

  Future<void> load({
    required InfernoEngineKind engine,
    required String modelPath,
    InfernoLoadOptions options = const InfernoLoadOptions(),
  });

  Future<void> unload();

  Stream<InfernoGenerationEvent> generate(InfernoGenerationRequest request);

  Future<void> cancel();

  /// Releases resources that outlive an unload, such as the native event
  /// listener that otherwise keeps the isolate alive. The backend must not
  /// be used afterwards.
  void dispose();
}
