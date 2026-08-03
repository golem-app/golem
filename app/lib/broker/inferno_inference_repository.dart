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

  @override
  Future<void> prepare() async {
    if (_loaded) return;
    await _runtime.load(engine: engine, modelPath: modelPath);
    _loaded = true;
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
    await for (final event in _runtime.generate(
      BrokerGenerationRequest(
        prompt: Gemma4ChatTemplate.render(
          context,
          reasoningEnabled: reasoningEnabled,
        ),
        sampling: BrokerSamplingParameters(
          maxTokens: 512,
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
            yield domainEvent;
          }
        case BrokerMetricsDelta():
          final metrics = event.metrics;
          yield MetricsEvent(
            InferenceMetrics(
              promptTokensPerSecond: metrics.promptTokensPerSecond,
              decodeTokensPerSecond: metrics.decodeTokensPerSecond,
              tokenCount: metrics.generatedTokenCount,
              elapsedSeconds: metrics.elapsedSeconds,
            ),
          );
        case BrokerGenerationCompleted():
          for (final domainEvent in _domainEvents(parser.finish())) {
            yield domainEvent;
          }
          yield const CompletedEvent();
      }
    }
  }

  static Iterable<InferenceEvent> _domainEvents(
    ReasoningStreamDelta delta,
  ) sync* {
    if (delta.resetAnswer) yield const AnswerResetEvent();
    if (delta.reasoning.isNotEmpty) yield ReasoningDelta(delta.reasoning);
    if (delta.answer.isNotEmpty) yield AnswerDelta(delta.answer);
  }
}
