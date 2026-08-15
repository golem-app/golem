@Tags(['real-model'])
library;

import 'dart:io';

import 'package:inferno/inferno.dart';
import 'package:inferno/testing.dart';
import 'package:test/test.dart';

void main() {
  final mlxPath = Platform.environment['INFERNO_GEMMA_MLX'];
  final skipReason = mlxPath == null
      ? 'Set INFERNO_GEMMA_MLX (see tool/fetch_model.dart) for the MLX bench.'
      : false;

  const request = InfernoGenerationRequest(
    prompt: '<bos><|turn>user\nSay hello.<turn|>\n<|turn>model\n',
    sampling: InfernoSamplingParameters(
      maxTokens: 16,
      temperature: 0.2,
      topP: 0.9,
      seed: 7,
      stopTokenIds: [1, 106],
    ),
  );

  // The `real-model` tag's budget in dart_test.yaml covers the shared load.
  group('pinned MLX artifact', () {
    // Constructed in setUpAll: a group body runs at collection time even when
    // skipped, and the native runtime must not spin up then. Nullable so a
    // setUpAll failure cannot turn tearDownAll into a LateInitializationError.
    Inferno? inferno;

    setUpAll(() async {
      if (Platform.isMacOS) stageMlxMetallibForCliRun();
      inferno = Inferno.native();
      await inferno!.load(engine: InfernoEngineKind.mlx, modelPath: mlxPath!);
    });

    tearDownAll(() async {
      await inferno?.unload();
      await inferno?.dispose();
    });

    test('streams deltas and reports metrics', () async {
      final events = await inferno!.generate(request).toList();
      expect(events.whereType<InfernoTextDelta>(), isNotEmpty);
      final metrics = events.whereType<InfernoMetricsEvent>().single.metrics;
      expect(metrics.generatedTokenCount, greaterThan(0));
      expect(metrics.peakPhysicalFootprintBytes, greaterThan(0));
      expect(events.last, isA<InfernoGenerationCompleted>());
    });

    test(
      'a context budget below prompt plus max tokens fails clearly',
      () async {
        await expectLater(
          inferno!
              .generate(
                const InfernoGenerationRequest(
                  prompt: '<bos><|turn>user\nSay hello.<turn|>\n<|turn>model\n',
                  sampling: InfernoSamplingParameters(
                    maxTokens: 16,
                    contextLength: 8,
                    seed: 7,
                    stopTokenIds: [1, 106],
                  ),
                ),
              )
              .toList(),
          throwsA(
            isA<InfernoException>()
                .having(
                  (error) => error.code,
                  'code',
                  InfernoErrorCode.contextExhausted,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('context budget'),
                ),
          ),
        );
      },
    );

    test('survives an unload and reload in one process', () async {
      await inferno!.unload();
      await inferno!.load(engine: InfernoEngineKind.mlx, modelPath: mlxPath!);
      final events = await inferno!.generate(request).toList();
      expect(events.whereType<InfernoTextDelta>(), isNotEmpty);
      expect(events.last, isA<InfernoGenerationCompleted>());
    });
  }, skip: skipReason);
}
