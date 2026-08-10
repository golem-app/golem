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

/// KV-cache element type for engines that support quantized caches.
/// `f16` is every engine's default; `q8_0` halves KV memory (llama.cpp
/// quantizes both cache halves and requires flash attention for the value
/// half; MLX maps it to an 8-bit quantized cache).
enum InfernoKvCacheType { f16, q8_0 }

/// Load-time engine configuration, sent across the ABI as one JSON payload
/// alongside the model path (ABI 2). Null fields keep the engine's own
/// default; engines ignore fields that do not apply to them.
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

  /// Validate every tensor on load. Upstream llama.cpp defaults to false;
  /// true forces a full page-in of the mmapped weights — a triage tool,
  /// not a production default.
  final bool checkTensors;

  final InfernoKvCacheType kvCacheType;

  /// Decode/prefill thread count; null keeps the engine default.
  final int? threadCount;

  /// GPU offload override for llama.cpp (0 = CPU only, the #13 escape
  /// hatch); null keeps the build's default (all layers on Metal, none
  /// elsewhere).
  final int? gpuLayers;

  /// Size sliding-window-attention layers' KV cache at the full context
  /// instead of the window. Off by default, matching llama.cpp's own
  /// tooling: the full-size cache buys only cache-rollback ability that
  /// per-generate contexts never use, at real KV memory cost on SWA
  /// models like Gemma.
  final bool swaFull;

  /// The multimodal projector paired with this model, or null for a
  /// text-only load. An engine that cannot use one ignores it; an engine
  /// that can refuses a projector built for a different model rather than
  /// loading it and producing noise.
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

/// One encoded image handed to an engine: the file's own bytes (PNG, JPEG,
/// WebP), decoded natively rather than in Dart.
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

  /// Ordered images for this generation. The rendered [prompt] must carry one
  /// media marker per entry, in this order — the engine substitutes each
  /// marker with that image's encoded tokens.
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
