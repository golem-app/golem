import 'dart:typed_data';

import 'package:inferno/inferno.dart';

import '../core/repositories/contracts.dart'
    show InferenceException, InferenceFailureKind;

/// Pinned-artifact and engine-pin metadata, re-exported so measurement code
/// outside the broker can cite pins without importing package:inferno.
export 'package:inferno/inferno.dart'
    show
        InfernoFileRole,
        InfernoModelArtifact,
        InfernoModelFile,
        gemma4E2BGgufQ4,
        gemma4E2BMlx4Bit,
        llamaCppRelease,
        llamaCppRevision,
        mlxSwiftLmVersion,
        mlxSwiftVersion,
        qwen35TwoBGgufQ4,
        qwen35TwoBMlx4Bit,
        qwen35GgufQ4,
        qwen35Mlx4Bit;

enum BrokerEngine { llamaCpp, mlx }

final class BrokerSamplingParameters {
  const BrokerSamplingParameters({
    required this.maxTokens,
    required this.temperature,
    required this.topP,
    this.topK,
    this.contextLength,
    this.presencePenalty,
    required this.seed,
    required this.stopSequences,
    required this.stopTokenIds,
  });

  final int maxTokens;
  final double temperature;
  final double topP;

  /// Null keeps top-k filtering out of the engine's sampler chain.
  final int? topK;

  /// Null falls back to the engine's own bound (llama's trained context).
  final int? contextLength;

  /// Null keeps the presence penalty out of the chain; set, it penalizes
  /// already-seen tokens over a window covering the whole generation (#80).
  /// Edge semantics stay engine-native — llama.cpp counts only sampled
  /// tokens, MLX also pre-seeds with the prompt.
  final double? presencePenalty;

  final int? seed;
  final List<String> stopSequences;
  final List<int> stopTokenIds;
}

/// One encoded image, already read from the attachment store; engines decode.
final class BrokerImageInput {
  const BrokerImageInput(this.bytes);

  final Uint8List bytes;
}

final class BrokerGenerationRequest {
  const BrokerGenerationRequest({
    required this.prompt,
    required this.sampling,
    this.images = const [],
  });

  final String prompt;
  final BrokerSamplingParameters sampling;

  final List<BrokerImageInput> images;
}

final class BrokerRuntimeMetrics {
  const BrokerRuntimeMetrics({
    required this.decodeTokensPerSecond,
    required this.promptTokensPerSecond,
    required this.generatedTokenCount,
    required this.elapsedSeconds,
    required this.timingSemanticsVersion,
    this.promptTokenCount,
    this.timeToFirstTokenSeconds,
    this.peakPhysicalFootprintBytes,
  });

  final double decodeTokensPerSecond;
  final double promptTokensPerSecond;
  final int generatedTokenCount;
  final double elapsedSeconds;

  /// The engine's own statement of the timing contract behind the numbers
  /// above (`currentTimingSemantics` in the domain). Required, never
  /// defaulted: the broker carries an engine's measurement and must not
  /// supply a contract the engine did not claim.
  final int timingSemanticsVersion;

  // Null when an engine cannot measure them; the iOS bake-off record (ADR
  // 0002, whose timings are version 1) requires all three, so the adapter
  // must not drop them.
  final int? promptTokenCount;
  final double? timeToFirstTokenSeconds;
  final int? peakPhysicalFootprintBytes;
}

sealed class BrokerRuntimeEvent {
  const BrokerRuntimeEvent();
}

final class BrokerTextDelta extends BrokerRuntimeEvent {
  const BrokerTextDelta(this.text);

  final String text;
}

final class BrokerMetricsDelta extends BrokerRuntimeEvent {
  const BrokerMetricsDelta(this.metrics);

  final BrokerRuntimeMetrics metrics;
}

enum BrokerStopReason {
  endOfSequence,
  stopSequence,
  stopToken,
  maxTokens,
  cancelled,
}

final class BrokerGenerationCompleted extends BrokerRuntimeEvent {
  const BrokerGenerationCompleted(this.reason);

  final BrokerStopReason reason;
}

