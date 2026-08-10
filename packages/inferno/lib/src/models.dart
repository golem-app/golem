import 'dart:collection';
import 'dart:typed_data';

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

/// `f16` is every engine's default; `q8_0` halves KV memory (llama.cpp
/// quantizes both cache halves and requires flash attention for the value half;
/// MLX maps it to an 8-bit quantized cache).
enum InfernoKvCacheType { f16, q8_0 }

/// Sent across the ABI as one JSON payload alongside the model path (ABI 2).
/// Null fields keep the engine default; engines ignore what does not apply.
final class InfernoLoadOptions {
  const InfernoLoadOptions({
    this.checkTensors = false,
    this.kvCacheType = InfernoKvCacheType.f16,
    this.threadCount,
    this.gpuLayers,
    this.swaFull = false,
    this.projectorPath,
  }) : assert(
         threadCount == null || threadCount > 0,
         'threadCount must be positive when set',
       );

  /// Upstream llama.cpp defaults to false; true forces a full page-in of the
  /// mmapped weights — a triage tool, not a production default.
  final bool checkTensors;

  final InfernoKvCacheType kvCacheType;

  final int? threadCount;

  /// llama.cpp GPU offload (0 = CPU only, the #13 escape hatch); null keeps the
  /// build default — all layers on Metal, none elsewhere.
  final int? gpuLayers;

  /// Size SWA layers' KV cache at the full context instead of the window. Off
  /// by default, like llama.cpp's own tooling: it buys only cache-rollback that
  /// per-generate contexts never use, at real KV cost on SWA models like Gemma.
  final bool swaFull;

  /// An engine that cannot use a projector ignores it; one that can refuses a
  /// projector built for a different model rather than producing noise.
  final String? projectorPath;

  Map<String, Object?> toJson() => {
    'checkTensors': checkTensors,
    'kvCacheType': kvCacheType.name,
    'threadCount': threadCount,
    'gpuLayers': gpuLayers,
    'swaFull': swaFull,
    'projectorPath': projectorPath,
  };
}

final class InfernoSamplingParameters {
  const InfernoSamplingParameters({
    this.maxTokens = 512,
    this.temperature = 1,
    this.topP = 0.95,
    this.topK,
    this.contextLength,
    this.presencePenalty,
    this.seed,
    this.stopSequences = const [],
    this.stopTokenIds = const [],
  }) : assert(maxTokens > 0),
       assert(temperature >= 0),
       assert(topP > 0 && topP <= 1),
       assert(topK == null || topK > 0),
       assert(contextLength == null || contextLength > 0),
       assert(presencePenalty == null || presencePenalty > 0);

  final int maxTokens;
  final double temperature;
  final double topP;

  /// Null keeps the sampler out of the chain entirely.
  final int? topK;

  /// Token budget over prompt plus generation, enforced before decoding starts.
  /// Engines with a trained context window cap the budget there; MLX, having
  /// none, enforces the budget as its only bound.
  final int? contextLength;

  /// Additive penalty on tokens already present in the generation, applied
  /// over the whole generation window on both engines. Null keeps the
  /// penalty out of the chain. This is the published Qwen 3.5 lever against
  /// a quantized build's non-terminating think loop (#80).
  final double? presencePenalty;

  final int? seed;
  final List<String> stopSequences;
  final List<int> stopTokenIds;
}

/// The file's own bytes (PNG, JPEG, WebP), decoded natively rather than in Dart.
final class InfernoImageInput {
  const InfernoImageInput(this.bytes);

  final Uint8List bytes;
}

/// Input to an engine. The prompt is already rendered by the caller.
final class InfernoGenerationRequest {
  const InfernoGenerationRequest({
    required this.prompt,
    this.sampling = const InfernoSamplingParameters(),
    this.images = const [],
  });

  final String prompt;
  final InfernoSamplingParameters sampling;

  /// The rendered [prompt] must carry one media marker per entry, in this
  /// order; the engine substitutes each marker with that image's tokens.
  final List<InfernoImageInput> images;
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
