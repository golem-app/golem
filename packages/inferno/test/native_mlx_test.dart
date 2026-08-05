@Tags(['real-model'])
library;

import 'dart:io';

import 'package:inferno/inferno.dart';
import 'package:test/test.dart';

/// MLX resolves its shader library beside the loaded binary before falling
/// back to app-bundle lookups; CLI runs stage it there (see
/// tokenization_parity_test.dart).
void _stageMetallibForCliRun() {
  final dylib = File('.dart_tool/lib/libinferno_mlx.dylib');
  final metallib = File(
    'build/apple-resources/macosx/mlx-swift_Cmlx.bundle/'
    'Contents/Resources/default.metallib',
  );
  if (dylib.existsSync() && metallib.existsSync()) {
    metallib.copySync('${dylib.parent.path}/mlx.metallib');
  }
}

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

  // One shared runtime: the multi-gigabyte artifact loads once in setUpAll
  // and every test runs against the resident model. The `real-model` tag's
  // budget in dart_test.yaml covers the load.
  group('pinned MLX artifact', () {
    final inferno = Inferno.native();

    setUpAll(() async {
      if (Platform.isMacOS) _stageMetallibForCliRun();
      await inferno.load(engine: InfernoEngineKind.mlx, modelPath: mlxPath!);
    });

    tearDownAll(() async {
      await inferno.unload();
      await inferno.dispose();
    });

    test('streams deltas and reports metrics', () async {
      final events = await inferno.generate(request).toList();
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
          inferno
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
                  InfernoErrorCode.generationFailed,
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
      await inferno.unload();
      await inferno.load(engine: InfernoEngineKind.mlx, modelPath: mlxPath!);
      final events = await inferno.generate(request).toList();
      expect(events.whereType<InfernoTextDelta>(), isNotEmpty);
      expect(events.last, isA<InfernoGenerationCompleted>());
    });
  }, skip: skipReason);
}