/// The broker's subtype of the app-level [InferenceException], so controllers
/// catch one semantic failure type across backends. [message] is diagnostic;
/// presentation maps [kind] to localized copy and never renders it
/// (handbook v5.0 §5.2).
final class BrokerRuntimeException extends InferenceException {
  const BrokerRuntimeException(
    String message, {
    InferenceFailureKind kind = InferenceFailureKind.engine,
    super.cause,
  }) : super(kind, message);
}

/// Mirrors the Inferno load options so application code stays package-blind.
/// Every knob exists for measurement and triage, not UI.
final class BrokerLoadOptions {
  const BrokerLoadOptions({
    this.checkTensors = false,
    this.quantizedKvCache = false,
    this.threadCount,
    this.forceCpu = false,
  });

  final bool checkTensors;

  /// q8_0 KV cache on llama.cpp (forces flash attention), 8-bit quantized
  /// cache on MLX.
  final bool quantizedKvCache;

  final int? threadCount;

  /// The #13 escape hatch: keep every layer off the GPU on Metal builds.
  final bool forceCpu;
}

abstract interface class BrokerRuntime {
  Future<void> load({
    required BrokerEngine engine,
    required String modelPath,
    BrokerLoadOptions options = const BrokerLoadOptions(),
    String? projectorPath,
  });
  Future<void> unload();
  Stream<BrokerRuntimeEvent> generate(BrokerGenerationRequest request);
  Future<void> cancel();

  /// Stops the engine synchronously, blocking until its worker thread has
  /// joined, and stays usable afterwards.
  ///
  /// Synchronous because it runs on the way out: Android delivers `detached`
  /// without awaiting the handler, and under predictive back the activity can
  /// finish without running Dart at all. Anything asynchronous here races the
  /// isolate's destruction, and a worker that outlives it aborts the process
  /// from the token trampoline (#124).
  void releaseEngine();
}

/// The only adapter between Flutter application code and package:inferno.
final class InfernoRuntimeAdapter implements BrokerRuntime {
  InfernoRuntimeAdapter(this._inferno);

  factory InfernoRuntimeAdapter.native() =>
      InfernoRuntimeAdapter(Inferno.native());

  final Inferno _inferno;

  @override
  Future<void> load({
    required BrokerEngine engine,
    required String modelPath,
    BrokerLoadOptions options = const BrokerLoadOptions(),
    String? projectorPath,
  }) => _translating(
    () => _inferno.load(
      engine: switch (engine) {
        BrokerEngine.llamaCpp => InfernoEngineKind.llamaCpp,
        BrokerEngine.mlx => InfernoEngineKind.mlx,
      },
      modelPath: modelPath,
      options: InfernoLoadOptions(
        projectorPath: projectorPath,
        checkTensors: options.checkTensors,
        kvCacheType: options.quantizedKvCache
            ? InfernoKvCacheType.q8_0
            : InfernoKvCacheType.f16,
        threadCount: options.threadCount,
        gpuLayers: options.forceCpu ? 0 : null,
      ),
    ),
  );

  @override
  Future<void> unload() => _translating(_inferno.unload);

  @override
  Future<void> cancel() => _translating(_inferno.cancel);

  @override
  void releaseEngine() => _inferno.releaseEngine();

  /// [releaseEngine] plus the callback listener. Terminal, and deliberately
  /// not on [BrokerRuntime]: the app's only teardown is [releaseEngine]; this
  /// serves harnesses that build one adapter per model and must not leak
  /// listeners between them.
  Future<void> dispose() => _translating(_inferno.dispose);

