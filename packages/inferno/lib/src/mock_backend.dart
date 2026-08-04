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

  @override
  Future<void> load({
    required InfernoEngineKind engine,
    required String modelPath,
  }) async {
    if (failLoad case final failure?) throw failure;
    lastModelPath = modelPath;
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
    for (final delta in deltas) {
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      if (epoch != _generationEpoch) {
        yield const InfernoGenerationCompleted(InfernoStopReason.cancelled);
        return;
      }
      generated++;
      yield InfernoTextDelta(delta);
    }
    watch.stop();
    final elapsed = watch.elapsedMicroseconds / Duration.microsecondsPerSecond;
    yield InfernoMetricsEvent(
      InfernoMetrics(
        decodeTokensPerSecond: elapsed == 0 ? 0 : generated / elapsed,
        promptTokensPerSecond: 100,
        generatedTokenCount: generated,
        elapsedSeconds: elapsed,
        promptTokenCount: request.prompt.length,
        timeToFirstTokenSeconds: elapsed == 0 ? 0 : elapsed / generated,
        peakPhysicalFootprintBytes: 1 << 20,
      ),
    );
    yield const InfernoGenerationCompleted(InfernoStopReason.maxTokens);
  }

  @override
  Future<void> cancel() async => _generationEpoch++;

  @override
  void dispose() {}
}
