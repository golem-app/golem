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

  Future<void> load({
    required InfernoEngineKind engine,
    required String modelPath,
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
      await _backend.load(engine: engine, modelPath: modelPath);
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
    final done = Completer<void>();
    _generationDone = done;

    void finish() {
      if (completed) return;
      completed = true;
      _nativeSubscription = null;
      _generationDone = null;
      if (_state == _RuntimeState.generating) _state = _RuntimeState.loaded;
      if (!done.isCompleted) done.complete();
      if (!controller.isClosed) unawaited(controller.close());
    }

    controller = StreamController<InfernoGenerationEvent>(
      sync: true,
      onListen: () {
        _state = _RuntimeState.generating;
        _nativeSubscription = _backend
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
      },
      onPause: () => _nativeSubscription?.pause(),
      onResume: () => _nativeSubscription?.resume(),
      onCancel: () async {
        if (!completed) await _backend.cancel();
        await _nativeSubscription?.cancel();
        finish();
      },
    );
    return controller.stream;
  }

  Future<void> cancel() async {
    if (_state != _RuntimeState.generating) return;
    await _backend.cancel();
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