  @override
  Stream<BrokerRuntimeEvent> generate(BrokerGenerationRequest request) async* {
    final events = _inferno.generate(
      InfernoGenerationRequest(
        prompt: request.prompt,
        sampling: InfernoSamplingParameters(
          maxTokens: request.sampling.maxTokens,
          temperature: request.sampling.temperature,
          topP: request.sampling.topP,
          topK: request.sampling.topK,
          contextLength: request.sampling.contextLength,
          presencePenalty: request.sampling.presencePenalty,
          seed: request.sampling.seed,
          stopSequences: request.sampling.stopSequences,
          stopTokenIds: request.sampling.stopTokenIds,
        ),
        images: [
          for (final image in request.images) InfernoImageInput(image.bytes),
        ],
      ),
    );
    try {
      await for (final event in events) {
        switch (event) {
          case InfernoTextDelta():
            yield BrokerTextDelta(event.text);
          case InfernoMetricsEvent():
            final metrics = event.metrics;
            yield BrokerMetricsDelta(
              BrokerRuntimeMetrics(
                decodeTokensPerSecond: metrics.decodeTokensPerSecond,
                promptTokensPerSecond: metrics.promptTokensPerSecond,
                generatedTokenCount: metrics.generatedTokenCount,
                elapsedSeconds: metrics.elapsedSeconds,
                timingSemanticsVersion: metrics.timingSemanticsVersion,
                promptTokenCount: metrics.promptTokenCount,
                timeToFirstTokenSeconds: metrics.timeToFirstTokenSeconds,
                peakPhysicalFootprintBytes: metrics.peakPhysicalFootprintBytes,
              ),
            );
          case InfernoGenerationCompleted():
            yield BrokerGenerationCompleted(switch (event.reason) {
              InfernoStopReason.endOfSequence => BrokerStopReason.endOfSequence,
              InfernoStopReason.stopSequence => BrokerStopReason.stopSequence,
              InfernoStopReason.stopToken => BrokerStopReason.stopToken,
              InfernoStopReason.maxTokens => BrokerStopReason.maxTokens,
              InfernoStopReason.cancelled => BrokerStopReason.cancelled,
            });
        }
      }
    } on InfernoException catch (error, stackTrace) {
      Error.throwWithStackTrace(_translated(error), stackTrace);
    }
  }

  /// The origin trace travels with the translation. A `throw` here would start
  /// the stack at this frame, which is the one frame that explains nothing —
  /// the engine call underneath it is the whole diagnostic (#130).
  static Future<T> _translating<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on InfernoException catch (error, stackTrace) {
      Error.throwWithStackTrace(_translated(error), stackTrace);
    }
  }

  static BrokerRuntimeException _translated(InfernoException error) =>
      switch (error.code) {
        InfernoErrorCode.invalidModelPath => BrokerRuntimeException(
          'The model file could not be found on this device.',
          kind: InferenceFailureKind.invalidModelArtifact,
          cause: error,
        ),
        InfernoErrorCode.corruptModel ||
        InfernoErrorCode.incompatibleModel => BrokerRuntimeException(
          'The model on this device is damaged or not compatible '
          'with this build.',
          kind: InferenceFailureKind.invalidModelArtifact,
          cause: error,
        ),
        InfernoErrorCode.loadFailed => BrokerRuntimeException(
          'The model could not be loaded.',
          cause: error,
        ),
        InfernoErrorCode.generationFailed => BrokerRuntimeException(
          'The local engine failed while generating a response.',
          cause: error,
        ),
        InfernoErrorCode.contextExhausted => BrokerRuntimeException(
          'This conversation no longer fits the model’s context '
          'window. Start a new chat to continue.',
          kind: InferenceFailureKind.contextExhausted,
          cause: error,
        ),
        InfernoErrorCode.outOfMemory => BrokerRuntimeException(
          'The model ran out of memory while responding. Close other '
          'apps and try again, or lower the context length in Settings.',
          kind: InferenceFailureKind.outOfMemory,
          cause: error,
        ),
        InfernoErrorCode.unsupportedDevice => BrokerRuntimeException(
          'This device’s processor is missing an instruction set the '
          'local engine needs, so it cannot run models here.',
          kind: InferenceFailureKind.unsupportedDevice,
          cause: error,
        ),
        InfernoErrorCode.cancelled => BrokerRuntimeException(
          'Generation was cancelled.',
          cause: error,
        ),
        InfernoErrorCode.nativeUnavailable ||
        InfernoErrorCode.invalidState ||
        InfernoErrorCode.internal => BrokerRuntimeException(
          'The local inference runtime hit an internal error.',
          cause: error,
        ),
      };
}
