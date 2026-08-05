import 'package:golem_flutter/broker/hash.dart';
import 'package:golem_flutter/broker/runtime.dart';

import 'eval_spec.dart';
import 'eval_templates.dart';

/// One artifact × engine cell of the evaluation matrix.
final class EvalCombo {
  const EvalCombo({
    required this.label,
    required this.path,
    required this.engine,
  });

  final String label;
  final String path;
  final BrokerEngine engine;
}

final class EvalCheckResult {
  const EvalCheckResult({
    required this.description,
    required this.required,
    required this.passed,
  });

  final String description;
  final bool required;
  final bool passed;
}

final class EvalPromptResult {
  const EvalPromptResult({
    required this.promptId,
    this.answer = '',
    this.reasoning = '',
    this.stopReason,
    this.rawTextHash,
    this.rawTextLength = 0,
    this.metrics,
    this.checkResults = const [],
    this.error,
  });

  final String promptId;
  final String answer;
  final String reasoning;
  final String? stopReason;
  final String? rawTextHash;
  final int rawTextLength;
  final BrokerRuntimeMetrics? metrics;
  final List<EvalCheckResult> checkResults;
  final String? error;

  bool get passed =>
      error == null &&
      checkResults.where((check) => check.required).every((c) => c.passed);
}

final class EvalComboResult {
  const EvalComboResult({
    required this.combo,
    required this.loadSeconds,
    required this.promptResults,
  });

  final EvalCombo combo;
  final double loadSeconds;
  final List<EvalPromptResult> promptResults;

  /// Human-readable descriptions of every failed required check or errored
  /// generation — empty when the combo passed.
  List<String> get failures => [
    for (final result in promptResults)
      if (result.error != null)
        '${result.promptId}: ${result.error}'
      else
        for (final check in result.checkResults)
          if (check.required && !check.passed)
            '${result.promptId}: failed ${check.description} '
                '(answer: ${result.answer})',
  ];
}

/// Loads the combo's artifact, runs every prompt through the same broker
/// path the app uses, and unloads. A failed generation becomes an error row
/// and the remaining prompts still run; a failed load propagates, because
/// nothing after it could mean anything.
Future<EvalComboResult> runEvalCombo({
  required BrokerRuntime runtime,
  required EvalCombo combo,
  required EvalTemplate template,
  required List<EvalPrompt> prompts,
  void Function(String message)? onProgress,
}) async {
  final loadWatch = Stopwatch()..start();
  await runtime.load(engine: combo.engine, modelPath: combo.path);
  loadWatch.stop();
  final results = <EvalPromptResult>[];
  for (final prompt in prompts) {
    onProgress?.call(
      '[${combo.label} · ${combo.engine.name}] ${prompt.id} '
      '(${results.length + 1}/${prompts.length})',
    );
    results.add(await _runPrompt(runtime, template, prompt));
  }
  await runtime.unload();
  return EvalComboResult(
    combo: combo,
    loadSeconds: loadWatch.elapsedMilliseconds / 1000,
    promptResults: results,
  );
}

Future<EvalPromptResult> _runPrompt(
  BrokerRuntime runtime,
  EvalTemplate template,
  EvalPrompt prompt,
) async {
  final parser = template.newParser();
  final raw = StringBuffer();
  final answer = StringBuffer();
  final reasoning = StringBuffer();
  BrokerRuntimeMetrics? metrics;
  String? stopReason;

  void applyDelta(ReasoningStreamDelta delta) {
    if (delta.resetAnswer) answer.clear();
    reasoning.write(delta.reasoning);
    answer.write(delta.answer);
  }

  try {
    final events = runtime.generate(
      BrokerGenerationRequest(
        prompt: template.render(
          prompt.messages,
          reasoningEnabled: prompt.reasoningEnabled,
        ),
        sampling: BrokerSamplingParameters(
          maxTokens: prompt.maxTokens,
          temperature: prompt.temperature,
          topP: prompt.topP,
          seed: prompt.seed,
          stopSequences: template.stopSequences,
          stopTokenIds: template.stopTokenIds,
        ),
      ),
    );
    await for (final event in events) {
      switch (event) {
        case BrokerTextDelta():
          raw.write(event.text);
          applyDelta(parser.consume(event.text));
        case BrokerMetricsDelta():
          metrics = event.metrics;
        case BrokerGenerationCompleted():
          applyDelta(parser.finish());
          stopReason = event.reason.name;
      }
    }
  } on Exception catch (error) {
    return EvalPromptResult(promptId: prompt.id, error: '$error');
  }

  final answerText = answer.toString().trim();
  return EvalPromptResult(
    promptId: prompt.id,
    answer: answerText,
    reasoning: reasoning.toString().trim(),
    stopReason: stopReason,
    rawTextHash: fnv1a64(raw.toString()),
    rawTextLength: raw.length,
    metrics: metrics,
    checkResults: [
      for (final check in prompt.checks)
        EvalCheckResult(
          description: check.describe(),
          required: check.required,
          passed: check.passes(answerText),
        ),
      // Implicit on every prompt: a truncated answer can still satisfy its
      // content checks, so budget exhaustion must be visible in the check
      // list, not only in the stop column. Informational — evidence, not a
      // gate.
      EvalCheckResult(
        description: 'stopped before the token budget [informational]',
        required: false,
        passed: stopReason != BrokerStopReason.maxTokens.name,
      ),
    ],
  );
}
