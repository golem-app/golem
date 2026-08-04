import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'backend.dart';
import 'errors.dart';
import 'models.dart';

typedef _NativeCallback =
    Void Function(
      Uint64 operationId,
      Int32 eventKind,
      Pointer<Uint8> bytes,
      IntPtr length,
      Pointer<Void> userData,
    );
typedef _AsyncOperationNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Uint64,
      Pointer<NativeFunction<_NativeCallback>>,
      Pointer<Void>,
    );
typedef _UnloadNative =
    Int32 Function(
      Pointer<Void>,
      Uint64,
      Pointer<NativeFunction<_NativeCallback>>,
      Pointer<Void>,
    );
typedef _EngineIntNative = Int32 Function(Pointer<Void>);
typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _StringFreeNative = Void Function(Pointer<Utf8>);

const _llamaAssetId = 'package:inferno/inferno.dart';
const _mlxAssetId = 'package:inferno/inferno_mlx.dart';

@Native<Uint32 Function()>(
  symbol: 'inferno_abi_version',
  assetId: _llamaAssetId,
)
external int _infernoAbiVersion();

@Native<Pointer<Utf8> Function()>(
  symbol: 'inferno_probe_json',
  assetId: _llamaAssetId,
)
external Pointer<Utf8> _infernoProbe();

@Native<Pointer<Void> Function(Pointer<Utf8>)>(
  symbol: 'inferno_engine_create',
  assetId: _llamaAssetId,
)
external Pointer<Void> _infernoCreate(Pointer<Utf8> engineName);

@Native<_AsyncOperationNative>(
  symbol: 'inferno_engine_load',
  assetId: _llamaAssetId,
)
external int _infernoLoad(
  Pointer<Void> engine,
  Pointer<Utf8> modelPath,
  int operationId,
  Pointer<NativeFunction<_NativeCallback>> callback,
  Pointer<Void> userData,
);

@Native<_AsyncOperationNative>(
  symbol: 'inferno_engine_generate',
  assetId: _llamaAssetId,
)
external int _infernoGenerate(
  Pointer<Void> engine,
  Pointer<Utf8> request,
  int operationId,
  Pointer<NativeFunction<_NativeCallback>> callback,
  Pointer<Void> userData,
);

@Native<_AsyncOperationNative>(
  symbol: 'inferno_engine_tokenize',
  assetId: _llamaAssetId,
)
external int _infernoTokenize(
  Pointer<Void> engine,
  Pointer<Utf8> prompt,
  int operationId,
  Pointer<NativeFunction<_NativeCallback>> callback,
  Pointer<Void> userData,
);

@Native<_EngineIntNative>(
  symbol: 'inferno_engine_cancel',
  assetId: _llamaAssetId,
)
external int _infernoCancel(Pointer<Void> engine);

@Native<_UnloadNative>(symbol: 'inferno_engine_unload', assetId: _llamaAssetId)
external int _infernoUnload(
  Pointer<Void> engine,
  int operationId,
  Pointer<NativeFunction<_NativeCallback>> callback,
  Pointer<Void> userData,
);

@Native<_DestroyNative>(
  symbol: 'inferno_engine_destroy',
  assetId: _llamaAssetId,
)
external void _infernoDestroy(Pointer<Void> engine);

@Native<_StringFreeNative>(
  symbol: 'inferno_string_free',
  assetId: _llamaAssetId,
)
external void _infernoStringFree(Pointer<Utf8> value);

@Native<Uint32 Function()>(
  symbol: 'inferno_mlx_abi_version',
  assetId: _mlxAssetId,
)
external int _infernoMlxAbiVersion();

@Native<Pointer<Utf8> Function()>(
  symbol: 'inferno_mlx_probe_json',
  assetId: _mlxAssetId,
)
external Pointer<Utf8> _infernoMlxProbe();

@Native<Pointer<Void> Function(Pointer<Utf8>)>(
  symbol: 'inferno_mlx_engine_create',
  assetId: _mlxAssetId,
)
external Pointer<Void> _infernoMlxCreate(Pointer<Utf8> engineName);

