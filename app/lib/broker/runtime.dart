import 'package:inferno/inferno.dart';

/// Pinned-artifact and engine-pin metadata, re-exported so evaluation and
/// measurement code outside the broker can cite pins in evidence reports
/// without importing package:inferno across the boundary.
export 'package:inferno/inferno.dart'
    show
        InfernoModelArtifact,
        InfernoModelFile,
        gemma4E2BGgufQ4,
        gemma4E2BMlx4Bit,
        llamaCppRelease,
        llamaCppRevision,
        mlxSwiftLmVersion,
        mlxSwiftVersion,
        qwen35GgufQ4,
        qwen35Mlx4Bit;

enum BrokerEngine { llamaCpp, mlx }

final class BrokerSamplingParameters {
  const BrokerSamplingParameters({
    required this.maxTokens,
    required this.temperature,
    required this.topP,
    required this.seed,
    required this.stopSequences,
    required this.stopTokenIds,
  });

  final int maxTokens;
  final double temperature;
  final double topP;
  final int? seed;
  final List<String> stopSequences;
  final List<int> stopTokenIds;
}

final class BrokerGenerationRequest {
  const BrokerGenerationRequest({required this.prompt, required this.sampling});

  final String prompt;
  final BrokerSamplingParameters sampling;
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
/// so the recovery banner never shows a package exception verbatim.
final class BrokerRuntimeException implements Exception {
  const BrokerRuntimeException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract interface class BrokerRuntime {
  Future<void> load({required BrokerEngine engine, required String modelPath});
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
  }) => _translating(
    () => _inferno.load(
      engine: switch (engine) {
        BrokerEngine.llamaCpp => InfernoEngineKind.llamaCpp,
        BrokerEngine.mlx => InfernoEngineKind.mlx,
      },
      modelPath: modelPath,
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
          seed: request.sampling.seed,
          stopSequences: request.sampling.stopSequences,
          stopTokenIds: request.sampling.stopTokenIds,
        ),
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
      BrokerRuntimeException(switch (error.code) {
        InfernoErrorCode.invalidModelPath =>
          'The model file could not be found on this device.',
        InfernoErrorCode.corruptModel || InfernoErrorCode.incompatibleModel =>
          'The model on this device is damaged or not compatible '
              'with this build.',
        InfernoErrorCode.loadFailed => 'The model could not be loaded.',
        InfernoErrorCode.generationFailed =>
          'The local engine failed while generating a response.',
        InfernoErrorCode.cancelled => 'Generation was cancelled.',
        InfernoErrorCode.nativeUnavailable ||
        InfernoErrorCode.invalidState ||
        InfernoErrorCode.internal =>
          'The local inference runtime hit an internal error.',
      }, cause: error);
}
