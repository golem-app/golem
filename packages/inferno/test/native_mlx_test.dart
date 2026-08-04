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

  setUpAll(() {
    if (Platform.isMacOS) _stageMetallibForCliRun();
  });

  test(
    'the pinned MLX artifact loads, streams, and reloads',
    () async {
      final inferno = Inferno.native();
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
      for (var cycle = 0; cycle < 2; cycle++) {
        await inferno.load(engine: InfernoEngineKind.mlx, modelPath: mlxPath!);
        final events = await inferno.generate(request).toList();
        expect(
          events.whereType<InfernoTextDelta>(),
          isNotEmpty,
          reason: 'cycle $cycle',
        );
        final metrics = events.whereType<InfernoMetricsEvent>().single.metrics;
        expect(
          metrics.generatedTokenCount,
          greaterThan(0),
          reason: 'cycle $cycle',
        );
        expect(metrics.peakPhysicalFootprintBytes, greaterThan(0));
        expect(events.last, isA<InfernoGenerationCompleted>());
        await inferno.unload();
      }
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