@Native<_AsyncOperationNative>(
  symbol: 'inferno_mlx_engine_load',
  assetId: _mlxAssetId,
)
external int _infernoMlxLoad(
  Pointer<Void> engine,
  Pointer<Utf8> modelPath,
  int operationId,
  Pointer<NativeFunction<_NativeCallback>> callback,
  Pointer<Void> userData,
);

@Native<_AsyncOperationNative>(
  symbol: 'inferno_mlx_engine_generate',
  assetId: _mlxAssetId,
)
external int _infernoMlxGenerate(
  Pointer<Void> engine,
  Pointer<Utf8> request,
  int operationId,
  Pointer<NativeFunction<_NativeCallback>> callback,
  Pointer<Void> userData,
);

@Native<_AsyncOperationNative>(
  symbol: 'inferno_mlx_engine_tokenize',
  assetId: _mlxAssetId,
)
external int _infernoMlxTokenize(
  Pointer<Void> engine,
  Pointer<Utf8> prompt,
  int operationId,
  Pointer<NativeFunction<_NativeCallback>> callback,
  Pointer<Void> userData,
);

@Native<_EngineIntNative>(
  symbol: 'inferno_mlx_engine_cancel',
  assetId: _mlxAssetId,
)
external int _infernoMlxCancel(Pointer<Void> engine);

@Native<_UnloadNative>(
  symbol: 'inferno_mlx_engine_unload',
  assetId: _mlxAssetId,
)
external int _infernoMlxUnload(
  Pointer<Void> engine,
  int operationId,
  Pointer<NativeFunction<_NativeCallback>> callback,
  Pointer<Void> userData,
);

@Native<_DestroyNative>(
  symbol: 'inferno_mlx_engine_destroy',
  assetId: _mlxAssetId,
)
external void _infernoMlxDestroy(Pointer<Void> engine);

@Native<_StringFreeNative>(
  symbol: 'inferno_mlx_string_free',
  assetId: _mlxAssetId,
)
external void _infernoMlxStringFree(Pointer<Utf8> value);

abstract interface class _NativeApi {
  int abiVersion();
  Pointer<Utf8> probe();
  Pointer<Void> create(Pointer<Utf8> name);
  int load(
    Pointer<Void> engine,
    Pointer<Utf8> path,
    int operationId,
    Pointer<NativeFunction<_NativeCallback>> callback,
    Pointer<Void> userData,
  );
  int generate(
    Pointer<Void> engine,
    Pointer<Utf8> request,
    int operationId,
    Pointer<NativeFunction<_NativeCallback>> callback,
    Pointer<Void> userData,
  );
  int tokenize(
    Pointer<Void> engine,
    Pointer<Utf8> prompt,
    int operationId,
    Pointer<NativeFunction<_NativeCallback>> callback,
    Pointer<Void> userData,
  );
  int cancel(Pointer<Void> engine);
  int unload(
    Pointer<Void> engine,
    int operationId,
    Pointer<NativeFunction<_NativeCallback>> callback,
    Pointer<Void> userData,
  );
  void destroy(Pointer<Void> engine);
  void stringFree(Pointer<Utf8> value);
}

final class _LlamaNativeApi implements _NativeApi {
  @override
  int abiVersion() => _infernoAbiVersion();
  @override
  Pointer<Utf8> probe() => _infernoProbe();
  @override
  Pointer<Void> create(Pointer<Utf8> name) => _infernoCreate(name);
  @override
  int load(
    Pointer<Void> engine,
    Pointer<Utf8> path,
    int operationId,
    Pointer<NativeFunction<_NativeCallback>> callback,
    Pointer<Void> userData,
  ) => _infernoLoad(engine, path, operationId, callback, userData);
  @override
  int generate(
    Pointer<Void> engine,
    Pointer<Utf8> request,
    int operationId,
    Pointer<NativeFunction<_NativeCallback>> callback,
    Pointer<Void> userData,
  ) => _infernoGenerate(engine, request, operationId, callback, userData);
  @override
  int tokenize(
    Pointer<Void> engine,
    Pointer<Utf8> prompt,
    int operationId,
    Pointer<NativeFunction<_NativeCallback>> callback,
    Pointer<Void> userData,
  ) => _infernoTokenize(engine, prompt, operationId, callback, userData);
  @override
  int cancel(Pointer<Void> engine) => _infernoCancel(engine);
  @override
  int unload(
    Pointer<Void> engine,
    int operationId,
    Pointer<NativeFunction<_NativeCallback>> callback,
    Pointer<Void> userData,
  ) => _infernoUnload(engine, operationId, callback, userData);
  @override
  void destroy(Pointer<Void> engine) => _infernoDestroy(engine);
  @override
  void stringFree(Pointer<Utf8> value) => _infernoStringFree(value);
}

