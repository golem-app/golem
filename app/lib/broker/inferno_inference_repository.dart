import 'package:flutter/foundation.dart';

import '../core/domain/models.dart';
import '../core/repositories/contracts.dart';
import 'gemma4_chat_template.dart';
import 'runtime.dart';

final class InfernoInferenceRepository implements InferenceRepository {
  InfernoInferenceRepository(
    this._runtime, {
    required this.engine,
    required this.modelPath,
    this.seed,
  });

  final BrokerRuntime _runtime;
  final BrokerEngine engine;
  final String modelPath;
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
    final parser = ReasoningStreamParser();
    BrokerRuntimeMetrics? finalMetrics;
    var sawAnswer = false;
    await for (final event in _runtime.generate(
      BrokerGenerationRequest(
        prompt: Gemma4ChatTemplate.render(
          context,
          reasoningEnabled: reasoningEnabled,
        ),
        sampling: BrokerSamplingParameters(
          // Roomy enough that reasoning cannot silently starve the visible
          // answer; a budget stop is still surfaced below, never swallowed.
          maxTokens: 2048,
          temperature: 1,
          topP: 0.95,
          seed: seed,
          stopSequences: const [Gemma4ChatTemplate.turnEnd],
          stopTokenIds: const [
            Gemma4ChatTemplate.eosTokenId,
            Gemma4ChatTemplate.turnEndTokenId,
          ],
        ),
      ),
    )) {
      switch (event) {
        case BrokerTextDelta():
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

  static Iterable<InferenceEvent> _domainEvents(
    ReasoningStreamDelta delta,
  ) sync* {
    if (delta.resetAnswer) yield const AnswerResetEvent();
    if (delta.reasoning.isNotEmpty) yield ReasoningDelta(delta.reasoning);
    if (delta.answer.isNotEmpty) yield AnswerDelta(delta.answer);
  }
}
