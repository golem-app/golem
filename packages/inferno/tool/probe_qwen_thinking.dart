import 'dart:io';

import 'package:inferno/inferno.dart';
import 'package:inferno/testing.dart';

/// #80 probe: does the Qwen 3.5 thinking channel close before the budget,
/// per sampling recipe? Runs the failing `reasoning-speed` anchor prompt
/// against a local artifact under a grid of sampling variants × seeds and
/// reports, per run, whether `</think>` arrived, the token count, and
/// whether the visible answer contains the expected `80`.
///
/// Usage: `dart run tool/probe_qwen_thinking.dart <llama|mlx> <model-path>`.
///
/// The variants compare the pre-#80 pinned recipe against the official
/// Qwen 3.5 card (thinking general: temperature 1.0, top-p 0.95, top-k 20,
/// presence penalty 1.5), isolating top-k, temperature, and the penalty —
/// the field ABI 4 was added to carry.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln(
      'Usage: dart run tool/probe_qwen_thinking.dart <llama|mlx> <model-path>',
    );
    exitCode = 64;
    return;
  }
  final engine = switch (arguments.first) {
    'llama' => InfernoEngineKind.llamaCpp,
    'mlx' => InfernoEngineKind.mlx,
    _ => throw ArgumentError('Engine must be llama or mlx.'),
  };

  const prompt =
      '<|im_start|>user\n'
      'A train travels 60 km in 45 minutes. What is its average speed in '
      'km/h? Give the final number.<|im_end|>\n'
      '<|im_start|>assistant\n'
      '<think>\n';
  const variants = <String, (double, double, int?, double?)>{
    'pinned-0.6/0.95/-': (0.6, 0.95, null, null),
    'pinned+topk-0.6/0.95/20': (0.6, 0.95, 20, null),
    'card-1.0/0.95/20': (1.0, 0.95, 20, null),
    'temp-only-1.0/0.95/-': (1.0, 0.95, null, null),
    'card-full-1.0/0.95/20/p1.5': (1.0, 0.95, 20, 1.5),
  };
  const seeds = [7, 42, 1980];

  if (Platform.isMacOS && engine == InfernoEngineKind.mlx) {
    stageMlxMetallibForCliRun(warnOnMissing: true);
  }
  final inferno = Inferno.native();
  await inferno.load(engine: engine, modelPath: arguments[1]);

  stdout.writeln('variant\tseed\tclosed\ttokens\tstop\tanswer80');
  for (final MapEntry(key: name, value: (temperature, topP, topK, penalty))
      in variants.entries) {
    var closedCount = 0;
    for (final seed in seeds) {
      final buffer = StringBuffer();
      var tokens = 0;
      var stop = '?';
      await for (final event in inferno.generate(
        InfernoGenerationRequest(
          prompt: prompt,
          sampling: InfernoSamplingParameters(
            maxTokens: 4096,
            temperature: temperature,
            topP: topP,
            topK: topK,
            presencePenalty: penalty,
            seed: seed,
            stopSequences: const ['<|im_end|>'],
            stopTokenIds: const [248046, 248044],
          ),
        ),
      )) {
        switch (event) {
          case InfernoTextDelta():
            buffer.write(event.text);
          case InfernoMetricsEvent():
            tokens = event.metrics.generatedTokenCount;
          case InfernoGenerationCompleted():
            stop = event.reason.name;
        }
      }
      final text = buffer.toString();
      final closeAt = text.indexOf('</think>');
      final closed = closeAt >= 0;
      if (closed) closedCount++;
      final answer = closed ? text.substring(closeAt + '</think>'.length) : '';
      stdout.writeln(
        '$name\t$seed\t$closed\t$tokens\t$stop'
        '\t${RegExp(r'\b80\b').hasMatch(answer)}',
      );
    }
    stdout.writeln('# $name closed $closedCount/${seeds.length}');
  }
  await inferno.dispose();
}