final class _MlxNativeApi implements _NativeApi {
  @override
  int abiVersion() => _infernoMlxAbiVersion();
  @override
  Pointer<Utf8> probe() => _infernoMlxProbe();
  @override
  Pointer<Void> create(Pointer<Utf8> name) => _infernoMlxCreate(name);
  @override
  int load(
    Pointer<Void> engine,
    Pointer<Utf8> path,
    int operationId,
    Pointer<NativeFunction<_NativeCallback>> callback,
    Pointer<Void> userData,
  ) => _infernoMlxLoad(engine, path, operationId, callback, userData);
  @override
  int generate(
    Pointer<Void> engine,
    Pointer<Utf8> request,
    int operationId,
    Pointer<NativeFunction<_NativeCallback>> callback,
    Pointer<Void> userData,
  ) => _infernoMlxGenerate(engine, request, operationId, callback, userData);
  @override
  int tokenize(
    Pointer<Void> engine,
    Pointer<Utf8> prompt,
    int operationId,
    Pointer<NativeFunction<_NativeCallback>> callback,
    Pointer<Void> userData,
  ) => _infernoMlxTokenize(engine, prompt, operationId, callback, userData);
  @override
  int cancel(Pointer<Void> engine) => _infernoMlxCancel(engine);
  @override
  int unload(
    Pointer<Void> engine,
    int operationId,
    Pointer<NativeFunction<_NativeCallback>> callback,
    Pointer<Void> userData,
  ) => _infernoMlxUnload(engine, operationId, callback, userData);
  @override
  void destroy(Pointer<Void> engine) => _infernoMlxDestroy(engine);
  @override
  void stringFree(Pointer<Utf8> value) => _infernoMlxStringFree(value);
}

sealed class _PendingOperation {
  _PendingOperation(this.api);

  /// The engine library that emits this operation's events; payload buffers
  /// must be released through the same library that allocated them.
  final _NativeApi api;
}

final class _PendingFuture extends _PendingOperation {
  _PendingFuture(super.api);

  final Completer<void> completer = Completer<void>();
}

final class _PendingTokens extends _PendingOperation {
  _PendingTokens(super.api);

  final Completer<List<int>> completer = Completer<List<int>>();
  List<int>? tokenIds;
}

final class _GenerationTextSink implements Sink<String> {
  _GenerationTextSink(this.controller);

  final StreamController<InfernoGenerationEvent> controller;

  @override
  void add(String data) => controller.add(InfernoTextDelta(data));

  @override
  void close() {}
}

final class _PendingGeneration extends _PendingOperation {
  _PendingGeneration(super.api, this.controller) {
    _textDecoder = const Utf8Decoder(allowMalformed: true)
        .startChunkedConversion(
          StringConversionSink.from(_GenerationTextSink(controller)),
        );
  }

  final StreamController<InfernoGenerationEvent> controller;
  late final ByteConversionSink _textDecoder;
  bool _textClosed = false;

  void addTextBytes(Uint8List bytes) => _textDecoder.add(bytes);

  void closeText() {
    if (_textClosed) return;
    _textClosed = true;
    _textDecoder.close();
  }
}

/// Dart FFI binding for the shared asynchronous Inferno C ABI.
final class NativeInfernoBackend implements InfernoBackend {
  NativeInfernoBackend() : _llamaApi = _LlamaNativeApi() {
    final version = _llamaApi.abiVersion();
    if (version != 1) {
      throw InfernoException(
        InfernoErrorCode.nativeUnavailable,
        'Unsupported native ABI $version (expected 1).',
      );
    }
    _callback = NativeCallable<_NativeCallback>.listener(_handleNativeEvent);
  }

