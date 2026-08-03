import 'package:inferno/inferno.dart';

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
  });

  final double decodeTokensPerSecond;
  final double promptTokensPerSecond;
  final int generatedTokenCount;
  final double elapsedSeconds;
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

final class BrokerGenerationCompleted extends BrokerRuntimeEvent {
  const BrokerGenerationCompleted();
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
  }) => _inferno.load(
    engine: switch (engine) {
      BrokerEngine.llamaCpp => InfernoEngineKind.llamaCpp,
      BrokerEngine.mlx => InfernoEngineKind.mlx,
    },
    modelPath: modelPath,
  );

  @override
  Future<void> unload() => _inferno.unload();

  @override
  Future<void> cancel() => _inferno.cancel();

  @override
  Stream<BrokerRuntimeEvent> generate(BrokerGenerationRequest request) async* {
    await for (final event in _inferno.generate(
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
    )) {
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
            ),
          );
        case InfernoGenerationCompleted():
          yield const BrokerGenerationCompleted();
      }
    }
  }
}
