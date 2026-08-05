import 'package:flutter/foundation.dart';

import '../core/domain/models.dart';
import '../core/repositories/contracts.dart';
import 'hash.dart';
import 'model_profile.dart';
import 'runtime.dart';

final class InfernoInferenceRepository implements InferenceRepository {
  InfernoInferenceRepository(
    this._runtime, {
    required this.engine,
    required this.modelPath,
    required this.profile,
    this.seed,
  });

  final BrokerRuntime _runtime;
  final BrokerEngine engine;
  final String modelPath;
  final ModelProfile profile;
  final int? seed;
  bool _loaded = false;
  Future<void>? _preparing;

  @override
  Future<void> prepare() {
    if (_loaded) return Future.value();
    // Loading takes seconds; a second caller must join the load in flight
    // rather than trip the runtime's single-operation lifecycle.
    return _preparing ??= () async {
      try {
        await _runtime.load(engine: engine, modelPath: modelPath);
        _loaded = true;
      } finally {
        _preparing = null;
      }
    }();
  }

  @override
  Future<void> unload() async {
    if (!_loaded) return;
    await _runtime.unload();
    _loaded = false;
  }

  @override
  Future<void> cancel() => _runtime.cancel();

  @override
  Stream<InferenceEvent> generate({
    required List<Map<String, String>> context,
    required bool reasoningEnabled,
  }) async* {
    if (!_loaded) throw StateError('Inferno is not loaded.');
    final parser = profile.newParser(reasoningEnabled: reasoningEnabled);
    final sampling = profile.sampling(reasoningEnabled: reasoningEnabled);
    BrokerRuntimeMetrics? finalMetrics;
    var sawAnswer = false;
    final probe = seed == null ? null : StringBuffer();
    await for (final event in _runtime.generate(
      BrokerGenerationRequest(
        prompt: profile.render(context, reasoningEnabled: reasoningEnabled),
        sampling: BrokerSamplingParameters(
          maxTokens: sampling.maxTokens,
          temperature: sampling.temperature,
          topP: sampling.topP,
          seed: seed,
          stopSequences: profile.stopSequences,
          stopTokenIds: profile.stopTokenIds,
        ),
      ),
    )) {
      switch (event) {
        case BrokerTextDelta():
          probe?.write(event.text);
          for (final domainEvent in _domainEvents(parser.consume(event.text))) {
            if (domainEvent is AnswerDelta) sawAnswer = true;
            if (domainEvent is AnswerResetEvent) sawAnswer = false;
            yield domainEvent;
          }
        case BrokerMetricsDelta():
          final metrics = event.metrics;
          finalMetrics = metrics;
          yield MetricsEvent(
            InferenceMetrics(
              promptTokensPerSecond: metrics.promptTokensPerSecond,
              decodeTokensPerSecond: metrics.decodeTokensPerSecond,
              tokenCount: metrics.generatedTokenCount,
              elapsedSeconds: metrics.elapsedSeconds,
            ),
          );
        case BrokerGenerationCompleted():
          _logMetrics(finalMetrics, event.reason);
          if (probe != null) _logProbe(probe.toString());
          for (final domainEvent in _domainEvents(parser.finish())) {
            if (domainEvent is AnswerDelta) sawAnswer = true;
            yield domainEvent;
          }
          if (event.reason == BrokerStopReason.maxTokens && !sawAnswer) {
            throw const BrokerRuntimeException(
              'The response used its whole token budget before reaching an '
              'answer. Try again, or turn reasoning off.',
            );
          }
          yield const CompletedEvent();
      }
    }
  }

  /// One greppable line per completed generation; this is the capture channel
  /// for on-device measurement (the app contract carries only core metrics).
  void _logMetrics(BrokerRuntimeMetrics? metrics, BrokerStopReason reason) {
    if (metrics == null) return;
    debugPrint(
      'INFERNO_METRICS engine=${engine.name}'
      ' stopReason=${reason.name}'
      ' decodeTokensPerSecond=${metrics.decodeTokensPerSecond.toStringAsFixed(2)}'
      ' promptTokensPerSecond=${metrics.promptTokensPerSecond.toStringAsFixed(2)}'
      ' generatedTokenCount=${metrics.generatedTokenCount}'
      ' promptTokenCount=${metrics.promptTokenCount}'
      ' timeToFirstTokenSeconds=${metrics.timeToFirstTokenSeconds?.toStringAsFixed(3)}'
      ' elapsedSeconds=${metrics.elapsedSeconds.toStringAsFixed(2)}'
      ' peakPhysicalFootprintBytes=${metrics.peakPhysicalFootprintBytes}',
    );
  }

  /// One greppable line per seeded generation, hashing the raw pre-parser
  /// text so two devices can be compared for token-identical output without
  /// shipping the transcript through logs. Only emitted when a fixed seed is
  /// configured (`GOLEM_SAMPLING_SEED`), i.e. during determinism probes.
  void _logProbe(String rawText) {
    debugPrint(
      'INFERNO_PROBE engine=${engine.name}'
      ' seed=$seed'
      ' chars=${rawText.length}'
      ' fnv1a64=${fnv1a64(rawText)}',
    );
  }

  static Iterable<InferenceEvent> _domainEvents(
    ReasoningStreamDelta delta,
  ) sync* {
    if (delta.resetAnswer) yield const AnswerResetEvent();
    if (delta.reasoning.isNotEmpty) yield ReasoningDelta(delta.reasoning);
    if (delta.answer.isNotEmpty) yield AnswerDelta(delta.answer);
  }
}