  final _NativeApi _llamaApi;
  _NativeApi? _activeApi;
  late final NativeCallable<_NativeCallback> _callback;
  final Map<int, _PendingOperation> _operations = {};
  Pointer<Void> _engine = nullptr;
  int _nextOperationId = 1;

  @override
  Future<InfernoDeviceProbe> probe() async {
    final results = <InfernoEngineProbe>[];
    String? operatingSystem;
    for (final api in [
      _llamaApi,
      if (Platform.isIOS || Platform.isMacOS) _MlxNativeApi(),
    ]) {
      final decoded = _probe(api);
      operatingSystem ??= decoded.$1;
      results.addAll(decoded.$2);
    }
    return InfernoDeviceProbe(
      operatingSystem: operatingSystem ?? Platform.operatingSystem,
      engines: results,
    );
  }

  (String, List<InfernoEngineProbe>) _probe(_NativeApi api) {
    final pointer = api.probe();
    if (pointer == nullptr) {
      throw const InfernoException(
        InfernoErrorCode.nativeUnavailable,
        'The native probe returned no result.',
      );
    }
    try {
      final json = jsonDecode(pointer.toDartString()) as Map<String, Object?>;
      final engines = (json['engines']! as List<Object?>).map((item) {
        final value = item! as Map<String, Object?>;
        return InfernoEngineProbe(
          engine: _engineKind(value['name']! as String),
          available: value['available']! as bool,
          detail: value['detail'] as String?,
        );
      });
      return (json['operatingSystem']! as String, engines.toList());
    } finally {
      api.stringFree(pointer);
    }
  }

  @override
  Future<void> load({
    required InfernoEngineKind engine,
    required String modelPath,
  }) async {
    if (_engine != nullptr) {
      throw const InfernoException(
        InfernoErrorCode.invalidState,
        'A native engine already exists.',
      );
    }
    final name = switch (engine) {
      InfernoEngineKind.llamaCpp => 'llama_cpp',
      InfernoEngineKind.mlx => 'mlx',
      InfernoEngineKind.mock => throw const InfernoException(
        InfernoErrorCode.nativeUnavailable,
        'The mock engine is not a native runtime.',
      ),
    };
    final api = switch (engine) {
      InfernoEngineKind.llamaCpp => _llamaApi,
      InfernoEngineKind.mlx => _MlxNativeApi(),
      InfernoEngineKind.mock => throw const InfernoException(
        InfernoErrorCode.nativeUnavailable,
        'The mock engine is not a native runtime.',
      ),
    };
    final version = api.abiVersion();
    if (version != 1) {
      throw InfernoException(
        InfernoErrorCode.nativeUnavailable,
        'Unsupported $name native ABI $version (expected 1).',
      );
    }
    _activeApi = api;
    final nativeName = name.toNativeUtf8();
    try {
      _engine = api.create(nativeName);
    } finally {
      malloc.free(nativeName);
    }
    if (_engine == nullptr) {
      _activeApi = null;
      throw InfernoException(
        InfernoErrorCode.nativeUnavailable,
        'The $name engine is not available in this native artifact.',
      );
    }

    final path = modelPath.toNativeUtf8();
    try {
      await _startFuture(
        api,
        (operationId) => api.load(
          _engine,
          path,
          operationId,
          _callback.nativeFunction,
          nullptr,
        ),
      );
    } catch (_) {
      api.destroy(_engine);
      _engine = nullptr;
      _activeApi = null;
      rethrow;
    } finally {
      malloc.free(path);
    }
  }

