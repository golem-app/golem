import 'dart:collection';
import 'dart:typed_data';

import 'errors.dart';

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
    this.reportProgress = false,
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

  /// Ask the engine for load progress (ABI 6). llama.cpp forwards its own
  /// fraction, rate-limited; MLX exposes none and stays silent. Off by
  /// default, and absent from the payload when off, so a caller that never
  /// asks sends exactly the ABI-5 payload.
  final bool reportProgress;

  Map<String, Object?> toJson() => {
    'checkTensors': checkTensors,
    'kvCacheType': kvCacheType.name,
    'threadCount': threadCount,
    'gpuLayers': gpuLayers,
    'swaFull': swaFull,
    'projectorPath': projectorPath,
    if (reportProgress) 'reportProgress': true,
  };
}

/// A load's progress, forwarded from the engine while weights map in.
typedef InfernoLoadProgress = void Function(double fraction);

/// What a generation should observe beyond its text (ABI 6). Everything is
/// opt-in: a request without one produces exactly the ABI-5 event stream,
/// which is what keeps an unobserved run the baseline an observed one is
/// compared against.
final class InfernoObservation {
  const InfernoObservation({
    this.promptProgress = false,
    this.tokenTiming = false,
  });

  /// `{"phase":"prompt","completed":n,"total":N}` after each prefill batch
  /// is submitted — llama.cpp text prompts only; MLX reports nothing.
  final bool promptProgress;

  /// Arrival instants per sampled token (llama.cpp) or per detokenized chunk
  /// (MLX), each a [InfernoTokenTimingEvent] naming which it is.
  final bool tokenTiming;

  bool get isEmpty => !promptProgress && !tokenTiming;

  Map<String, Object?> toJson() => {
    'promptProgress': promptProgress,
    'tokenTiming': tokenTiming,
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

  /// Additive penalty on tokens already seen, with a window covering the
  /// whole generation on both engines. Null keeps the penalty out of the
  /// chain. Engine semantics differ at the edge and are left engine-native:
  /// llama.cpp penalizes only tokens it sampled, while MLX pre-seeds its
  /// ring with the prompt, so prompt vocabulary and the stop token carry
  /// the penalty there too. This is the published Qwen 3.5 lever against a
  /// quantized build's non-terminating think loop (#80).
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
    this.observe,
  });

  final String prompt;
  final InfernoSamplingParameters sampling;

  /// The rendered [prompt] must carry one media marker per entry, in this
  /// order; the engine substitutes each marker with that image's tokens.
  final List<InfernoImageInput> images;

  /// Null (the default) asks for nothing beyond text and metrics.
  final InfernoObservation? observe;
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
    required this.timingSemanticsVersion,
    this.promptTokenCount,
    this.timeToFirstTokenSeconds,
    this.peakPhysicalFootprintBytes,
    this.promptBatchSize,
  });

  /// Parses one METRICS payload as the shims emit it.
  ///
  /// Every failure is a disagreement with a native half whose ABI already
  /// matched — a build defect — so it is a typed [InfernoException] naming
  /// the key rather than a cast error inside the event listener.
  factory InfernoMetrics.fromPayload(Map<String, Object?> payload) {
    Never reject(String detail) => throw InfernoException(
      InfernoErrorCode.internal,
      'The native metrics payload $detail.',
    );
    double required(String key) => switch (payload[key]) {
      final num value => value.toDouble(),
      _ => reject('has no numeric "$key"'),
    };
    num? optional(String key) => switch (payload[key]) {
      null => null,
      final num value => value,
      _ => reject('has a non-numeric "$key"'),
    };
    // Presence is required and the value is carried as-is: the ABI check
    // decides whether a shim may speak at all, this field only labels what
    // it measured, and a defaulted label is exactly what version 1 was.
    final version = switch (payload['timingSemanticsVersion']) {
      final int value when value >= 1 => value,
      _ => reject('omits a usable "timingSemanticsVersion"'),
    };
    return InfernoMetrics(
      decodeTokensPerSecond: required('decodeTokensPerSecond'),
      promptTokensPerSecond: required('promptTokensPerSecond'),
      generatedTokenCount: required('generatedTokenCount').toInt(),
      elapsedSeconds: required('elapsedSeconds'),
      timingSemanticsVersion: version,
      promptTokenCount: optional('promptTokenCount')?.toInt(),
      timeToFirstTokenSeconds: optional('timeToFirstTokenSeconds')?.toDouble(),
      peakPhysicalFootprintBytes: optional(
        'peakPhysicalFootprintBytes',
      )?.toInt(),
      promptBatchSize: optional('promptBatchSize')?.toInt(),
    );
  }

  /// The contract version 2 names (docs/architecture/inferno.md): the first
  /// token and the elapsed time are both measured from the instant the native
  /// shim accepted the request, and the decode rate is the token count over
  /// the window after the first token. Version 1 — an absent key, found
  /// only in records written before #57 — started that field at the
  /// prefill's submission (ADR 0020).
  static const currentTimingSemanticsVersion = 2;

  final double decodeTokensPerSecond;
  final double promptTokensPerSecond;
  final int generatedTokenCount;
  final double elapsedSeconds;
  final int timingSemanticsVersion;
  final int? promptTokenCount;

  /// Null exactly when no token was produced: zero would be a measurement.
  final double? timeToFirstTokenSeconds;
  final int? peakPhysicalFootprintBytes;

  /// The prefill batch the engine ran with (ABI 6). llama.cpp reports the
  /// `n_batch` it sized for the prompt; MLX reports nothing, and null means
  /// exactly that — not reported, never "no batching".
  final int? promptBatchSize;
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

/// Which phase a progress event describes (ABI 6).
enum InfernoProgressPhase { load, prompt }

/// Progress inside a generation (a load's progress arrives through
/// [InfernoLoadProgress] instead). [completed] and [total] are submitted
/// prompt tokens — how much of the prompt has been handed to the backend,
/// which on Metal runs ahead of the compute — so this is a count, never a
/// rate; the prompt rate is the metrics'.
final class InfernoProgressEvent extends InfernoGenerationEvent {
  const InfernoProgressEvent({
    required this.phase,
    this.fraction,
    this.completed,
    this.total,
  });

  final InfernoProgressPhase phase;
  final double? fraction;
  final int? completed;
  final int? total;
}

/// What one timing observation is an instant of. A llama.cpp observation is
/// one sampled token; an MLX observation is one detokenized chunk, which the
/// library assembles from one or more tokens — so chunk instants are
/// inter-chunk arrivals and must never be read, or divided, as tokens.
enum InfernoObservationKind { token, chunk }

/// A contiguous batch of arrival instants, in milliseconds since the request
/// was accepted (the metrics' t0) on the engine's own monotonic clock.
/// [firstIndex] is the zero-based index of the first observation; the next
/// batch begins at `firstIndex + timesMs.length`.
final class InfernoTokenTimingEvent extends InfernoGenerationEvent {
  const InfernoTokenTimingEvent({
    required this.kind,
    required this.firstIndex,
    required this.timesMs,
  });

  final InfernoObservationKind kind;
  final int firstIndex;
  final List<double> timesMs;
}
