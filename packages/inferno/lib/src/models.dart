import 'dart:collection';

enum InfernoEngineKind { llamaCpp, mlx, mock }

final class InfernoEngineProbe {
  const InfernoEngineProbe({
    required this.engine,
    required this.available,
    this.detail,
  });

  final InfernoEngineKind engine;
  final bool available;
  final String? detail;
}

final class InfernoDeviceProbe {
  InfernoDeviceProbe({
    required this.operatingSystem,
    required Iterable<InfernoEngineProbe> engines,
  }) : engines = UnmodifiableListView(engines);

  final String operatingSystem;
  final List<InfernoEngineProbe> engines;

  bool supports(InfernoEngineKind engine) =>
      engines.any((probe) => probe.engine == engine && probe.available);
}

final class InfernoSamplingParameters {
  const InfernoSamplingParameters({
    this.maxTokens = 512,
    this.temperature = 1,
    this.topP = 0.95,
    this.topK,
    this.contextLength,
    this.seed,
    this.stopSequences = const [],
    this.stopTokenIds = const [],
  }) : assert(maxTokens > 0),
       assert(temperature >= 0),
       assert(topP > 0 && topP <= 1),
       assert(topK == null || topK > 0),
       assert(contextLength == null || contextLength > 0);

  final int maxTokens;
  final double temperature;
  final double topP;

  /// Top-k sampling cutoff; null keeps the sampler out of the chain entirely,
  /// preserving pre-existing behavior bit for bit.
  final int? topK;

  /// Token budget over prompt plus generation, enforced by every engine
  /// before decoding starts. Engines with a trained context window cap the
  /// budget at that window; engines without one (MLX) enforce the budget as
  /// their only bound.
  final int? contextLength;

  final int? seed;
  final List<String> stopSequences;
  final List<int> stopTokenIds;
}

/// Input to an engine. The prompt is already rendered by the caller.
final class InfernoGenerationRequest {
  const InfernoGenerationRequest({
    required this.prompt,
    this.sampling = const InfernoSamplingParameters(),
  });

  final String prompt;
  final InfernoSamplingParameters sampling;
}

enum InfernoStopReason {
  endOfSequence,
  stopSequence,
  stopToken,
  maxTokens,
  cancelled,
}

final class InfernoMetrics {
  const InfernoMetrics({
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
  final int? promptTokenCount;
  final double? timeToFirstTokenSeconds;
  final int? peakPhysicalFootprintBytes;
}

sealed class InfernoGenerationEvent {
  const InfernoGenerationEvent();
}

final class InfernoTextDelta extends InfernoGenerationEvent {
  const InfernoTextDelta(this.text);

  final String text;
}

final class InfernoMetricsEvent extends InfernoGenerationEvent {
  const InfernoMetricsEvent(this.metrics);

  final InfernoMetrics metrics;
}

final class InfernoGenerationCompleted extends InfernoGenerationEvent {
  const InfernoGenerationCompleted(this.reason);

  final InfernoStopReason reason;
}
