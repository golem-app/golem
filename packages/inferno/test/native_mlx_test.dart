@Tags(['real-model'])
library;

import 'dart:io';

import 'package:inferno/inferno.dart';
import 'package:inferno/testing.dart';
import 'package:test/test.dart';

import 'timing_invariants.dart';

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
      // Loud here, unlike the parity suites: this group only runs under
      // INFERNO_GEMMA_MLX, so a missing metallib is certain to surface as an
      // opaque failure inside MLX rather than as a shader library nobody
      // staged.
      if (Platform.isMacOS) stageMlxMetallibForCliRun(warnOnMissing: true);
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
      expectHonestTiming(metrics);
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

    test('observes chunk arrivals when asked, and only then', () async {
      // ABI 6: the library yields a chunk per one or more tokens and exposes
      // no load or prefill progress, so this shim reports chunk instants and
      // nothing else — and nothing at all when not asked.
      final quiet = await inferno!.generate(request).toList();
      expect(quiet.whereType<InfernoProgressEvent>(), isEmpty);
      expect(quiet.whereType<InfernoTokenTimingEvent>(), isEmpty);
      expect(
        quiet.whereType<InfernoMetricsEvent>().single.metrics.promptBatchSize,
        isNull,
      );

      final observed = await inferno!
          .generate(
            InfernoGenerationRequest(
              prompt: request.prompt,
              sampling: request.sampling,
              observe: const InfernoObservation(
                promptProgress: true,
                tokenTiming: true,
              ),
            ),
          )
          .toList();
      expect(observed.whereType<InfernoProgressEvent>(), isEmpty);
      final metrics = observed.whereType<InfernoMetricsEvent>().single.metrics;
      final batches = observed.whereType<InfernoTokenTimingEvent>().toList();
      expect(batches, isNotEmpty);
      expectContiguousObservations(
        batches,
        kind: InfernoObservationKind.chunk,
        elapsedSeconds: metrics.elapsedSeconds,
      );
      // Chunks, not tokens: never more of them than tokens.
      final chunks = batches.fold<int>(0, (n, b) => n + b.timesMs.length);
      expect(chunks, lessThanOrEqualTo(metrics.generatedTokenCount));
    });

    test('survives an unload and reload in one process', () async {
      await inferno!.unload();
      await inferno!.load(engine: InfernoEngineKind.mlx, modelPath: mlxPath!);
      final events = await inferno!.generate(request).toList();
      expect(events.whereType<InfernoTextDelta>(), isNotEmpty);
      expect(events.last, isA<InfernoGenerationCompleted>());
    });
  }, skip: skipReason);
}
