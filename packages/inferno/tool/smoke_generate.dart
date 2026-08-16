import 'dart:io';

import 'package:inferno/inferno.dart';
import 'package:inferno/testing.dart';

/// Bench helper: run one deterministic generation against a local model and
/// print the decoded text plus metrics. Usage:
/// `dart run tool/smoke_generate.dart <llama|mlx> <model-path> [prompt]`.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln(
      'Usage: dart run tool/smoke_generate.dart <llama|mlx> <model-path> '
      '[prompt]',
    );
    exitCode = 64;
    return;
  }
  final engine = switch (arguments.first) {
    'llama' => InfernoEngineKind.llamaCpp,
    'mlx' => InfernoEngineKind.mlx,
    _ => throw ArgumentError('Engine must be llama or mlx.'),
  };
  final userPrompt = arguments.length > 2
      ? arguments[2]
      : 'Reply with one short word.';
  final rendered = '<bos><|turn>user\n$userPrompt<turn|>\n<|turn>model\n';

  if (Platform.isMacOS && engine == InfernoEngineKind.mlx) {
    stageMlxMetallibForCliRun(warnOnMissing: true);
  }
  final inferno = Inferno.native();
  await inferno.load(engine: engine, modelPath: arguments[1]);
  final buffer = StringBuffer();
  await for (final event in inferno.generate(
    InfernoGenerationRequest(
      prompt: rendered,
      sampling: const InfernoSamplingParameters(
        maxTokens: 64,
        temperature: 1,
        topP: 0.95,
        seed: 7,
        stopSequences: ['<turn|>'],
        stopTokenIds: [1, 106],
      ),
    ),
  )) {
    switch (event) {
      case InfernoTextDelta():
        buffer.write(event.text);
      case InfernoMetricsEvent():
        final m = event.metrics;
        stderr.writeln(
          'metrics: decode=${m.decodeTokensPerSecond.toStringAsFixed(1)} tok/s'
          ' prompt=${m.promptTokensPerSecond.toStringAsFixed(1)} tok/s'
          ' tokens=${m.generatedTokenCount}'
          ' ttft=${m.timeToFirstTokenSeconds?.toStringAsFixed(3)}s'
          ' peakBytes=${m.peakPhysicalFootprintBytes}',
        );
      case InfernoGenerationCompleted():
        stderr.writeln('stop: ${event.reason.name}');
    }
  }
  stdout.writeln('OUTPUT: $buffer');
  await inferno.dispose();
}
