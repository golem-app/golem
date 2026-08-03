import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// The broker test is the one app test allowed to import Inferno: the ticket's
// mock engine exists exactly to verify broker behavior without native
// inference (see tool/check_inferno_imports.dart).
import 'package:inferno/inferno.dart';
import 'package:inferno/testing.dart';

import 'package:golem_flutter/broker/gemma4_chat_template.dart';
import 'package:golem_flutter/broker/inferno_inference_repository.dart';
import 'package:golem_flutter/broker/runtime.dart';
import 'package:golem_flutter/core/domain/models.dart';

final class _RecordingRuntime implements BrokerRuntime {
  BrokerGenerationRequest? request;
  int loads = 0;
  int cancels = 0;

  @override
  Future<void> load({
    required BrokerEngine engine,
    required String modelPath,
  }) async => loads++;

  @override
  Future<void> unload() async {}

  @override
  Future<void> cancel() async => cancels++;

  @override
  Stream<BrokerRuntimeEvent> generate(BrokerGenerationRequest request) async* {
    this.request = request;
    yield const BrokerTextDelta('<|chan');
    yield const BrokerTextDelta('nel>thought\nprivate ');
    yield const BrokerTextDelta('work\n<channel|>Visible answer.');
    yield const BrokerMetricsDelta(
      BrokerRuntimeMetrics(
        decodeTokensPerSecond: 20,
        promptTokensPerSecond: 120,
        generatedTokenCount: 4,
        elapsedSeconds: 0.2,
        promptTokenCount: 12,
        timeToFirstTokenSeconds: 0.05,
        peakPhysicalFootprintBytes: 128 << 20,
      ),
    );
    yield const BrokerGenerationCompleted();
  }
}

final class _MetricsRuntime extends _RecordingRuntime {
  @override
  Stream<BrokerRuntimeEvent> generate(BrokerGenerationRequest request) async* {
    yield const BrokerTextDelta('Answer');
    yield const BrokerMetricsDelta(
      BrokerRuntimeMetrics(
        decodeTokensPerSecond: 18.5,
        promptTokensPerSecond: 240,
        generatedTokenCount: 7,
        elapsedSeconds: 0.4,
      ),
    );
    yield const BrokerGenerationCompleted();
  }
}