  @override
  Stream<InfernoGenerationEvent> generate(InfernoGenerationRequest request) {
    if (_engine == nullptr) {
      throw const InfernoException(
        InfernoErrorCode.invalidState,
        'No native model is loaded.',
      );
    }
    final api = _activeApi!;
    late StreamController<InfernoGenerationEvent> controller;
    controller = StreamController<InfernoGenerationEvent>(
      sync: true,
      onListen: () {
        final operationId = _nextOperationId++;
        _operations[operationId] = _PendingGeneration(api, controller);
        final encoded = jsonEncode({
          'prompt': request.prompt,
          'maxTokens': request.sampling.maxTokens,
          'temperature': request.sampling.temperature,
          'topP': request.sampling.topP,
          'seed': request.sampling.seed,
          'stopSequences': request.sampling.stopSequences,
          'stopTokenIds': request.sampling.stopTokenIds,
        }).toNativeUtf8();
        final result = api.generate(
          _engine,
          encoded,
          operationId,
          _callback.nativeFunction,
          nullptr,
        );
        malloc.free(encoded);
        if (result != 0) {
          _operations.remove(operationId);
          controller.addError(_startError('generation', result));
          unawaited(controller.close());
        }
      },
      onCancel: cancel,
    );
    return controller.stream;
  }

  @override
  Future<void> cancel() async {
    if (_engine == nullptr) return;
    final result = _activeApi!.cancel(_engine);
    if (result != 0) throw _startError('cancel', result);
  }

  @override
  Future<void> unload() async {
    if (_engine == nullptr) return;
    final api = _activeApi!;
    try {
      await _startFuture(
        api,
        (operationId) =>
            api.unload(_engine, operationId, _callback.nativeFunction, nullptr),
      );
    } finally {
      api.destroy(_engine);
      _engine = nullptr;
      _activeApi = null;
    }
  }

  @override
  void dispose() {
    if (_engine != nullptr) {
      _activeApi?.destroy(_engine);
      _engine = nullptr;
      _activeApi = null;
    }
    _callback.close();
  }

  /// Test/tooling-only access for asserting raw cross-engine token parity.
  Future<List<int>> tokenizeForTesting(String renderedPrompt) {
    if (_engine == nullptr) {
      throw const InfernoException(
        InfernoErrorCode.invalidState,
        'No native model is loaded.',
      );
    }
    final api = _activeApi!;
    final prompt = renderedPrompt.toNativeUtf8();
    final operationId = _nextOperationId++;
    final operation = _PendingTokens(api);
    _operations[operationId] = operation;
    final result = api.tokenize(
      _engine,
      prompt,
      operationId,
      _callback.nativeFunction,
      nullptr,
    );
    malloc.free(prompt);
    if (result != 0) {
      _operations.remove(operationId);
      operation.completer.completeError(_startError('tokenization', result));
    }
    return operation.completer.future;
  }

  Future<void> _startFuture(
    _NativeApi api,
    int Function(int operationId) start,
  ) {
    final operationId = _nextOperationId++;
    final operation = _PendingFuture(api);
    _operations[operationId] = operation;
    final result = start(operationId);
    if (result != 0) {
      _operations.remove(operationId);
      operation.completer.completeError(_startError('operation', result));
    }
    return operation.completer.future;
  }

