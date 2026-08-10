import 'dart:typed_data';

import 'package:inferno/inferno.dart';

import '../core/repositories/contracts.dart'
    show InferenceException, InferenceFailureKind;

/// Pinned-artifact and engine-pin metadata, re-exported so evaluation and
/// measurement code outside the broker can cite pins in evidence reports
/// without importing package:inferno across the boundary.
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
    required this.seed,
    required this.stopSequences,
    required this.stopTokenIds,
  });

  final int maxTokens;
  final double temperature;
  final double topP;

  /// Null keeps top-k filtering out of the engine's sampler chain.
  final int? topK;

  /// Token budget over prompt plus generation, enforced by the engines;
  /// null falls back to the engine's own bound (llama's trained context).
  final int? contextLength;

  final int? seed;
  final List<String> stopSequences;
  final List<int> stopTokenIds;
}

/// One encoded image for a generation, already read from the attachment
/// store. Engines decode the bytes themselves.
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

  /// Ordered images; the rendered [prompt] carries one media marker each.
  final List<BrokerImageInput> images;
}

final class BrokerRuntimeMetrics {
  const BrokerRuntimeMetrics({
    required this.decodeTokensPerSecond,
    required this.promptTokensPerSecond,
    required this.generatedTokenCount,
    required this.elapsedSeconds,
    this.promptTokenCount,
    this.timeToFirstTokenSeconds,
    this.peakPhysicalFootprintBytes,
  });

  final double decodeTokensPerSecond;
  final double promptTokensPerSecond;
  final int generatedTokenCount;
  final double elapsedSeconds;

  // Null when an engine cannot measure them; the iOS bake-off record
  // requires all three, so the adapter must not drop them.
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

/// A runtime failure with user-presentable text; `toString` is the message
/// so the recovery banner never shows a package exception verbatim. The
/// broker's subtype of the app-level [InferenceException] so controllers
/// catch one type across fake and real backends (§19.2).
final class BrokerRuntimeException extends InferenceException {
  const BrokerRuntimeException(
    String message, {
    InferenceFailureKind kind = InferenceFailureKind.engine,
    super.cause,
  }) : super(kind, message);
}

/// Load-time engine configuration, mirrored from the Inferno options so
/// application code stays package-blind. Defaults are the engine
/// defaults; every knob exists for measurement and triage, not UI.
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
  /// [projectorPath] is the multimodal projector pinned with these weights,
  /// or null for a text-only artifact.
  Future<void> load({
    required BrokerEngine engine,
    required String modelPath,
    BrokerLoadOptions options = const BrokerLoadOptions(),
    String? projectorPath,
  });
  Future<void> unload();
  Stream<BrokerRuntimeEvent> generate(BrokerGenerationRequest request);
  Future<void> cancel();
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

  /// Closes the underlying runtime, including its native-callback listener.
  /// The app keeps one adapter alive for its whole lifetime and never calls
  /// this; harness code that cycles engines in one process must, or the
  /// listener keeps the isolate alive after the run.
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
    } on InfernoException catch (error) {
      throw _translated(error);
    }
  }

  static Future<T> _translating<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on InfernoException catch (error) {
      throw _translated(error);
    }
  }

  static BrokerRuntimeException _translated(InfernoException error) =>
      switch (error.code) {
        InfernoErrorCode.invalidModelPath => BrokerRuntimeException(
          'The model file could not be found on this device.',
          cause: error,
        ),
        InfernoErrorCode.corruptModel ||
        InfernoErrorCode.incompatibleModel => BrokerRuntimeException(
          'The model on this device is damaged or not compatible '
          'with this build.',
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