void main() {
  test('Gemma template applies BOS and generation prompt exactly once', () {
    final rendered = Gemma4ChatTemplate.render(const [
      {'role': 'user', 'content': ' Hello '},
      {'role': 'assistant', 'content': 'Hi'},
      {'role': 'user', 'content': 'Why?'},
    ], reasoningEnabled: false);
    expect(rendered, startsWith('<bos><|turn>user\nHello<turn|>\n'));
    expect('<bos>'.allMatches(rendered), hasLength(1));
    expect(rendered, endsWith('<|turn>model\n'));
    expect('<|turn>model\n'.allMatches(rendered), hasLength(2));
  });

  test('reasoning control lives in one leading system turn', () {
    final rendered = Gemma4ChatTemplate.render(const [
      {'role': 'user', 'content': 'Hello'},
    ], reasoningEnabled: true);
    expect(
      rendered,
      '<bos><|turn>system\n<|think|>\n<turn|>\n'
      '<|turn>user\nHello<turn|>\n<|turn>model\n',
    );
  });

  test('split channel markers route thought and visible output', () async {
    final runtime = _RecordingRuntime();
    final repository = InfernoInferenceRepository(
      runtime,
      engine: BrokerEngine.mlx,
      modelPath: '/local/model',
      seed: 9,
    );
    await repository.prepare();
    await repository.prepare();
    final events = await repository
        .generate(
          context: const [
            {'role': 'user', 'content': 'Hello'},
          ],
          reasoningEnabled: true,
        )
        .toList();

    expect(runtime.loads, 1);
    expect(
      events.whereType<ReasoningDelta>().map((event) => event.text).join(),
      'private work\n',
    );
    expect(
      events.whereType<AnswerDelta>().map((event) => event.text).join(),
      'Visible answer.',
    );
    final metrics = events.whereType<MetricsEvent>().single.metrics;
    expect(metrics.tokenCount, 4);
    expect(metrics.decodeTokensPerSecond, 20);
    expect(metrics.promptTokensPerSecond, 120);
    expect(metrics.elapsedSeconds, 0.2);
    expect(events.last, isA<CompletedEvent>());
    expect(runtime.request!.prompt, contains('<|think|>'));
    expect('<bos>'.allMatches(runtime.request!.prompt), hasLength(1));
    expect(runtime.request!.sampling.stopTokenIds, [1, 106]);
    expect(runtime.request!.sampling.stopSequences, ['<turn|>']);
  });

  test('late thought channel resets a premature answer', () {
    final parser = ReasoningStreamParser();
    final first = parser.consume('Premature<|channel>thought\nrethinking');
    final last = parser.consume('\n<channel|>Final');
    expect(first.answer, 'Premature');
    expect(first.resetAnswer, isTrue);
    expect(first.reasoning, 'rethinking');
    expect(last.reasoning, '\n');
    expect(last.answer, 'Final');
  });

  test('the adapter forwards optional measurement fields', () async {
    final adapter = InfernoRuntimeAdapter(
      Inferno.withBackend(MockInfernoBackend()),
    );
    // Inferno validates path shape before touching any backend, so even the
    // mock needs an existing file.
    final model = File(
      '${Directory.systemTemp.createTempSync('golem-broker-').path}/m.gguf',
    )..writeAsBytesSync(const [0]);
    addTearDown(() => model.parent.deleteSync(recursive: true));
    await adapter.load(engine: BrokerEngine.llamaCpp, modelPath: model.path);
    final metrics =
        (await adapter
                .generate(
                  const BrokerGenerationRequest(
                    prompt: 'Hi',
                    sampling: BrokerSamplingParameters(
                      maxTokens: 8,
                      temperature: 1,
                      topP: 0.95,
                      seed: null,
                      stopSequences: [],
                      stopTokenIds: [],
                    ),
                  ),
                )
                .toList())
            .whereType<BrokerMetricsDelta>()
            .single
            .metrics;
    expect(metrics.promptTokenCount, 'Hi'.length);
    expect(metrics.timeToFirstTokenSeconds, isNotNull);
    expect(metrics.peakPhysicalFootprintBytes, 1 << 20);
  });

  test(
    'metrics without optional fields still reach the app contract',
    () async {
      final repository = InfernoInferenceRepository(
        _MetricsRuntime(),
        engine: BrokerEngine.llamaCpp,
        modelPath: '/local/model.gguf',
      );
      await repository.prepare();
      final events = await repository
          .generate(
            context: const [
              {'role': 'user', 'content': 'Hello'},
            ],
            reasoningEnabled: false,
          )
          .toList();
      final metrics = events.whereType<MetricsEvent>().single.metrics;
      expect(metrics.decodeTokensPerSecond, 18.5);
      expect(metrics.promptTokensPerSecond, 240);
      expect(metrics.tokenCount, 7);
      expect(events.last, isA<CompletedEvent>());
    },
  );

  test('subscription cancellation reaches the runtime', () async {
    final runtime = _RecordingRuntime();
    final repository = InfernoInferenceRepository(
      runtime,
      engine: BrokerEngine.llamaCpp,
      modelPath: '/local/model.gguf',
    );
    await repository.prepare();
    late StreamSubscription<InferenceEvent> subscription;
    subscription = repository
        .generate(
          context: const [
            {'role': 'user', 'content': 'Hello'},
          ],
          reasoningEnabled: false,
        )
        .listen((_) => unawaited(subscription.cancel()));
    await Future<void>.delayed(Duration.zero);
    await repository.cancel();
    expect(runtime.cancels, 1);
  });
}
