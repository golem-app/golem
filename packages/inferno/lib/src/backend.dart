import 'models.dart';

/// Internal engine contract shared by the native and deterministic backends.
abstract interface class InfernoBackend {
  Future<InfernoDeviceProbe> probe();

  Future<void> load({
    required InfernoEngineKind engine,
    required String modelPath,
    InfernoLoadOptions options = const InfernoLoadOptions(),
    InfernoLoadProgress? onProgress,
  });

  Future<void> unload();

  Stream<InfernoGenerationEvent> generate(InfernoGenerationRequest request);

  Future<void> cancel();

  /// Stops the engine synchronously, blocking until its worker thread has
  /// joined, and leaves the event listener open so the backend can load
  /// again.
  ///
  /// Synchronous by necessity. On Android the only teardown signal Dart
  /// receives is `detached`, which the framework neither awaits nor
  /// guarantees; anything asynchronous races the isolate's own destruction,
  /// and a worker that outlives it aborts the process from the callback
  /// trampoline (#124).
  void releaseEngine();

  /// [releaseEngine] plus the event listener, which otherwise keeps the
  /// isolate alive. The backend must not be used afterwards.
  void dispose();
}
