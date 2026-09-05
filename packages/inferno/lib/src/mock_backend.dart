import 'dart:async';
import 'dart:io';

import 'backend.dart';
import 'errors.dart';
import 'models.dart';

/// A deterministic backend for API, broker, and UI tests.
final class MockInfernoBackend implements InfernoBackend {
  MockInfernoBackend({
    this.deltas = const ['Mock ', 'generation'],
    this.delay = Duration.zero,
    this.failLoad,
    this.failGeneration,
  });

  final List<String> deltas;
  final Duration delay;
  final InfernoException? failLoad;
  final InfernoException? failGeneration;

  bool _loaded = false;
  int _generationEpoch = 0;
  String? lastModelPath;
  InfernoGenerationRequest? lastRequest;

  @override
  Future<InfernoDeviceProbe> probe() async => InfernoDeviceProbe(
    operatingSystem: Platform.operatingSystem,
    engines: const [
      InfernoEngineProbe(engine: InfernoEngineKind.mock, available: true),
    ],
  );

  InfernoLoadOptions? lastLoadOptions;

  @override
  Future<void> load({
    required InfernoEngineKind engine,
    required String modelPath,
    InfernoLoadOptions options = const InfernoLoadOptions(),
  }) async {
    if (failLoad case final failure?) throw failure;
    lastModelPath = modelPath;
    lastLoadOptions = options;
    _loaded = true;
  }

  @override
  Future<void> unload() async {
    _generationEpoch++;
    _loaded = false;
  }

  @override
  Stream<InfernoGenerationEvent> generate(
    InfernoGenerationRequest request,
  ) async* {
    if (!_loaded) {
      throw const InfernoException(
        InfernoErrorCode.invalidState,
        'The mock model is not loaded.',
      );
    }
    if (failGeneration case final failure?) throw failure;
    lastRequest = request;
    final epoch = ++_generationEpoch;
    final watch = Stopwatch()..start();
    var generated = 0;
    double? firstDeltaSeconds;
    for (final delta in deltas) {
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      if (epoch != _generationEpoch) {
        yield const InfernoGenerationCompleted(InfernoStopReason.cancelled);
        return;
      }
      generated++;
      firstDeltaSeconds ??= _seconds(watch);
      yield InfernoTextDelta(delta);
    }
    watch.stop();
    final elapsed = _seconds(watch);
    final decodeSeconds = elapsed - (firstDeltaSeconds ?? elapsed);
    // Measured from the top of the call like the shims, so ttft <= elapsed
    // holds; the prefill relation (ttft >= prompt window) is not modelled.
    yield InfernoMetricsEvent(
      InfernoMetrics(
        decodeTokensPerSecond: generated > 1 && decodeSeconds > 0
            ? (generated - 1) / decodeSeconds
            : 0,
        promptTokensPerSecond: 100,
        generatedTokenCount: generated,
        elapsedSeconds: elapsed,
        timingSemanticsVersion: InfernoMetrics.currentTimingSemanticsVersion,
        promptTokenCount: request.prompt.length,
        timeToFirstTokenSeconds: firstDeltaSeconds,
        peakPhysicalFootprintBytes: 1 << 20,
      ),
    );
    yield const InfernoGenerationCompleted(InfernoStopReason.maxTokens);
  }

  @override
  Future<void> cancel() async => _generationEpoch++;

  @override
  void releaseEngine() {}

  @override
  void dispose() {}
}

double _seconds(Stopwatch watch) =>
    watch.elapsedMicroseconds / Duration.microsecondsPerSecond;
