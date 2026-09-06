import 'dart:async';
import 'dart:io';

import 'backend.dart';
import 'errors.dart';
import 'models.dart';
import 'native_backend.dart';

enum _RuntimeState { unloaded, loading, loaded, generating, unloading }

/// Enforces Inferno's single-model, single-generation lifecycle.
final class Inferno {
  Inferno.withBackend(this._backend);

  factory Inferno.native() => Inferno.withBackend(NativeInfernoBackend());

  final InfernoBackend _backend;
  _RuntimeState _state = _RuntimeState.unloaded;
  StreamSubscription<InfernoGenerationEvent>? _nativeSubscription;
  Completer<void>? _generationDone;

  Future<InfernoDeviceProbe> probe() => _backend.probe();

  /// What this device can run, answered without constructing a runtime — the
  /// question a caller asks *before* deciding whether to fetch weights at all.
  /// An engine reports unavailable where its compiled kernels cannot execute,
  /// so this is the same verdict the first load would reach, minus the
  /// gigabytes.
  /// [engine] narrows the question to one engine, so answering it costs only
  /// that engine's library.
  static Future<InfernoDeviceProbe> probeDevice({InfernoEngineKind? engine}) =>
      NativeInfernoBackend.probeDevice(engine: engine);

  /// [onProgress] receives the engine's load fraction when
  /// [InfernoLoadOptions.reportProgress] asked for it; an engine that cannot
  /// report one (MLX) never calls it.
  Future<void> load({
    required InfernoEngineKind engine,
    required String modelPath,
    InfernoLoadOptions options = const InfernoLoadOptions(),
    InfernoLoadProgress? onProgress,
  }) async {
    if (_state != _RuntimeState.unloaded) {
      throw InfernoException(
        InfernoErrorCode.invalidState,
        'load requires an unloaded runtime (currently ${_state.name}).',
      );
    }
    await _validateModelPath(engine, modelPath);
    _state = _RuntimeState.loading;
    try {
      await _backend.load(
        engine: engine,
        modelPath: modelPath,
        options: options,
        onProgress: onProgress,
      );
      _state = _RuntimeState.loaded;
    } catch (error) {
      _state = _RuntimeState.unloaded;
      if (error is InfernoException) rethrow;
      throw InfernoException(
        InfernoErrorCode.loadFailed,
        'The model could not be loaded.',
        cause: error,
      );
    }
  }

  Future<void> unload() async {
    if (_state == _RuntimeState.unloaded) return;
    if (_state == _RuntimeState.loading || _state == _RuntimeState.unloading) {
      throw InfernoException(
        InfernoErrorCode.invalidState,
        'unload is not valid while the runtime is ${_state.name}.',
      );
    }
    if (_state == _RuntimeState.generating) {
      await cancel();
      await _generationDone?.future;
    }
    _state = _RuntimeState.unloading;
    try {
      await _backend.unload();
    } finally {
      _state = _RuntimeState.unloaded;
    }
  }

  Stream<InfernoGenerationEvent> generate(InfernoGenerationRequest request) {
    if (_state != _RuntimeState.loaded) {
      throw InfernoException(
        InfernoErrorCode.invalidState,
        'generate requires a loaded runtime (currently ${_state.name}).',
      );
    }
    if (request.prompt.isEmpty) {
      throw const InfernoException(
        InfernoErrorCode.generationFailed,
        'The rendered prompt must not be empty.',
      );
    }

    late StreamController<InfernoGenerationEvent> controller;
    var completed = false;
    var started = false;
    StreamSubscription<InfernoGenerationEvent>? subscription;
    final done = Completer<void>();

    void finish() {
      if (completed) return;
      completed = true;
      if (identical(_nativeSubscription, subscription)) {
        _nativeSubscription = null;
      }
      if (identical(_generationDone, done)) _generationDone = null;
      if (_state == _RuntimeState.generating) _state = _RuntimeState.loaded;
      if (!done.isCompleted) done.complete();
      if (!controller.isClosed) unawaited(controller.close());
    }

    controller = StreamController<InfernoGenerationEvent>(
      sync: true,
      onListen: () {
        // The stream is lazy, so the lifecycle can move on between the
        // generate() call and the first listener; re-validate here before
        // touching the engine.
        if (_state != _RuntimeState.loaded) {
          completed = true;
          controller.addError(
            InfernoException(
              InfernoErrorCode.invalidState,
              'generate requires a loaded runtime (currently ${_state.name}).',
            ),
          );
          unawaited(controller.close());
          return;
        }
        started = true;
        _state = _RuntimeState.generating;
        _generationDone = done;
        subscription = _backend
            .generate(request)
            .listen(
              controller.add,
              onError: (Object error, StackTrace stackTrace) {
                controller.addError(
                  error is InfernoException
                      ? error
                      : InfernoException(
                          InfernoErrorCode.generationFailed,
                          'Generation failed.',
                          cause: error,
                        ),
                  stackTrace,
                );
              },
              onDone: finish,
            );
        _nativeSubscription = subscription;
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        if (!started) return;
        if (!completed) await _backend.cancel();
        await subscription?.cancel();
        finish();
      },
    );
    return controller.stream;
  }

  Future<void> cancel() async {
    if (_state != _RuntimeState.generating) return;
    await _backend.cancel();
  }

  /// Stops the engine synchronously and stays usable: a later [load] starts
  /// a fresh engine on the same listener.
  ///
  /// This is the teardown that survives process death. Android delivers
  /// `detached` without awaiting the handler — and predictive back can finish
  /// the activity without running Dart at all — so an asynchronous unload
  /// races the isolate's destruction. A worker thread that outlives the
  /// isolate aborts the process from the callback trampoline (#124);
  /// destroying the engine blocks until that thread has joined.
  void releaseEngine() {
    unawaited(_nativeSubscription?.cancel() ?? Future<void>.value());
    _nativeSubscription = null;
    _generationDone = null;
    _backend.releaseEngine();
    _state = _RuntimeState.unloaded;
  }

  /// Unloads any resident model and releases the backend's native listener
  /// so the isolate can exit. The runtime must not be used afterwards.
  Future<void> dispose() async {
    try {
      await unload();
    } finally {
      // The listener must be released even when the unload fails, or the
      // leak dispose() exists to prevent survives exactly the error path.
      _backend.dispose();
    }
  }

  static Future<void> _validateModelPath(
    InfernoEngineKind engine,
    String modelPath,
  ) async {
    if (modelPath.trim().isEmpty) {
      throw const InfernoException(
        InfernoErrorCode.invalidModelPath,
        'The model path must not be empty.',
      );
    }
    final type = await FileSystemEntity.type(modelPath, followLinks: true);
    final expected = engine == InfernoEngineKind.mlx
        ? FileSystemEntityType.directory
        : FileSystemEntityType.file;
    if (type != expected) {
      final shape = engine == InfernoEngineKind.mlx
          ? 'a directory'
          : 'a GGUF file';
      throw InfernoException(
        InfernoErrorCode.invalidModelPath,
        'The ${engine.name} model path must be $shape.',
      );
    }
  }
}