  void _handleNativeEvent(
    int operationId,
    int eventKind,
    Pointer<Uint8> bytes,
    int length,
    Pointer<Void> userData,
  ) {
    final copiedBytes = length == 0
        ? Uint8List(0)
        : Uint8List.fromList(bytes.asTypedList(length));
    final operation = _operations[operationId];
    if (bytes != nullptr) {
      // Events can still be queued on the listener port after unload() nulls
      // _activeApi; free through the operation's own engine library. Both
      // shims allocate with the platform malloc, so the llama fallback frees
      // correctly even for an already-forgotten operation.
      final api = operation?.api ?? _activeApi ?? _llamaApi;
      api.stringFree(bytes.cast<Utf8>());
    }
    if (operation == null) return;
    if (eventKind == 1 && operation is _PendingGeneration) {
      operation.addTextBytes(copiedBytes);
      return;
    }
    final payload = copiedBytes.isEmpty ? '' : utf8.decode(copiedBytes);
    switch (eventKind) {
      case 2:
        if (operation is _PendingGeneration) {
          final json = jsonDecode(payload) as Map<String, Object?>;
          operation.controller.add(
            InfernoMetricsEvent(
              InfernoMetrics(
                decodeTokensPerSecond: (json['decodeTokensPerSecond']! as num)
                    .toDouble(),
                promptTokensPerSecond: (json['promptTokensPerSecond']! as num)
                    .toDouble(),
                generatedTokenCount: (json['generatedTokenCount']! as num)
                    .toInt(),
                elapsedSeconds: (json['elapsedSeconds']! as num).toDouble(),
                promptTokenCount: (json['promptTokenCount'] as num?)?.toInt(),
                timeToFirstTokenSeconds:
                    (json['timeToFirstTokenSeconds'] as num?)?.toDouble(),
                peakPhysicalFootprintBytes:
                    (json['peakPhysicalFootprintBytes'] as num?)?.toInt(),
              ),
            ),
          );
        }
      case 3:
        if (operation is _PendingGeneration) {
          operation.closeText();
          operation.controller.add(
            InfernoGenerationCompleted(_stopReason(payload)),
          );
        }
      case 4:
        final failure = _decodeError(payload);
        _operations.remove(operationId);
        switch (operation) {
          case _PendingFuture():
            operation.completer.completeError(failure);
          case _PendingTokens():
            operation.completer.completeError(failure);
          case _PendingGeneration():
            operation.closeText();
            operation.controller.addError(failure);
            unawaited(operation.controller.close());
        }
      case 5:
        _operations.remove(operationId);
        switch (operation) {
          case _PendingFuture():
            operation.completer.complete();
          case _PendingTokens():
            final tokenIds = operation.tokenIds;
            if (tokenIds == null) {
              operation.completer.completeError(
                const InfernoException(
                  InfernoErrorCode.internal,
                  'Native tokenization completed without token IDs.',
                ),
              );
            } else {
              operation.completer.complete(tokenIds);
            }
          case _PendingGeneration():
            operation.closeText();
            unawaited(operation.controller.close());
        }
      case 6:
        if (operation is _PendingTokens) {
          operation.tokenIds = (jsonDecode(payload) as List<Object?>)
              .cast<num>()
              .map((value) => value.toInt())
              .toList(growable: false);
        }
      default:
        final failure = InfernoException(
          InfernoErrorCode.internal,
          'Unknown native event kind $eventKind.',
        );
        _operations.remove(operationId);
        switch (operation) {
          case _PendingFuture():
            operation.completer.completeError(failure);
          case _PendingTokens():
            operation.completer.completeError(failure);
          case _PendingGeneration():
            operation.closeText();
            operation.controller.addError(failure);
            unawaited(operation.controller.close());
        }
    }
  }

  static InfernoException _decodeError(String payload) {
    try {
      final json = jsonDecode(payload) as Map<String, Object?>;
      final nativeCode = json['code']! as String;
      return InfernoException(switch (nativeCode) {
        'invalid_model_path' => InfernoErrorCode.invalidModelPath,
        'incompatible_model' => InfernoErrorCode.incompatibleModel,
        'corrupt_model' => InfernoErrorCode.corruptModel,
        'load_failed' => InfernoErrorCode.loadFailed,
        'generation_failed' => InfernoErrorCode.generationFailed,
        'cancelled' => InfernoErrorCode.cancelled,
        _ => InfernoErrorCode.internal,
      }, json['message']! as String);
    } on FormatException {
      return InfernoException(InfernoErrorCode.internal, payload);
    }
  }

  static InfernoException _startError(String operation, int code) =>
      InfernoException(
        InfernoErrorCode.invalidState,
        'Native $operation was rejected with status $code.',
      );

  static InfernoEngineKind _engineKind(String name) => switch (name) {
    'llama_cpp' => InfernoEngineKind.llamaCpp,
    'mlx' => InfernoEngineKind.mlx,
    _ => InfernoEngineKind.mock,
  };

  static InfernoStopReason _stopReason(String value) => switch (value) {
    'end_of_sequence' => InfernoStopReason.endOfSequence,
    'stop_sequence' => InfernoStopReason.stopSequence,
    'stop_token' => InfernoStopReason.stopToken,
    'cancelled' => InfernoStopReason.cancelled,
    _ => InfernoStopReason.maxTokens,
  };
}
