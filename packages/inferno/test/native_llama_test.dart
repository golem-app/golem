import 'dart:async';
import 'dart:io';

import 'package:inferno/inferno.dart';
import 'package:test/test.dart';

void main() {
  final modelPath = Platform.environment['INFERNO_TOY_GGUF'];
  final skipReason = modelPath == null
      ? 'Set INFERNO_TOY_GGUF using tool/fetch_toy_model.dart.'
      : false;

  test('toy GGUF loads, streams, reports metrics, and unloads', () async {
    final inferno = Inferno.native();
    await inferno.load(
      engine: InfernoEngineKind.llamaCpp,
      modelPath: modelPath!,
    );
    final events = await inferno
        .generate(
          const InfernoGenerationRequest(
            prompt: 'Hello',
            sampling: InfernoSamplingParameters(
              maxTokens: 8,
              temperature: 0.2,
              topP: 0.9,
              seed: 7,
            ),
          ),
        )
        .toList();
    expect(events.whereType<InfernoTextDelta>(), isNotEmpty);
    final metrics = events.whereType<InfernoMetricsEvent>().single.metrics;
    expect(metrics.generatedTokenCount, greaterThan(0));
    expect(metrics.elapsedSeconds, greaterThanOrEqualTo(0));
    expect(events.last, isA<InfernoGenerationCompleted>());
    await inferno.unload();
  }, skip: skipReason);

  test(
    'toy GGUF generation can be cancelled without wedging the runtime',
    () async {
      final inferno = Inferno.native();
      await inferno.load(
        engine: InfernoEngineKind.llamaCpp,
        modelPath: modelPath!,
      );
      final events = <InfernoGenerationEvent>[];
      final done = Completer<void>();
      inferno
          .generate(
            const InfernoGenerationRequest(
              prompt: 'Keep generating random text',
              sampling: InfernoSamplingParameters(maxTokens: 256, seed: 9),
            ),
          )
          .listen((event) {
            events.add(event);
          }, onDone: done.complete);
      await inferno.cancel();
      await done.future;
      expect(
        events.whereType<InfernoGenerationCompleted>().single.reason,
        InfernoStopReason.cancelled,
      );
      await inferno.unload();
    },
    skip: skipReason,
  );

  test('damaged GGUF variants fail as catchable Dart errors', () async {
    final fixtureDirectory = File(modelPath!).parent.path;
    for (final fixture in {
      'corrupt.gguf': InfernoErrorCode.corruptModel,
      'truncated.gguf': InfernoErrorCode.corruptModel,
      'incompatible.gguf': InfernoErrorCode.incompatibleModel,
    }.entries) {
      final inferno = Inferno.native();
      await expectLater(
        inferno.load(
          engine: InfernoEngineKind.llamaCpp,
          modelPath: '$fixtureDirectory/${fixture.key}',
        ),
        throwsA(
          isA<InfernoException>().having(
            (error) => error.code,
            fixture.key,
            fixture.value,
          ),
        ),
      );
    }
  }, skip: skipReason);
}
